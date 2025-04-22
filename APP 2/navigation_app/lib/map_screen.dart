import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:http/http.dart' as http;
import './utils/vector2d.dart';

class MapScreen extends StatefulWidget {
  final List<List<dynamic>> path;
  final List<int> startLocation;
  final double headingDegrees;
  final Vector2D initialPosition;
  final String selectedBoothName;
  final Function(bool)? onArrival;

  const MapScreen({
    Key? key,
    required this.path,
    required this.startLocation,
    required this.headingDegrees,
    required this.initialPosition,
    required this.selectedBoothName,
    this.onArrival,
  }) : super(key: key);

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  List<dynamic> elements = [];
  double maxX = 0, maxY = 0;

  // for IMU step‑based movement
  Offset basePosition = Offset.zero;
  Offset animatedOffset = Offset.zero;
  double manualRotation = 0.0;

  // path updating
  List<List<dynamic>> currentPath = [];
  StreamSubscription<CompassEvent>? _headingSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  late AnimationController _moveController;
  late Animation<Offset> _moveAnimation;

  @override
  void initState() {
    super.initState();

    // set up initial base & path
    basePosition = Offset(widget.initialPosition.x, widget.initialPosition.y);
    currentPath = List.from(widget.path);

    // fetch the map geometry
    _fetchMapData();

    // animate steps
    _moveController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))
      ..addListener(() {
        setState(() => animatedOffset = _moveAnimation.value);
      });

    // listen for rotation gestures
    _headingSub = FlutterCompass.events?.listen((event) {
      // not used here, but could drive cone if desired
    });

    // detect "steps" via accelerometer
    _accelSub = accelerometerEvents.listen((evt) {
      final mag = sqrt(evt.x * evt.x + evt.y * evt.y + evt.z * evt.z);
      if (mag > 12) {
        final step = 0.7 * MapPainter.cellSize;
        // rotate step vector by -manualRotation so "forward" is map‑north
        final corrected = Offset(
          cos(-manualRotation) * step,
          sin(-manualRotation) * step,
        );
        final start = animatedOffset;
        final end = start + corrected;
        _moveAnimation = Tween<Offset>(begin: start, end: end).animate(CurvedAnimation(
          parent: _moveController,
          curve: Curves.easeOut,
        ));
        _moveController.forward(from: 0);
        // optionally re‑request path here…
      }
    });
  }

  Future<void> _fetchMapData() async {
    final url = Uri.parse("https://inmaps.onrender.com/map-data");
    try {
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        final jsonBody = jsonDecode(resp.body);
        final fetched = jsonBody["elements"] as List<dynamic>;

        // find canvas extents
        double mx = 0, my = 0;
        for (var el in fetched) {
          final sx = (el["start"]["x"] as num).toDouble();
          final sy = (el["start"]["y"] as num).toDouble();
          final ex = (el["end"]["x"]   as num).toDouble();
          final ey = (el["end"]["y"]   as num).toDouble();
          mx = max(mx, max(sx, ex));
          my = max(my, max(sy, ey));
        }

        setState(() {
          elements = fetched;
          maxX = mx + 50;
          maxY = my + 50;
        });
      }
    } catch (e) {
      debugPrint("❌ Map fetch error: $e");
    }
  }

  @override
  void dispose() {
    _headingSub?.cancel();
    _accelSub?.cancel();
    _moveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Image.asset('assets/images/logo.png', height: 45),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: elements.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : InteractiveViewer(
        boundaryMargin: const EdgeInsets.all(1000),
        minScale: 0.2,
        maxScale: 5,
        panEnabled: true,
        scaleEnabled: true,
        child: CustomPaint(
          size: Size(maxX, maxY),
          painter: MapPainter(
            elements: elements,
            path: widget.path,
            basePosition: basePosition,
            animatedOffset: animatedOffset,
            headingDegrees: widget.headingDegrees,
            manualRotation: manualRotation,
          ),
        ),
      ),
    );
  }
}

class MapPainter extends CustomPainter {
  final List<dynamic> elements;
  final List<List<dynamic>> path;
  final Offset basePosition;
  final Offset animatedOffset;
  final double headingDegrees;
  final double manualRotation;

  static const double cellSize = 40.0;

  MapPainter({
    required this.elements,
    required this.path,
    required this.basePosition,
    required this.animatedOffset,
    required this.headingDegrees,
    required this.manualRotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1) compute user center
    final userCenter = basePosition + animatedOffset;

    // 2) rotate the map around the user
    canvas.save();
    canvas.translate(userCenter.dx, userCenter.dy);
    canvas.rotate(manualRotation);
    canvas.translate(-userCenter.dx, -userCenter.dy);

    // 3) define paints
    final boothPaint = Paint()..color = Colors.blue.withOpacity(0.7);
    final blockerPaint = Paint()..color = Colors.black.withOpacity(0.7);
    final yellowZonePaint = Paint()..color = Colors.yellow.withOpacity(0.3);

    final paintPathGlow = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    final paintPath = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final paintUserBorder = Paint()..color = Colors.white;
    final paintUser = Paint()..color = const Color(0xFF008C9E);

    // 4) draw yellow zones
    for (var el in elements) {
      final t = (el['type'] as String).toLowerCase();
      if (t == 'yellow zone') {
        // build a simple rect path from start → end
        final sx = (el['start']['x'] as num).toDouble();
        final sy = (el['start']['y'] as num).toDouble();
        final ex = (el['end']['x']   as num).toDouble();
        final ey = (el['end']['y']   as num).toDouble();
        final rect = Rect.fromLTRB(sx, sy, ex, ey);
        canvas.drawRect(rect, yellowZonePaint);
      }
    }

    // 5) draw booths and blockers
    for (var el in elements) {
      final t = (el['type'] as String).toLowerCase();
      if (t.contains('zone') || t == 'beacon') continue;

      final sx = (el['start']['x'] as num).toDouble();
      final sy = (el['start']['y'] as num).toDouble();
      final ex = (el['end']['x']   as num).toDouble();
      final ey = (el['end']['y']   as num).toDouble();
      final rect = Rect.fromLTRB(sx, sy, ex, ey);

      if (t == 'booth') {
        canvas.drawRect(rect, boothPaint);
      } else if (t == 'blocker') {
        canvas.drawRect(rect, blockerPaint);
      }
    }

    // 7) draw your navigation path
    if (path.isNotEmpty) {
      for (int i = 0; i < path.length - 1; i++) {
        final p1 = Offset((path[i][0] + 0.5) * cellSize, (path[i][1] + 0.5) * cellSize);
        final p2 = Offset((path[i + 1][0] + 0.5) * cellSize, (path[i + 1][1] + 0.5) * cellSize);
        canvas.drawLine(p1, p2, paintPathGlow);
        canvas.drawLine(p1, p2, paintPath);
      }
    }

    // 8) draw the user dot
    canvas.drawCircle(userCenter, 10, paintUserBorder);
    canvas.drawCircle(userCenter, 6, paintUser);

    // 9) draw booth/blocker labels
    final textStyle = const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w500);
    for (var el in elements) {
      final t = (el['type'] as String).toLowerCase();
      if (!(t == 'booth' || t == 'blocker')) continue;

      final sx = (el['start']['x'] as num).toDouble();
      final sy = (el['start']['y'] as num).toDouble();
      final ex = (el['end']['x']   as num).toDouble();
      final ey = (el['end']['y']   as num).toDouble();
      final center = Offset((sx + ex) / 2, (sy + ey) / 2);
      final name = el['name'].toString();
      final label = name.substring(0, min(3, name.length));

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-manualRotation);
      canvas.translate(-center.dx, -center.dy);

      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
      canvas.restore();
    }

    // 10) restore before cone
    canvas.restore();

    // 11) draw the cone (always upright)
    const coneLen = 80.0, coneAng = pi / 6;
    final hr = headingDegrees * pi / 180;
    final c1 = userCenter + Offset(cos(hr - coneAng), sin(hr - coneAng)) * coneLen;
    final c2 = userCenter + Offset(cos(hr + coneAng), sin(hr + coneAng)) * coneLen;
    final cone = Path()
      ..moveTo(userCenter.dx, userCenter.dy)
      ..lineTo(c1.dx, c1.dy)
      ..lineTo(c2.dx, c2.dy)
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..color = const Color(0xFF008C9E).withOpacity(0.15)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant MapPainter old) => true;
}
