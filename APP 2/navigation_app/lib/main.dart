import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'game_screen.dart';
import 'ble_scanner_service.dart';

void main() => runApp(NavigationApp());

class NavigationApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Indoor Navigation',
      theme: ThemeData(primarySwatch: Colors.purple),
      home: BLEScannerPage(),
    );
  }
}

class BLEScannerPage extends StatefulWidget {
  @override
  _BLEScannerPageState createState() => _BLEScannerPageState();
}

class _BLEScannerPageState extends State<BLEScannerPage> {
  Map<String, int> scannedDevices = {};
  String userLocation = "";
  String selectedBooth = "";
  List<String> boothNames = [];
  List<List<dynamic>> currentPath = [];
  Timer? locationUpdateTimer;
  final ValueNotifier<List<int>> liveLocation = ValueNotifier([0, 0]);
  final BLEScannerService bleService = BLEScannerService();

  @override
  void initState() {
    super.initState();
    startScan();
    fetchBoothNames();
    locationUpdateTimer = Timer.periodic(Duration(seconds: 3), (_) {
      if (scannedDevices.length >= 3) {
        estimateUserLocation();
      }
    });
  }

  @override
  void dispose() {
    bleService.stopScan();
    locationUpdateTimer?.cancel();
    super.dispose();
  }

  void startScan() {
    bleService.startScan((id, rssi) {
      setState(() {
        scannedDevices[id] = rssi;
        print("📶 Updated $id with RSSI $rssi");
      });
    });
  }

  double estimateDistance(int rssi, int txPower) =>
      pow(10, (txPower - rssi) / 20).toDouble();

  void estimateUserLocation() {
    final distances = <String, double>{};
    scannedDevices.forEach((id, rssi) {
      distances[id] = estimateDistance(rssi, -59);
    });

    final position = trilaterate(distances, bleService.beaconIdToPosition);
    if (position != null) {
      setState(() {
        userLocation = "${position.x.round()}, ${position.y.round()}";
        liveLocation.value = [position.x ~/ 50, position.y ~/ 50];
      });

      if (selectedBooth.isNotEmpty) {
        requestPath(selectedBooth);
      }

      print("📍 You are at: (${position.x.toStringAsFixed(1)}, ${position.y.toStringAsFixed(1)})");
    }
  }

  Future<void> fetchBoothNames() async {
    final url = Uri.parse('http://143.215.53.49:8001/booths');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final booths = jsonDecode(response.body);
        setState(() {
          boothNames = List<String>.from(booths.map((b) => b["name"]));
        });
      }
    } catch (e) {
      print("❌ Error fetching booth names: $e");
    }
  }

  Future<void> requestPath(String boothName) async {
    if (boothName.trim().isEmpty || userLocation.isEmpty || !userLocation.contains(",")) return;
    final start = userLocation.split(",").map((e) => int.parse(e.trim()) ~/ 50).toList();

    try {
      final response = await http.post(
        Uri.parse('http://143.215.53.49:8001/path'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"from_": start, "to": boothName}),
      );

      if (response.statusCode == 200) {
        final path = jsonDecode(response.body)["path"];
        setState(() => currentPath = List<List<dynamic>>.from(path));
        print("📍 Path to $boothName: ${path.map((p) => "(${p[0]}, ${p[1]})").join(" → ")}");
      }
    } catch (e) {
      print("❌ Error requesting path: $e");
    }
  }

  void openMapScreen() {
    if (userLocation.isEmpty || selectedBooth.isEmpty) return;
    final start = userLocation.split(",").map((e) => int.parse(e.trim()) ~/ 50).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          path: currentPath,
          startLocation: start,
          startLocationNotifier: liveLocation,
          onStartScan: startScan,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("BLE Navigation")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              ElevatedButton(onPressed: startScan, child: Text("Scan for Beacons")),
              ...scannedDevices.entries.map((e) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Device ID: ${e.key}"),
                  Text("RSSI: ${e.value}"),
                ],
              )),
              if (scannedDevices.isNotEmpty)
                ElevatedButton(onPressed: estimateUserLocation, child: Text("Get My Location")),
              if (userLocation.isNotEmpty) ...[
                SizedBox(height: 20),
                RawAutocomplete<String>(
                  optionsBuilder: (textEditingValue) => boothNames.where((option) =>
                      option.toLowerCase().contains(textEditingValue.text.toLowerCase())),
                  onSelected: (selection) => setState(() => selectedBooth = selection),
                  fieldViewBuilder: (context, controller, focusNode, _) => TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(labelText: 'Enter booth name'),
                    onChanged: (value) => selectedBooth = value,
                  ),
                  optionsViewBuilder: (context, onSelected, options) => Material(
                    elevation: 4.0,
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: options.map((option) => ListTile(
                        title: Text(option),
                        onTap: () => onSelected(option),
                      )).toList(),
                    ),
                  ),
                ),
                SizedBox(height: 10),
                ElevatedButton(onPressed: () => requestPath(selectedBooth), child: Text("Find Path")),
              ],
              SizedBox(height: 20),
              ElevatedButton(onPressed: openMapScreen, child: Text("Show Map")),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  bleService.stopScan();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const GameScreen()));
                },
                child: Text("Go to Game Mode"),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class Vector2D {
  final double x, y;
  Vector2D(this.x, this.y);
}

Vector2D? trilaterate(Map<String, double> d, Map<String, List<int>> p) {
  if (d.length < 3) return null;
  final keys = d.keys.toList();
  final p1 = Vector2D(p[keys[0]]![0].toDouble(), p[keys[0]]![1].toDouble());
  final p2 = Vector2D(p[keys[1]]![0].toDouble(), p[keys[1]]![1].toDouble());
  final p3 = Vector2D(p[keys[2]]![0].toDouble(), p[keys[2]]![1].toDouble());
  final r1 = d[keys[0]]!, r2 = d[keys[1]]!, r3 = d[keys[2]]!;
  final A = 2 * (p2.x - p1.x), B = 2 * (p2.y - p1.y);
  final C = r1 * r1 - r2 * r2 - p1.x * p1.x + p2.x * p2.x - p1.y * p1.y + p2.y * p2.y;
  final D = 2 * (p3.x - p2.x), E = 2 * (p3.y - p2.y);
  final F = r2 * r2 - r3 * r3 - p2.x * p2.x + p3.x * p3.x - p2.y * p2.y + p3.y * p3.y;
  final denom = A * E - B * D;
  if (denom.abs() < 1e-6) return null;
  final x = (C * E - B * F) / denom;
  final y = (A * F - C * D) / denom;
  return Vector2D(x, y);
}


// ========================
// 🧭 MAP SCREEN
// ========================
class MapScreen extends StatefulWidget {
  final List<List<dynamic>> path;
  final List<int> startLocation;
  final ValueNotifier<List<int>> startLocationNotifier;
  final VoidCallback onStartScan;
  MapScreen({required this.path,required this.startLocation,required this.startLocationNotifier, required this.onStartScan,});
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<dynamic> elements = [];
  double maxX = 0;
  double maxY = 0;
  List<int> currentLocation = [0, 0];

  @override
  void initState() {
    super.initState();
    widget.onStartScan();
    widget.startLocationNotifier.addListener(() {
        setState(() {
          currentLocation = widget.startLocationNotifier.value;
        });
      });
    fetchMapData();
  }
  Map<String, dynamic>? _findTappedBooth(Offset tapPosition) {
    for (var el in elements) {
      final start = el["start"];
      final end = el["end"];
      final rect = Rect.fromPoints(
        Offset(start["x"].toDouble(), start["y"].toDouble()),
        Offset(end["x"].toDouble(), end["y"].toDouble()),
      );
      if (rect.contains(tapPosition) && el["type"] == "booth") {
        return el;
      }
    }
    return null;
  }

  void _showBoothPopup(Map<String, dynamic> booth) {
    final name = booth["name"];
    final description = booth["description"] ?? "No description available.";
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(name),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Close"),
          )
        ],
      ),
    );
  }

  Future<void> fetchMapData() async {
    final url = Uri.parse("http://143.215.53.49:8001/map-data");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final fetchedElements = json["elements"];
        double maxXLocal = 0, maxYLocal = 0;
        for (var el in fetchedElements) {
          final start = el["start"];
          final end = el["end"];
          maxXLocal = [start["x"], end["x"], maxXLocal]
              .reduce((a, b) => a > b ? a : b)
              .toDouble();
          maxYLocal = [start["y"], end["y"], maxYLocal]
              .reduce((a, b) => a > b ? a : b)
              .toDouble();
        }
        setState(() {
          elements = fetchedElements;
          maxX = maxXLocal + 100; // 100 px padding.
          maxY = maxYLocal + 100;
        });
      } else {
        print("❌ Failed to fetch map data");
      }
    } catch (e) {
      print("❌ Map fetch failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Map View")),
      body: elements.isEmpty
          ? Center(child: CircularProgressIndicator())
          : InteractiveViewer(
        minScale: 0.2,
        maxScale: 5.0,
        boundaryMargin: EdgeInsets.all(1000),
        child: Container(
          width: maxX,
          height: maxY,
          child: GestureDetector(
            onTapDown: (details) {
              final tapped = _findTappedBooth(details.localPosition);
              if (tapped != null) {
                _showBoothPopup(tapped);
              }
            },
            child: CustomPaint(
              painter: MapPainter(elements, widget.path, currentLocation),
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
  final List<int> startLocation;
  static const double cellSize = 5.0;

  MapPainter(this.elements, this.path, this.startLocation);

  @override
  void paint(Canvas canvas, Size size) {
    final paintBooth = Paint()..color = Colors.green.withOpacity(0.6);
    final paintBlocker = Paint()..color = Colors.red.withOpacity(0.6);
    final paintOther = Paint()..color = Colors.blueGrey.withOpacity(0.5);
    final paintPath = Paint()
      ..color = Colors.blue
      ..strokeWidth = 3.0;
    final paintUser = Paint()..color = Colors.blue;
    final textStyle = TextStyle(color: Colors.black, fontSize: 10);

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
      canvas.drawCircle(
        Offset((startLocation[0] + 0.5) * cellSize, (startLocation[1] + 0.5) * cellSize),
        6,
        paintUser,
      );
      final span = TextSpan(text: name, style: textStyle);
      final tp = TextPainter(
        text: span,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
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




