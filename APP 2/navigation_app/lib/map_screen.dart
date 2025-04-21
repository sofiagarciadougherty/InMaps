import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import './utils/vector2d.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

class MapScreen extends StatefulWidget {
  final List<List<dynamic>> path;
  final List<int> startLocation;
  final double headingDegrees;
  final Vector2D initialPosition;
  final String selectedBoothName;
  final Function(bool)? onArrival;

  MapScreen({
    required this.path,
    required this.startLocation,
    required this.headingDegrees,
    required this.initialPosition,
    required this.selectedBoothName,
    this.onArrival,
  });

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  List<dynamic> elements = [];
  double maxX = 0;
  double maxY = 0;
  List<int> lastGridPosition = [-1, -1];
  List<List<dynamic>> currentPath = [];
  double manualRotationAngle = 0.0;


  final TransformationController _transformationController = TransformationController();
  late AnimationController _moveController;
  late Animation<Offset> _moveAnimation;
  Offset animatedOffset = Offset.zero;

  double currentHeading = 0.0;
  double headingRadians = 0.0;
  StreamSubscription<CompassEvent>? _headingSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  // Booth tap & arrival overlays
  OverlayEntry? _overlayEntry;
  OverlayEntry? _arrivalOverlay;
  bool hasNotifiedArrival = false;

  Vector2D imuOffset = Vector2D(0, 0);
  int stepCount = 0;

  Offset basePosition = Offset.zero;
  static const double cellSize = 40.0;

  @override
  void initState() {
    super.initState();

    basePosition = Offset(widget.initialPosition.x, widget.initialPosition.y);
    currentPath = [
          widget.startLocation,
          ...widget.path
        ].map<List<dynamic>>((row) => List<dynamic>.from(row)).toList();
    currentPath = List.from(widget.path);

    _moveController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..addListener(() {
      setState(() {
        animatedOffset = _moveAnimation.value;
      });
    });

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
        final stepDistance = 0.7 * cellSize;
        final correctedHeading = headingRadians - _getMapRotationAngle();
        final newOffset = Offset(
          imuOffset.x + cos(correctedHeading) * stepDistance,
          imuOffset.y + sin(correctedHeading) * stepDistance,
        );

        _moveAnimation = Tween<Offset>(
          begin: Offset(imuOffset.x, imuOffset.y),
          end: newOffset,
        ).animate(CurvedAnimation(
          parent: _moveController,
          curve: Curves.easeOut,
        ));

        _moveController.forward(from: 0);

        imuOffset = Vector2D(newOffset.dx, newOffset.dy);
        updatePath();
        _centerOnUserAfterMove();
        _checkArrival();
      }
    });
  }

  Future<void> fetchMapData() async {
    final url = Uri.parse("https://inmaps.onrender.com/map-data");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final fetched = json["elements"];
        double maxXLocal = 0, maxYLocal = 0;
        for (var el in fetched) {
          final sx = (el["start"]["x"] as num).toDouble();
          final sy = (el["start"]["y"] as num).toDouble();
          final ex = (el["end"]["x"] as num).toDouble();
          final ey = (el["end"]["y"] as num).toDouble();
          maxXLocal = [sx, ex, maxXLocal].reduce((a, b) => a > b ? a : b);
          maxYLocal = [sy, ey, maxYLocal].reduce((a, b) => a > b ? a : b);
        }
        setState(() {
          elements = fetched;
          maxX = maxXLocal + 100;
          maxY = maxYLocal + 100;
        });
      }
    } catch (e) {
      print("❌ Map fetch failed: $e");
    }
  }

  Future<void> updatePath() async {
    final px = basePosition.dx + imuOffset.x;
    final py = basePosition.dy + imuOffset.y;
    final xg = (px / cellSize).floor();
    final yg = (py / cellSize).floor();
    if (xg == lastGridPosition[0] && yg == lastGridPosition[1]) return;
    lastGridPosition = [xg, yg];

    try {
      final resp = await http.post(
        Uri.parse('https://inmaps.onrender.com/path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"from_": [xg, yg], "to": widget.selectedBoothName}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          currentPath = List<List<dynamic>>.from(data['path']);
        });
      }
    } catch (e) {
      print('❌ Path fetch failed: $e');
    }
  }

  // Booth description overlay
  void _showBoothDescription(dynamic booth) {
    _removeOverlay();
    final screen = MediaQuery.of(context).size;
    _overlayEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: 0,
        right: 0,
        top: 0,
        bottom: 0,
        child: Material(
          color: Colors.black54,
          child: Center(
            child: Container(
              width: 300,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF008C9E).withOpacity(0.8),
                          const Color(0xFF008C9E),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          booth["type"] == "booth" ? Icons.store :
                          booth["type"] == "blocker" ? Icons.block : Icons.info,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            booth["name"],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      booth["description"] ?? "No description available",
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextButton(
                      onPressed: _removeOverlay,
                      child: const Text("Close"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // Arrival notification
  void _checkArrival() {
    if (hasNotifiedArrival) return;
    final userCenter = Offset(basePosition.dx + imuOffset.x, basePosition.dy + imuOffset.y);
    for (var el in elements) {
      if (el["type"] == "booth" && el["name"] == widget.selectedBoothName) {
        final sx = el["start"]["x"] as num;
        final sy = el["start"]["y"] as num;
        final ex = el["end"]["x"] as num;
        final ey = el["end"]["y"] as num;
        final boothCenter = Offset((sx + ex)/2, (sy + ey)/2);
        final dx = boothCenter.dx - userCenter.dx;
        final dy = boothCenter.dy - userCenter.dy;
        if (sqrt(dx*dx + dy*dy) < 20) {
          hasNotifiedArrival = true;
          _showArrivalNotification();
          widget.onArrival?.call(true);
          break;
        }
      }
    }
  }

  void _showArrivalNotification() {
    _removeArrivalOverlay();
    _arrivalOverlay = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(context).size.height * 0.1,
        left: 0, right: 0,
        child: Center(
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 500),
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (c, v, child) => Transform.scale(
              scale: v,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal:24, vertical:16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade400, Colors.green.shade600],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.white, size:28),
                    const SizedBox(width:12),
                    Text("You've arrived at ${widget.selectedBoothName}!", style: const TextStyle(color: Colors.white, fontSize:18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_arrivalOverlay!);
    Future.delayed(const Duration(seconds:3), _removeArrivalOverlay);
  }

  void _removeArrivalOverlay() {
    _arrivalOverlay?.remove();
    _arrivalOverlay = null;
  }

  double _getMapRotationAngle() {
  return manualRotationAngle;
}


  void _centerOnUser() {
    final user = Offset(basePosition.dx + imuOffset.x, basePosition.dy + imuOffset.y);
    const zoom = 2.0;
    final size = MediaQuery.of(context).size;
    final matrix = Matrix4.identity()
      ..scale(zoom)
      ..translate(-user.dx + size.width/(2*zoom), -user.dy + size.height/(2*zoom));
    _transformationController.value = matrix;
  }

  void _centerOnUserAfterMove() {
    final user = Offset(basePosition.dx + imuOffset.x, basePosition.dy + imuOffset.y);
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final size = MediaQuery.of(context).size;
    final matrix = Matrix4.identity()
      ..scale(scale)
      ..translate(-user.dx + size.width/(2*scale), -user.dy + size.height/(2*scale));
    _transformationController.value = matrix;
  }

  @override
  void dispose() {
    _moveController.dispose();
    _transformationController.dispose();
    _headingSub?.cancel();
    _accelSub?.cancel();
    _removeOverlay();
    _removeArrivalOverlay();
    super.dispose();
  }
  Offset _rotatePoint(Offset point, Offset center, double angle) {
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    final rotatedX = dx * cos(angle) - dy * sin(angle);
    final rotatedY = dx * sin(angle) + dy * cos(angle);
    return Offset(rotatedX + center.dx, rotatedY + center.dy);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(children: [Image.asset('assets/images/logo.png', height:45)]),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: elements.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 0.2,
                  maxScale: 5.0,
                  boundaryMargin: const EdgeInsets.all(1000),
                  panEnabled: true,
                  scaleEnabled: true,
                  clipBehavior: Clip.none,
                  constrained: false,
                  onInteractionUpdate: (details) {
                    if (details.pointerCount == 2) {
                      final scale = _transformationController.value.getMaxScaleOnAxis();
                      final dampeningFactor = 0.02 / scale.clamp(1.0, 5.0);
                      setState(() {
                        manualRotationAngle += details.rotation * dampeningFactor;  
                        manualRotationAngle = manualRotationAngle.clamp(-pi, pi);
                      });
                    }
                  },
                  child: Container(
                    width: maxX,
                    height: maxY,
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: Size(maxX, maxY),
                          painter: MapPainter(
                            elements,
                            currentPath,
                            Offset(basePosition.dx, basePosition.dy),
                            currentHeading,
                            animatedOffset,
                            manualRotationAngle,
                          ),
                        ),
                        Positioned.fill(
                          child: GestureDetector(
                            onTapDown: (details) {
                              // 1. Get tap position
                              Offset tapPos = details.localPosition;

                              // 2. Calculate the center point (for rotation reference)
                              final userCenter = Offset(basePosition.dx + animatedOffset.dx, basePosition.dy + animatedOffset.dy);

                              // 3. Undo the map rotation for the tap
                              final rotatedTapPos = _rotatePoint(tapPos, userCenter, -manualRotationAngle);

                              // 4. Now check booths normally using rotatedTapPos!
                              for (var el in elements) {
                                if (el["type"].toString().toLowerCase() != "booth") continue;

                                final start = el["start"];
                                final end = el["end"];
                                final startOffset = Offset(start["x"].toDouble(), start["y"].toDouble());
                                final endOffset = Offset(end["x"].toDouble(), end["y"].toDouble());
                                final boothRect = Rect.fromPoints(startOffset, endOffset);

                                if (boothRect.contains(rotatedTapPos)) {
                                  print("🎯 Correct booth tapped: ${el['name']}");
                                  _showBoothDescription(el);
                                  return;
                                }
                              }
                              _removeOverlay();
                            },

                            child: Container(color: Colors.transparent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton(
                    onPressed: _centerOnUser,
                    backgroundColor: const Color(0xFF008C9E),
                    child: const Icon(Icons.my_location, color: Colors.white),
                    tooltip: 'Center on my location',
                  ),
                ),
              ],
            ),

    );
  }
}

class MapPainter extends CustomPainter {
  final List<dynamic> elements;
  final List<List<dynamic>> path;
  final Offset basePosition;
  final double headingDegrees;
  final Offset animatedOffset;
  final double manualRotation;

  static const double cellSize =40.0;

  MapPainter(
      this.elements,
      this.path,
      this.basePosition,
      this.headingDegrees,
      this.animatedOffset,
      this.manualRotation,
      );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0,0,size.width,size.height), Paint()..color = Colors.white);
    final userCenter = basePosition + animatedOffset;
    canvas.save();
    canvas.translate(userCenter.dx, userCenter.dy);
    canvas.rotate(manualRotation);
    canvas.translate(-userCenter.dx, -userCenter.dy);

    final paintBooth = Paint()..color = const Color(0xFF008C9E).withOpacity(0.15);
    final paintStairs = Paint()..color = Colors.red.withOpacity(0.2);
    final paintWalkable = Paint()..color = Colors.grey.withOpacity(0.1);
    final paintYellowZone = Paint()..color = Colors.yellow.withOpacity(0.15);
    final paintPathGlow = Paint()
      ..color = const Color(0xFF008C9E).withOpacity(0.3)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;
    final paintPath = Paint()
      ..color = const Color(0xFF008C9E)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    final paintUserBorder = Paint()..color = Colors.white;
    final paintUser = Paint()..color = const Color(0xFF008C9E);

    // Draw walkable areas first (as shadows)
    for (var el in elements) {
      final type = (el["type"] as String).toLowerCase();
      if (type == "walkable") {
        final start = el["start"];
        final end = el["end"];
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromPoints(
              Offset(start["x"].toDouble(), start["y"].toDouble()),
              Offset(end["x"].toDouble(), end["y"].toDouble())
            ),
            const Radius.circular(12),
          ),
          paintWalkable,
        );
      }
    }

    // Draw elements
    for (var el in elements) {
      final type = (el["type"] as String).toLowerCase();
      final start = el["start"];
      final end = el["end"];
      final startOffset = Offset(start["x"].toDouble(), start["y"].toDouble());
      final endOffset = Offset(end["x"].toDouble(), end["y"].toDouble());

      Paint paint;
      if (type == "stairs") {
        paint = paintStairs;
      } else if (type == "booth") {
        paint = Paint()..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF008C9E).withOpacity(0.2), const Color(0xFF008C9E).withOpacity(0.3)],
        ).createShader(Rect.fromPoints(startOffset, endOffset));
      } else if (type == "yellow_zone") {
        paint = paintYellowZone;
      } else {
        continue;
      }

      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromPoints(startOffset, endOffset),
              const Radius.circular(12)
          ),
          paint
      );

      if (type == "booth") {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromPoints(startOffset, endOffset),
                const Radius.circular(12)
            ),
            Paint()
              ..color = const Color(0xFF008C9E).withOpacity(0.3)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
        );
      }
    }
    // Draw path
    if (path.isNotEmpty) {
      for (int i=0; i<path.length-1; i++) {
        final p1 = Offset((path[i][0]+0.5)*cellSize, (path[i][1]+0.5)*cellSize);
        final p2 = Offset((path[i+1][0]+0.5)*cellSize, (path[i+1][1]+0.5)*cellSize);
        canvas.drawLine(p1,p2,paintPathGlow);
        canvas.drawLine(p1,p2,paintPath);
      }
    }
    // Draw user
    canvas.drawCircle(userCenter,10,paintUserBorder);
    canvas.drawCircle(userCenter,6,paintUser);
    // Draw labels
    final textStyle = const TextStyle(color: Colors.black87, fontSize:12, fontWeight:FontWeight.w500);
    for (var el in elements) {
      final type = (el["type"] as String).toLowerCase();

      // Skip zones and beacons for labels too
      if (!["booth", "blocker"].contains(type)) continue;

      final start = el["start"];
      final end = el["end"];
      final name = el["name"].toString().substring(0, min(3, el["name"].toString().length));
      final center = Offset((start["x"].toDouble()+end["x"].toDouble())/2, (start["y"].toDouble()+end["y"].toDouble())/2);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-manualRotation);
      canvas.translate(-center.dx, -center.dy);
      final tp = TextPainter(text: TextSpan(text: name, style: textStyle), textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, center-Offset(tp.width/2,tp.height/2));
      canvas.restore();
    }
    canvas.restore();
    // Draw cone unchanged by map rotation
    const coneLen=80.0, coneAng=pi/6;
    final hr = headingDegrees*pi/180;
    final c1 = userCenter+Offset(cos(hr-coneAng),sin(hr-coneAng))*coneLen;
    final c2 = userCenter+Offset(cos(hr+coneAng),sin(hr+coneAng))*coneLen;
    final cone = Path()..moveTo(userCenter.dx,userCenter.dy)..lineTo(c1.dx,c1.dy)..lineTo(c2.dx,c2.dy)..close();
    canvas.drawPath(cone, Paint()..color=const Color(0xFF008C9E).withOpacity(0.15)..style=PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(MapPainter old) => true;
}