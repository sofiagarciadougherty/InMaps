import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:ui' as ui;
import './utils/vector2d.dart';
import './utils/custom_matrix_utils.dart';

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
  double _userRotation = 0.0;
  double _manualRotation = 0.0;
  OverlayEntry? _overlayEntry;

  final TransformationController _transformationController = TransformationController();

  late AnimationController _moveController;
  late Animation<Offset> _moveAnimation;
  Offset animatedOffset = Offset.zero;

  double currentHeading = 0.0;
  double headingRadians = 0.0;
  StreamSubscription<CompassEvent>? _headingSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  late String selectedBoothName;

  Vector2D imuOffset = Vector2D(0, 0);
  int stepCount = 0;

  Offset basePosition = Offset.zero;
  static const double cellSize = 40.0;

  void _centerOnUser() {
    final userPosition = basePosition + Offset(imuOffset.x, imuOffset.y);
    const double zoomScale = 2.0;
    final size = MediaQuery.of(context).size;
    final translation = Matrix4.identity()
      ..scale(zoomScale)
      ..translate(
        -userPosition.dx + size.width / (2 * zoomScale),
        -userPosition.dy + size.height / (2 * zoomScale),
      );
    _transformationController.value = translation;
  }

  void _centerOnUserAfterMove() {
    final userPosition = basePosition + Offset(imuOffset.x, imuOffset.y);
    const double zoomScale = 2.0;
    final size = MediaQuery.of(context).size;
    final translation = Matrix4.identity()
      ..scale(zoomScale)
      ..translate(
        -userPosition.dx + size.width / (2 * zoomScale),
        -userPosition.dy + size.height / (2 * zoomScale),
      );
    _transformationController.value = translation;
  }

  void _checkProximity() {
    if (selectedBoothName.isEmpty) return;
    
    final userX = basePosition.dx + imuOffset.x;
    final userY = basePosition.dy + imuOffset.y;
    
    final targetBooth = elements.firstWhere(
      (el) => el["name"] == selectedBoothName,
      orElse: () => null,
    );
    
    if (targetBooth != null) {
      final start = targetBooth["start"];
      final end = targetBooth["end"];
      final boothCenterX = (start["x"] + end["x"]) / 2;
      final boothCenterY = (start["y"] + end["y"]) / 2;
      
      final dx = boothCenterX - userX;
      final dy = boothCenterY - userY;
      final distance = sqrt(dx * dx + dy * dy);
      
      const proximityThreshold = 100.0;
      if (distance < proximityThreshold) {
        widget.onArrival?.call(true);
      }
    }
  }

  @override
  void initState() {
    super.initState();

    basePosition = Offset(widget.initialPosition.x, widget.initialPosition.y);
    selectedBoothName = widget.selectedBoothName;
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
        final stepDistanceInPixels = 0.7 * cellSize;
        final newOffset = Offset(
          imuOffset.x + cos(headingRadians) * stepDistanceInPixels,
          imuOffset.y + sin(headingRadians) * stepDistanceInPixels,
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
        _checkProximity();
      }
    });

    updatePath();
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
          final startX = (el["start"]["x"] as num).toDouble();
          final startY = (el["start"]["y"] as num).toDouble();
          final endX = (el["end"]["x"] as num).toDouble();
          final endY = (el["end"]["y"] as num).toDouble();
          
          maxXLocal = [startX, endX, maxXLocal].reduce((a, b) => a > b ? a : b);
          maxYLocal = [startY, endY, maxYLocal].reduce((a, b) => a > b ? a : b);
        }

        setState(() {
          elements = fetchedElements;
          maxX = maxXLocal + 100;
          maxY = maxYLocal + 100;
        });
      }
    } catch (e) {
      print("❌ Map fetch failed: $e");
    }
  }

  Future<void> updatePath() async {
    final xPixels = basePosition.dx + imuOffset.x;
    final yPixels = basePosition.dy + imuOffset.y;

    final int xGrid = (xPixels / cellSize).floor();
    final int yGrid = (yPixels / cellSize).floor();

    if (xGrid == lastGridPosition[0] && yGrid == lastGridPosition[1]) return;

    lastGridPosition = [xGrid, yGrid];

    try {
      final response = await http.post(
        Uri.parse('https://inmaps.onrender.com/path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"from_": [xGrid, yGrid], "to": selectedBoothName}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          currentPath = List<List<dynamic>>.from(data['path']);
        });
      }
    } catch (e) {
      print('❌ Path fetch failed: $e');
    }
  }

  void _showBoothDescription(dynamic booth, Offset position) {
    _removeOverlay();
    
    final screenSize = MediaQuery.of(context).size;
    
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: (screenSize.width - 300) / 2,
        top: (screenSize.height - 150) / 2,
        child: Material(
          elevation: 8.0,
          borderRadius: BorderRadius.circular(8.0),
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10.0,
                  spreadRadius: 1.0,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      booth["type"] == "booth" ? Icons.store : 
                      booth["type"] == "blocker" ? Icons.block : Icons.info,
                      color: booth["type"] == "booth" ? Colors.green : 
                             booth["type"] == "blocker" ? Colors.red : Colors.blueGrey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        booth["name"],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16.0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8.0),
                Text(
                  booth["description"] ?? "No description available",
                  style: const TextStyle(fontSize: 14.0),
                ),
                const SizedBox(height: 8.0),
                Align(
                  alignment: Alignment.centerRight,
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
    );
    
    Overlay.of(context).insert(_overlayEntry!);
  }
  
  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _moveController.dispose();
    _transformationController.dispose();
    _headingSub?.cancel();
    _accelSub?.cancel();
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/images/logo.png'),
        ),
        title: const Text("Map View"),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _centerOnUser,
            tooltip: 'Center on my location',
          ),
        ],
      ),
      body: elements.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GestureDetector(
                  onScaleUpdate: (details) {
                    if (details.pointerCount >= 2) {
                      print("🔥 Scale detected with ${details.pointerCount} fingers, rotation=${details.rotation}");
                      double rotationDelta = details.rotation;
                      if (rotationDelta.abs() > 0.14) {
                        setState(() {
                          _manualRotation += rotationDelta*0.1;
                          print("🌀 MUCH smoother rotation: $_manualRotation radians (${_manualRotation * 180 / pi} degrees)");
                        });
                      }
                    }
                    if (_manualRotation.abs() < 0.05) { 
                      setState(() {
                        _manualRotation = 0.0;
                        print("🔄 Snapped back to north");
                      });
                    }
                  },
                  onTapUp: (details) {
                    final RenderBox renderBox = context.findRenderObject() as RenderBox;
                    final Matrix4 transform = _transformationController.value.clone();
                    final Matrix4 inverseTransform = Matrix4.inverted(transform);
                    final Offset localPosition = CustomMatrixUtils.transformPoint(
                      inverseTransform,
                      details.localPosition,
                    );

                    for (var element in elements) {
                      final start = element["start"];
                      final end = element["end"];
                      final rect = Rect.fromPoints(
                        Offset(start["x"].toDouble(), start["y"].toDouble()),
                        Offset(end["x"].toDouble(), end["y"].toDouble()),
                      );

                      if (rect.contains(localPosition)) {
                        _showBoothDescription(element, details.globalPosition);
                        break;
                      }
                    }
                  },
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 0.2,
                    maxScale: 5.0,
                    boundaryMargin: const EdgeInsets.all(1000),
                    panEnabled: true,
                    scaleEnabled: true,
                    clipBehavior: Clip.none,
                    constrained: false,
                    child: Container(
                      width: maxX,
                      height: maxY,
                      color: Colors.white,
                      child: CustomPaint(
                        size: Size(maxX, maxY),
                        painter: MapPainter(
                          elements,
                          currentPath,
                          basePosition,
                          currentHeading,
                          animatedOffset,
                          _manualRotation,
                        ),
                      ),
                    ),
                  ),
                ),

                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton(
                    onPressed: _centerOnUser,
                    child: const Icon(Icons.my_location),
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

  static const double cellSize = 40.0;

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
    print("🖌️ Repainting with manualRotation = $manualRotation radians (${manualRotation * 180 / pi} degrees)");

    final backgroundPaint = Paint()..color = const Color(0xFFF9F9F9);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    final userCenter = basePosition + animatedOffset;

    canvas.save();
    canvas.translate(userCenter.dx, userCenter.dy);
    canvas.rotate(manualRotation);
    canvas.translate(-userCenter.dx, -userCenter.dy);

    final paintBooth = Paint()..color = Colors.green.withOpacity(0.7);
    final paintBlocker = Paint()..color = Colors.red.withOpacity(0.6);
    final paintOther = Paint()..color = Colors.blueGrey.withOpacity(0.5);
    final paintPathGlow = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;
    final paintPath = Paint()
      ..color = Colors.blue
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    final paintUserBorder = Paint()..color = Colors.white;
    final paintUser = Paint()..color = Colors.blue;
    final paintCone = Paint()
      ..color = Colors.blue.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    // --- Draw booths, blockers, others ---
    for (var el in elements) {
      final start = el["start"];
      final end = el["end"];
      final type = el["type"].toString().toLowerCase();
      final startOffset = Offset(start["x"].toDouble(), start["y"].toDouble());
      final endOffset = Offset(end["x"].toDouble(), end["y"].toDouble());

      Paint paint;
      if (type == "blocker") paint = paintBlocker;
      else if (type == "booth") paint = paintBooth;
      else paint = paintOther;

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromPoints(startOffset, endOffset), const Radius.circular(12)),
        paint,
      );
    }

    // --- Draw path ---
    if (path.isNotEmpty) {
      final pathPaint = Paint()
        ..color = Colors.blue
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final pathGlowPaint = Paint()
        ..color = Colors.white.withOpacity(0.5)
        ..strokeWidth = 6.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final pathPoints = path.map((point) => 
        Offset((point[0] + 0.5) * cellSize, (point[1] + 0.5) * cellSize)
      ).toList();

      if (pathPoints.length >= 2) {
        // Draw path segments
        for (int i = 0; i < pathPoints.length - 1; i++) {
          // Draw glow effect
          canvas.drawLine(pathPoints[i], pathPoints[i + 1], pathGlowPaint);
          // Draw actual path
          canvas.drawLine(pathPoints[i], pathPoints[i + 1], pathPaint);
        }
      }
    }

    // --- Draw user ---
    canvas.drawCircle(userCenter, 10, paintUserBorder);
    canvas.drawCircle(userCenter, 6, paintUser);

    // --- Draw cone ---
    const double coneLength = 80.0;
    const double coneAngle = pi / 6;
    final headingRadians = headingDegrees * pi / 180;
    final p1 = userCenter + Offset(cos(headingRadians - coneAngle), sin(headingRadians - coneAngle)) * coneLength;
    final p2 = userCenter + Offset(cos(headingRadians + coneAngle), sin(headingRadians + coneAngle)) * coneLength;

    final conePath = Path()
      ..moveTo(userCenter.dx, userCenter.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(conePath, paintCone);

    // 🔥🔥 Draw booth labels now (inside rotated canvas!)
    final textStyle = const TextStyle(
      color: Colors.black,
      fontSize: 12,
      fontWeight: FontWeight.bold,
    );

    for (var el in elements) {
      final start = el["start"];
      final end = el["end"];
      final name = el["name"];
      final center = Offset(
        (start["x"].toDouble() + end["x"].toDouble()) / 2,
        (start["y"].toDouble() + end["y"].toDouble()) / 2,
      );

      // --- Counter-rotate text ---
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-manualRotation); // 👈 counter-rotate the label back
      canvas.translate(-center.dx, -center.dy);

      final tp = TextPainter(
        text: TextSpan(text: name, style: textStyle),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));

      canvas.restore();
    }

    canvas.restore(); // end overall rotation
  }

  @override
  bool shouldRepaint(MapPainter oldDelegate) => 
    oldDelegate.manualRotation != manualRotation ||
    oldDelegate.elements != elements ||
    oldDelegate.path != path ||
    oldDelegate.basePosition != basePosition ||
    oldDelegate.headingDegrees != headingDegrees ||
    oldDelegate.animatedOffset != animatedOffset;
}