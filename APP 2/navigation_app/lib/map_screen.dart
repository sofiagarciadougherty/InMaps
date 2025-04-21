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

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  List<dynamic> elements = [];
  double maxX = 0;
  double maxY = 0;
  List<int> lastGridPosition = [-1, -1];
  List<List<dynamic>> currentPath = [];
  double _userRotation = 0.0;
  double _manualRotation = 0.0;
  double _initialScale = 1.0;




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
  
  // Add variables for booth tap handling
  dynamic tappedBooth = null;
  OverlayEntry? _overlayEntry;

  bool hasNotifiedArrival = false;
  OverlayEntry? _arrivalOverlay;

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
    final double currentScale = _transformationController.value.getMaxScaleOnAxis();

    final size = MediaQuery.of(context).size;
    final translation = Matrix4.identity()
      ..scale(currentScale) // 🛠️ keep the current zoom
      ..translate(
        -userPosition.dx + size.width / (2 * currentScale),
        -userPosition.dy + size.height / (2 * currentScale),
      );
    _transformationController.value = translation;
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
        final correctedHeading = headingRadians - _manualRotation;
        final newOffset = Offset(
          imuOffset.x + cos(correctedHeading) * stepDistanceInPixels,
          imuOffset.y + sin(correctedHeading) * stepDistanceInPixels,
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
<<<<<<< Updated upstream
        _checkArrival();
      }
    });
=======
        _centerOnUserAfterMove();
      }
    });

    updatePath();
>>>>>>> Stashed changes
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

<<<<<<< Updated upstream
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
=======
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
        body: jsonEncode({
          "from_": [xGrid, yGrid],
          "to": selectedBoothName,
        }),
=======
        body: jsonEncode({"from_": [xGrid, yGrid], "to": selectedBoothName}),
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
=======

  @override
  void dispose() {
    _moveController.dispose();
    _transformationController.dispose();
    _headingSub?.cancel();
    _accelSub?.cancel();
    super.dispose();
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      title: Row(
        children: [
          Image.asset(
            'assets/images/logo.png',
            height: 45,
          ),
        ],
      ),
      iconTheme: const IconThemeData(color: Colors.black87),
    ),
    body: elements.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : Stack(
            children: [
              Container(
                color: Colors.white,
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 0.2,
                  maxScale: 5.0,
                  boundaryMargin: const EdgeInsets.all(1000),
                  panEnabled: true,
                  scaleEnabled: true,
                  clipBehavior: Clip.none,
                  constrained: false,
                  onInteractionStart: (details) {
                    _initialScale = _transformationController.value.getMaxScaleOnAxis();
                  },
                  onInteractionUpdate: (details) {
                    if (details.pointerCount >= 2) {
                      final rotationDelta = details.rotation;
                      final scaleDelta = details.scale;

                      if (rotationDelta.abs() > 0.7) {
                        double limitedRotationDelta = rotationDelta.clamp(-0.05, 0.05);
                        setState(() {
                          _manualRotation += limitedRotationDelta;
                        });
                      }

                      double currentScale = _transformationController.value.getMaxScaleOnAxis();
                      double desiredScale = _initialScale * scaleDelta;
                      double resistanceFactor = 0.1;
                      double adjustedScale = currentScale + (desiredScale - currentScale) * resistanceFactor;

                      Matrix4 newTransform = Matrix4.identity()
                        ..scale(adjustedScale)
                        ..translate(
                          _transformationController.value.row0.w / adjustedScale,
                          _transformationController.value.row1.w / adjustedScale,
                        );

                      _transformationController.value = newTransform;
                    }
                  },
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
                  backgroundColor: const Color(0xFF008C9E),
                  child: const Icon(
                    Icons.my_location,
                    color: Colors.white,
                  ),
                  elevation: 4,
                  tooltip: 'Center on my location',
                ),
              ),
            ],
          ),
  );
}
>>>>>>> Stashed changes
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
    // Fill the entire canvas with white first
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.white);

    final userCenter = basePosition + animatedOffset;

    // ROTATE booths and path
    canvas.save();
    canvas.translate(userCenter.dx, userCenter.dy);
    canvas.rotate(manualRotation);
    canvas.translate(-userCenter.dx, -userCenter.dy);

    final paintBooth = Paint()..color = const Color(0xFF008C9E).withOpacity(0.15);
    final paintBlocker = Paint()..color = Colors.red.withOpacity(0.2);
    final paintOther = Paint()..color = Colors.blueGrey.withOpacity(0.1);
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

    // --- Draw booth shadows first ---
    for (var el in elements) {
      final start = el["start"];
      final end = el["end"];
      final type = el["type"].toString().toLowerCase();
      if (type == "booth") {
        final startOffset = Offset(start["x"].toDouble(), start["y"].toDouble());
        final endOffset = Offset(end["x"].toDouble(), end["y"].toDouble());
        
        // Draw shadow
        final shadowPaint = Paint()
          ..color = Colors.black.withOpacity(0.1)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromPoints(startOffset, endOffset).translate(2, 2),
            const Radius.circular(12)
          ),
          shadowPaint,
        );
      }
    }

    // --- Draw booths, blockers, others ---
    for (var el in elements) {
      final start = el["start"];
      final end = el["end"];
      final type = el["type"].toString().toLowerCase();
      final startOffset = Offset(start["x"].toDouble(), start["y"].toDouble());
      final endOffset = Offset(end["x"].toDouble(), end["y"].toDouble());

      Paint paint;
      if (type == "blocker") paint = paintBlocker;
      else if (type == "booth") {
        // For booths, add a gradient effect
        paint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF008C9E).withOpacity(0.2),
              const Color(0xFF008C9E).withOpacity(0.3),
            ],
          ).createShader(Rect.fromPoints(startOffset, endOffset));
      }
      else paint = paintOther;

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromPoints(startOffset, endOffset), const Radius.circular(12)),
        paint,
      );

      // Add a subtle border for booths
      if (type == "booth") {
        final borderPaint = Paint()
          ..color = const Color(0xFF008C9E).withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromPoints(startOffset, endOffset), const Radius.circular(12)),
          borderPaint,
        );
      }
    }

    // --- Draw path ---
    if (path.isNotEmpty) {
      for (int i = 0; i < path.length - 1; i++) {
        final p1 = Offset((path[i][0] + 0.5) * cellSize, (path[i][1] + 0.5) * cellSize);
        final p2 = Offset((path[i + 1][0] + 0.5) * cellSize, (path[i + 1][1] + 0.5) * cellSize);
        canvas.drawLine(p1, p2, paintPathGlow);
        canvas.drawLine(p1, p2, paintPath);
      }
    }

    // --- Draw user (circle) ---
    canvas.drawCircle(userCenter, 10, paintUserBorder);
    canvas.drawCircle(userCenter, 6, paintUser);

    // --- Draw booth labels ---
    final textStyle = const TextStyle(
      color: Colors.black87,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );

    for (var el in elements) {
      // Skip elements with type "beacon"
      if (el["type"].toString().toLowerCase() == "beacon") {
        continue;
      }
      
      final start = el["start"];
      final end = el["end"];
      final name = el["name"];
      final center = Offset(
        (start["x"].toDouble() + end["x"].toDouble()) / 2,
        (start["y"].toDouble() + end["y"].toDouble()) / 2,
      );

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-manualRotation); // counter-rotate booth text
      canvas.translate(-center.dx, -center.dy);

      final tp = TextPainter(
        text: TextSpan(text: name, style: textStyle),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));

      canvas.restore();
    }

    canvas.restore(); // ✅ STOP rotating now

    // NOW: Draw cone based on real phone heading (no map rotation)
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

    final paintCone = Paint()
      ..color = const Color(0xFF008C9E).withOpacity(0.15)
      ..style = PaintingStyle.fill;

    canvas.drawPath(conePath, paintCone);
<<<<<<< Updated upstream

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
=======
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
>>>>>>> Stashed changes
