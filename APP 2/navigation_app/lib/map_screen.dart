import 'package:navigation_app/models/vector2d.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';



class MapScreen extends StatefulWidget {
  final List<List<dynamic>> path;
  final List<int> startLocation;
  final double headingDegrees;
  MapScreen({required this.path, required this.startLocation, required this.headingDegrees});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<dynamic> elements = [];
  double maxX = 0;
  double maxY = 0;

  double currentHeading = 0.0;
  double headingRadians = 0.0;
  StreamSubscription<CompassEvent>? _headingSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  Vector2D imuOffset = Vector2D(0, 0);
  int stepCount = 0;

  Offset basePosition = Offset.zero;
  static const double cellSize = 50.0;

  @override
  void initState() {
    super.initState();

    basePosition = Offset(
      (widget.startLocation[0] + 0.5) * cellSize,
      (widget.startLocation[1] + 0.5) * cellSize,
    );

    fetchMapData();

    _headingSub = FlutterCompass.events?.listen((event) {
      if (event.heading != null) {
        setState(() {
          currentHeading = event.heading!;
          headingRadians = currentHeading * pi / 180;
        });
      }
    });

    _accelSub = accelerometerEvents.listen((event) {
      double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (magnitude > 12) {
        stepCount++;
        imuOffset = Vector2D(
          imuOffset.x + cos(headingRadians) * 10,
          imuOffset.y + sin(headingRadians) * 10,
        );
        print("🦶 Step $stepCount → IMU Offset: (${imuOffset.x.toStringAsFixed(2)}, ${imuOffset.y.toStringAsFixed(2)})");
      }
    });
  }


  Future<void> fetchMapData() async {
    final url = Uri.parse("https://inmaps.onrender.com/map-data");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final fetchedElements = json["elements"];
        double maxXLocal = 0, maxYLocal = 0;
        for (var el in fetchedElements) {
          final start = el["start"];
          final end = el["end"];
          maxXLocal = [start["x"], end["x"], maxXLocal].reduce((a, b) => a > b ? a : b).toDouble();
          maxYLocal = [start["y"], end["y"], maxYLocal].reduce((a, b) => a > b ? a : b).toDouble();
        }
        setState(() {
          elements = fetchedElements;
          maxX = maxXLocal + 100;
          maxY = maxYLocal + 100;
        });
      } else {
        print("❌ Failed to fetch map data. Status: \${response.statusCode}");
      }
    } catch (e) {
      print("❌ Map fetch failed: \$e");
    }
  }

  @override
  void dispose() {
    _headingSub?.cancel();
    _accelSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Map View")),
      body: elements.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : InteractiveViewer(
        minScale: 0.2,
        maxScale: 5.0,
        boundaryMargin: const EdgeInsets.all(1000),
        child: Container(
          width: maxX,
          height: maxY,
          child: CustomPaint(
            painter: MapPainter(
              elements,
              widget.path,
              basePosition,
              currentHeading,
              imuOffset,
            ),
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
  final double headingDegrees;
  final Vector2D imuOffset;

  static const double cellSize = 50.0;

  MapPainter(
      this.elements,
      this.path,
      this.basePosition,
      this.headingDegrees,
      this.imuOffset,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final paintBooth = Paint()..color = Colors.green.withOpacity(0.6);
    final paintBlocker = Paint()..color = Colors.red.withOpacity(0.6);
    final paintOther = Paint()..color = Colors.blueGrey.withOpacity(0.5);
    final paintPath = Paint()
      ..color = Colors.blue
      ..strokeWidth = 3.0;
    final paintUser = Paint()..color = Colors.blue;
    final textStyle = const TextStyle(color: Colors.black, fontSize: 10);
    final paintCone = Paint()
      ..color = Colors.blue.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    for (var el in elements) {
      final start = el["start"];
      final end = el["end"];
      final name = el["name"];
      final type = el["type"].toString().toLowerCase();
      final startOffset = Offset(start["x"].toDouble(), start["y"].toDouble());
      final endOffset = Offset(end["x"].toDouble(), end["y"].toDouble());
      final center = Offset(
        (start["x"] + end["x"]) / 2,
        (start["y"] + end["y"]) / 2,
      );

      Paint paint;
      if (type == "blocker") {
        paint = paintBlocker;
      } else if (type == "booth") {
        paint = paintBooth;
      } else {
        paint = paintOther;
      }

      canvas.drawRect(Rect.fromPoints(startOffset, endOffset), paint);

      final span = TextSpan(text: name, style: textStyle);
      final tp = TextPainter(
        text: span,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }

    final userCenter = Offset(
      basePosition.dx + imuOffset.x,
      basePosition.dy + imuOffset.y,
    );

    canvas.drawCircle(userCenter, 6, paintUser);

    const double coneLength = 80.0;
    const double coneAngle = pi / 6;
    final headingRadians = headingDegrees * pi / 180;
    final angle1 = headingRadians - coneAngle;
    final angle2 = headingRadians + coneAngle;

    final p1 = userCenter + Offset(cos(angle1), sin(angle1)) * coneLength;
    final p2 = userCenter + Offset(cos(angle2), sin(angle2)) * coneLength;

    final conePath = Path()
      ..moveTo(userCenter.dx, userCenter.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();

    canvas.drawPath(conePath, paintCone);

    if (path.isNotEmpty) {
      for (int i = 0; i < path.length - 1; i++) {
        final p1 = Offset((path[i][0] + 0.5) * cellSize, (path[i][1] + 0.5) * cellSize);
        final p2 = Offset((path[i + 1][0] + 0.5) * cellSize, (path[i + 1][1] + 0.5) * cellSize);
        canvas.drawLine(p1, p2, paintPath);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
