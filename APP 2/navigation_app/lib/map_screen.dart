import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MapScreen extends StatefulWidget {
  final List<List<dynamic>> path;
  final List<int> startLocation;
  MapScreen({required this.path, required this.startLocation});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<dynamic> elements = [];
  double maxX = 0;
  double maxY = 0;

  @override
  void initState() {
    super.initState();
    fetchMapData();
  }

  Future<void> fetchMapData() async {
    final url = Uri.parse("http://128.61.115.73:8001/map-data");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final fetchedElements = json["elements"];
        double maxXLocal = 0, maxYLocal = 0;
        // Compute maximum x and y from the start and end coordinates
        for (var el in fetchedElements) {
          final start = el["start"];
          final end = el["end"];
          maxXLocal = [start["x"], end["x"], maxXLocal].reduce((a, b) => a > b ? a : b).toDouble();
          maxYLocal = [start["y"], end["y"], maxYLocal].reduce((a, b) => a > b ? a : b).toDouble();
        }
        setState(() {
          elements = fetchedElements;
          maxX = maxXLocal + 100; // Add padding (100 pixels) for display.
          maxY = maxYLocal + 100;
        });
      } else {
        print("❌ Failed to fetch map data. Status: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Map fetch failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Map View")),
      body: elements.isEmpty
          ? Center(child: CircularProgressIndicator())
          : InteractiveViewer(
        minScale: 0.2,
        maxScale: 5.0,
        boundaryMargin: const EdgeInsets.all(1000),
        child: Container(
          width: maxX,
          height: maxY,
          child: CustomPaint(
            painter: MapPainter(elements, widget.path, widget.startLocation),
          ),
        ),
      ),
    );
  }
}

class MapPainter extends CustomPainter {
  final List<dynamic> elements;
  final List<List<dynamic>> path;
  final List<int> startLocation;
  static const double cellSize = 50.0;

  MapPainter(this.elements, this.path, this.startLocation);

  @override
  void paint(Canvas canvas, Size size) {
    // Define Paint objects for different element types.
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

    // Draw each element from the map data.
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



      // Draw the user location marker on the map.
      canvas.drawCircle(
        Offset((startLocation[0] + 0.5) * cellSize, (startLocation[1] + 0.5) * cellSize),
        6,
        paintUser,
      );

      // Draw the name of the element at its center.
      final span = TextSpan(text: name, style: textStyle);
      final tp = TextPainter(
        text: span,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }

    // Draw the path if available.
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

