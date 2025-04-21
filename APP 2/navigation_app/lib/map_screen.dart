import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import './utils/vector2d.dart';

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

class _MapScreenState extends State<MapScreen> {
  List<dynamic> elements = [];
  double maxX = 0;
  double maxY = 0;
  List<int> lastGridPosition = [-1, -1];
  List<List<dynamic>> currentPath = [];

  double currentHeading = 0.0;
  double headingRadians = 0.0;
  StreamSubscription<CompassEvent>? _headingSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  late String selectedBoothName;

  Vector2D imuOffset = Vector2D(0, 0);
  int stepCount = 0;

  Offset basePosition = Offset.zero;
  static const double cellSize = 40.0;
  
  // Add variables for booth tap handling
  dynamic tappedBooth = null;
  OverlayEntry? _overlayEntry;

  bool hasNotifiedArrival = false;
  OverlayEntry? _arrivalOverlay;

  @override
  void initState() {
    super.initState();

    basePosition = Offset(
      widget.initialPosition.x,
      widget.initialPosition.y,
    );
    selectedBoothName = widget.selectedBoothName;
    currentPath = List.from(widget.path);
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
        imuOffset = Vector2D(
          imuOffset.x + cos(headingRadians) * stepDistanceInPixels,
          imuOffset.y + sin(headingRadians) * stepDistanceInPixels,
        );
        print("🦶 Step $stepCount → IMU Offset: (${(imuOffset.x/cellSize).toStringAsFixed(2)}m, ${(imuOffset.y/cellSize).toStringAsFixed(2)}m)");
        updatePath();
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

  // Add method to show booth description overlay
  void _showBoothDescription(dynamic booth, Offset position) {
    // Remove any existing overlay
    _removeOverlay();
    
    // Get the screen size
    final screenSize = MediaQuery.of(context).size;
    
    // Create the overlay entry
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        // Center the overlay on the screen
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
    
    // Insert the overlay
    Overlay.of(context).insert(_overlayEntry!);
  }
  
  // Add method to remove the overlay
  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _checkArrival() {
    if (hasNotifiedArrival) return;

    final userCenter = Offset(
      basePosition.dx + imuOffset.x,
      basePosition.dy + imuOffset.y,
    );

    // Find the target booth
    for (var el in elements) {
      if (el["type"].toString().toLowerCase() == "booth" && 
          el["name"] == widget.selectedBoothName) {
        final start = el["start"];
        final end = el["end"];
        final boothCenter = Offset(
          (start["x"] + end["x"]) / 2,
          (start["y"] + end["y"]) / 2,
        );

        // Calculate distance to booth
        final dx = boothCenter.dx - userCenter.dx;
        final dy = boothCenter.dy - userCenter.dy;
        final distance = sqrt(dx * dx + dy * dy);

        // If within 0.5 meters (20 pixels), notify arrival
        if (distance < 20) {
          hasNotifiedArrival = true;
          _showArrivalNotification();
          // Notify the game screen about arrival
          widget.onArrival?.call(true);
          break;
        }
      }
    }
  }

  void _showArrivalNotification() {
    _removeArrivalOverlay();
    
    _arrivalOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).size.height * 0.1,
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 500),
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.green.shade400,
                          Colors.green.shade600,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 12,
                          spreadRadius: 2,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "You've arrived at ${widget.selectedBoothName}!",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    
    Overlay.of(context).insert(_arrivalOverlay!);
    
    // Remove the notification after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      _removeArrivalOverlay();
    });
  }

  void _removeArrivalOverlay() {
    if (_arrivalOverlay != null) {
      _arrivalOverlay!.remove();
      _arrivalOverlay = null;
    }
  }

  @override
  void dispose() {
    _headingSub?.cancel();
    _accelSub?.cancel();
    _removeOverlay();
    _removeArrivalOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Map View")),
      body: elements.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                InteractiveViewer(
                  minScale: 0.2,
                  maxScale: 5.0,
                  boundaryMargin: const EdgeInsets.all(100),
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
                        imuOffset,
                      ),
                    ),
                  ),
                ),
                // Add a transparent layer for booth taps
                Positioned.fill(
                  child: GestureDetector(
                    onTapDown: (details) {
                      // Check if a booth was tapped
                      bool boothTapped = false;
                      for (var el in elements) {
                        // Skip elements with type "beacon"
                        if (el["type"].toString().toLowerCase() == "beacon") {
                          continue;
                        }
                        
                        final start = el["start"];
                        final end = el["end"];
                        final startOffset = Offset(start["x"].toDouble(), start["y"].toDouble());
                        final endOffset = Offset(end["x"].toDouble(), end["y"].toDouble());
                        final rect = Rect.fromPoints(startOffset, endOffset);
                        
                        if (rect.contains(details.localPosition)) {
                          boothTapped = true;
                          // Calculate the center of the booth for reference
                          final boothCenter = Offset(
                            (start["x"] + end["x"]) / 2,
                            (start["y"] + end["y"]) / 2,
                          );
                          _showBoothDescription(el, boothCenter);
                          break;
                        }
                      }
                      
                      // If no booth was tapped and overlay is showing, dismiss it
                      if (!boothTapped && _overlayEntry != null) {
                        _removeOverlay();
                      }
                    },
                    child: Container(
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
  Future<void> updatePath() async {
    final xPixels = basePosition.dx + imuOffset.x;
    final yPixels = basePosition.dy + imuOffset.y;

    final int xGrid = (xPixels / cellSize).floor();
    final int yGrid = (yPixels / cellSize).floor();

    if (xGrid == lastGridPosition[0] && yGrid == lastGridPosition[1]) {
      // User hasn't moved to a new grid cell → don't recalculate
      return;
    }

    lastGridPosition = [xGrid, yGrid];

    try {
      final response = await http.post(
        Uri.parse('https://inmaps.onrender.com/path'), // <<-- your backend
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "from_": [xGrid, yGrid],
          "to": selectedBoothName,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          currentPath = List<List<dynamic>>.from(data['path']);
        });

      } else {
        print('❌ Failed to fetch path: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Path fetch failed: $e');
    }
  }
}




class MapPainter extends CustomPainter {
  final List<dynamic> elements;
  final List<List<dynamic>> path;
  final Offset basePosition;
  final double headingDegrees;
  final Vector2D imuOffset;

  static const double cellSize = 40.0;

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
      // Skip elements with type "beacon"
      if (el["type"].toString().toLowerCase() == "beacon") {
        continue;
      }
      
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

    // Draw grid on top
    final gridPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final maxGridX = size.width;
    final maxGridY = size.height;

    // Draw vertical grid lines
    for (double x = 0; x <= maxGridX; x += cellSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, maxGridY),
        gridPaint,
      );

      // Add coordinates every 80 pixels (2 meters)
      if (x % (cellSize * 2) == 0) {
        final pixels = x.toInt();
        final meters = (pixels / cellSize).toStringAsFixed(1);
        TextPainter(
          text: TextSpan(
            text: '${pixels}px\n${meters}m',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              backgroundColor: Color(0xBBFFFFFF),
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        )
          ..layout()
          ..paint(canvas, Offset(x + 2, 2));
      }
    }

    // Draw horizontal grid lines
    for (double y = 0; y <= maxGridY; y += cellSize) {
      canvas.drawLine(
        Offset(0, y),
        Offset(maxGridX, y),
        gridPaint,
      );

      // Add coordinates every 80 pixels (2 meters)
      if (y % (cellSize * 2) == 0) {
        final pixels = y.toInt();
        final meters = (pixels / cellSize).toStringAsFixed(1);
        TextPainter(
          text: TextSpan(
            text: '${pixels}px\n${meters}m',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              backgroundColor: Color(0xBBFFFFFF),
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        )
          ..layout()
          ..paint(canvas, Offset(2, y + 2));
      }
    }

    // Update user position display to show both pixels and meters
    final userPixelX = userCenter.dx.toInt();
    final userPixelY = userCenter.dy.toInt();
    final userMeterX = (userPixelX / cellSize).toStringAsFixed(1);
    final userMeterY = (userPixelY / cellSize).toStringAsFixed(1);

    TextPainter(
      text: TextSpan(
        text: 'Pixels: ($userPixelX, $userPixelY)\nMeters: (${userMeterX}m, ${userMeterY}m)',
        style: const TextStyle(
          color: Colors.blue,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          backgroundColor: Color(0xDDFFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )
      ..layout()
      ..paint(canvas, userCenter + const Offset(-40, -35));
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}