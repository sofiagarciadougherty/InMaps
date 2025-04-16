import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
<<<<<<< Updated upstream
<<<<<<< Updated upstream
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
=======
import 'package:flutter_compass/flutter_compass.dart';
>>>>>>> Stashed changes
=======
import 'package:flutter_compass/flutter_compass.dart';
>>>>>>> Stashed changes
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter_compass/flutter_compass.dart';


// Import game_screen.dart but hide MapScreen to avoid conflict.
import 'package:navigation_app/game_screen.dart' hide MapScreen;
import 'package:navigation_app/map_screen.dart';

// Choose a teal color for buttons.
const Color kTealColor = Color(0xFF008C9E);

void main() => runApp(NavigationApp());

class NavigationApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Indoor Navigation',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: BLEScannerPage(),
    );
  }
}

class BLEScannerPage extends StatefulWidget {
  @override
  _BLEScannerPageState createState() => _BLEScannerPageState();
}

class _BLEScannerPageState extends State<BLEScannerPage> {
  // ---------------- Hardcoded Events (non-editable dropdown) ----------------
  final List<String> _events = [
    "Select Event",
    "Expo Event",
    "Exhibition Hall",
    "CRC",
    "McCamish Pavillion Create X",
  ];
  String _selectedEvent = ""; // chosen event from dropdown

  // ---------------- Booths (fetched from backend) ----------------
  List<String> boothNames = [];
  String selectedBooth = "";

  // ---------------- Beacon/Location Variables ----------------
  Map<String, int> scannedDevices = {};
  String userLocation = "";
  List<List<dynamic>> currentPath = [];
<<<<<<< Updated upstream

  // Known beacon positions
  final Map<String, List<int>> beaconIdToPosition = {
    "14j906Gy": [0, 0],
    "14jr08Ef": [200, 0],
    "14j606Gv": [0, 200],
  };

  final flutterReactiveBle = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
=======
  Timer? locationUpdateTimer;
  final ValueNotifier<List<double>> liveLocation = ValueNotifier([0.0, 0.0]);
  final BLEScannerService bleService = BLEScannerService();
>>>>>>> Stashed changes

  static const double metersPerCell = 0.5;
  static const double pixelsPerMeter = 20.0;
  static const double cellSize = metersPerCell * pixelsPerMeter;

  static const double metersPerCell = 0.5;
  static const double pixelsPerMeter = 20.0;
  static const double cellSize = metersPerCell * pixelsPerMeter;

  @override
  void initState() {
    super.initState();
    _selectedEvent = _events.isNotEmpty ? _events[0] : "";
    flutterReactiveBle.statusStream.listen((status) {
      debugPrint("Bluetooth status: $status");
    });
    fetchBoothNames();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }

<<<<<<< Updated upstream
  double estimateDistance(int rssi, int txPower) =>
      pow(10, (txPower - rssi) / 20).toDouble();
=======
  void startScan() {
    bleService.startScan((id, rssi) {
      setState(() {
        scannedDevices[id] = rssi;
        print("📶 Updated $id with RSSI $rssi");
      });
    });
  }

  double estimateDistance(int rssi, int txPower) {
    double ratio = (txPower - rssi).toDouble();
    double distance = pow(10, ratio / 25).toDouble();
    return distance.clamp(0.5, 10.0).toDouble();
  }
<<<<<<< Updated upstream
>>>>>>> Stashed changes

  // Flag to track connection status
  bool hasShownConnectedPopup = false;


  void startScan() async {
    await _scanSubscription?.cancel();
    setState(() {
      scannedDevices.clear();
      hasShownConnectedPopup = false;
    });

    _scanSubscription = flutterReactiveBle.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      if (device.name.toLowerCase() == "kontakt" &&
          device.serviceData.containsKey(Uuid.parse("FE6A"))) {
        final rawData = device.serviceData[Uuid.parse("FE6A")]!;
        final asciiBytes = rawData.sublist(13);
        final beaconId = String.fromCharCodes(asciiBytes);

        if (beaconIdToPosition.containsKey(beaconId)) {
          scannedDevices[beaconId] = device.rssi;
          debugPrint("📶 Beacon: $beaconId, RSSI: ${device.rssi}");

          // Trigger connected popup exactly once
          if (scannedDevices.length == 3 && !hasShownConnectedPopup) {
            hasShownConnectedPopup = true;

            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: Colors.teal[50],
                title: const Text(
                  "Connected",
                  style: TextStyle(color: kTealColor, fontWeight: FontWeight.bold),
                ),
                content: const Text(
                  "Successfully connected to the event.",
                  style: TextStyle(color: Colors.black87),
                ),
                actions: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: kTealColor,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text("OK"),
                  ),
                ],
              ),
            );
          }

          // Continuously estimate location whenever RSSI updates with at least 3 beacons
          if (scannedDevices.length >= 3) {
            estimateUserLocation(); // <-- Automatic location update
          }
        }
      }
    }, onError: (error) {
      debugPrint("❌ Scan error: $error");
    });
  }




  void estimateUserLocation() {
    if (scannedDevices.length < 3) {
      debugPrint("Not enough beacons for accurate location.");
      return;
    }

    final distances = <String, double>{};
    final knownBeaconPositions = <String, List<double>>{};

    scannedDevices.forEach((id, rssi) {
      if (bleService.beaconIdToPosition.containsKey(id)) {
        final distance = estimateDistance(rssi, -59);
        distances[id] = distance;
        final meters = bleService.beaconIdToPosition[id]!;
        knownBeaconPositions[id] = [meters[0] * pixelsPerMeter, meters[1] * pixelsPerMeter];
        print("📡 $id at ${knownBeaconPositions[id]} → RSSI: $rssi → Est. dist: ${distance.toStringAsFixed(2)}");
      }
    });

<<<<<<< Updated upstream
    final position = _trilaterate(distances);
    if (position != null) {
      double x = position.x < 0 ? 0 : position.x;
      double y = position.y < 0 ? 0 : position.y;
      userLocation = "${x.round()}, ${y.round()}";
      debugPrint("📍 [Auto-update] Current estimated location: $userLocation");
=======
=======

  void estimateUserLocation() {
    final distances = <String, double>{};
    final knownBeaconPositions = <String, List<double>>{};

    scannedDevices.forEach((id, rssi) {
      if (bleService.beaconIdToPosition.containsKey(id)) {
        final distance = estimateDistance(rssi, -59);
        distances[id] = distance;
        final meters = bleService.beaconIdToPosition[id]!;
        knownBeaconPositions[id] = [meters[0] * pixelsPerMeter, meters[1] * pixelsPerMeter];
        print("📡 $id at ${knownBeaconPositions[id]} → RSSI: $rssi → Est. dist: ${distance.toStringAsFixed(2)}");
      }
    });

>>>>>>> Stashed changes
    final position = trilaterate(distances, knownBeaconPositions);

    if (position != null) {
      setState(() {
        userLocation = "${position.x.round()}, ${position.y.round()}";
        liveLocation.value = [position.x, position.y];
      });
>>>>>>> Stashed changes

      // Request path automatically when location updates and booth is selected
      if (selectedBooth.isNotEmpty) {
        requestPath(selectedBooth);
      }
    } else {
      debugPrint("Trilateration failed.");
    }
  }

  // ------------------- Trilateration -------------------
  Vector2D? _trilaterate(Map<String, double> distances) {
    if (distances.length < 3) return null;
    final keys = distances.keys.toList();
    final p1 = Vector2D(
      beaconIdToPosition[keys[0]]![0].toDouble(),
      beaconIdToPosition[keys[0]]![1].toDouble(),
    );
    final p2 = Vector2D(
      beaconIdToPosition[keys[1]]![0].toDouble(),
      beaconIdToPosition[keys[1]]![1].toDouble(),
    );
    final p3 = Vector2D(
      beaconIdToPosition[keys[2]]![0].toDouble(),
      beaconIdToPosition[keys[2]]![1].toDouble(),
    );
    final r1 = distances[keys[0]]!;
    final r2 = distances[keys[1]]!;
    final r3 = distances[keys[2]]!;

    final A = 2 * (p2.x - p1.x);
    final B = 2 * (p2.y - p1.y);
    final C = r1 * r1 - r2 * r2 - p1.x * p1.x + p2.x * p2.x - p1.y * p1.y + p2.y * p2.y;
    final D = 2 * (p3.x - p2.x);
    final E = 2 * (p3.y - p2.y);
    final F = r2 * r2 - r3 * r3 - p2.x * p2.x + p3.x * p3.x - p2.y * p2.y + p3.y * p3.y;
    final denom = A * E - B * D;
    if (denom.abs() < 1e-6) return null;
    final x = (C * E - B * F) / denom;
    final y = (A * F - C * D) / denom;
    return Vector2D(x, y);
  }

  // ------------------- Fetch Booth Names from Backend -------------------
  Future<void> fetchBoothNames() async {
    final url = Uri.parse('http://143.215.53.49:8001/booths');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> booths = jsonDecode(response.body);
        setState(() {
          boothNames = booths.map((b) => b["name"] as String).toList();
        });
      }
    } catch (e) {
      debugPrint("❌ Exception while fetching booth list: $e");
    }
  }

  // ------------------- Request Path -------------------
  Future<void> requestPath(String boothName) async {
    if (boothName.trim().isEmpty || userLocation.isEmpty || !userLocation.contains(",")) return;
<<<<<<< Updated upstream
<<<<<<< Updated upstream
=======
    final start = userLocation.split(",").map((e) => double.parse(e.trim()) / cellSize).toList();
>>>>>>> Stashed changes
=======
    final start = userLocation.split(",").map((e) => double.parse(e.trim()) / cellSize).toList();
>>>>>>> Stashed changes

    final start = userLocation.split(",").map((e) => int.parse(e.trim()) ~/ 50).toList();
    try {
      final response = await http.post(
        Uri.parse('http://143.215.53.49:8001/path'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"from_": start, "to": boothName}),
      );

      if (response.statusCode == 200) {
        final path = jsonDecode(response.body)["path"];
        setState(() {
          currentPath = List<List<dynamic>>.from(path);
        });

        // ✅ Print the path to the terminal only
        if (path.isEmpty) {
          debugPrint("⚠️ No path found to $boothName.");
        } else {
          debugPrint("🧭 Path to $boothName: ${path.map((p) => "(${p[0]}, ${p[1]})").join(" → ")}");
        }
      }
    } catch (e) {
      debugPrint("❌ Error requesting path: $e");
    }
  }

<<<<<<< Updated upstream
  // ------------------- Open Map Screen -------------------
  void openMapScreen() async {
      if (userLocation.isEmpty || selectedBooth.isEmpty) return;
=======
  void openMapScreen() {
    if (userLocation.isEmpty || selectedBooth.isEmpty) return;
    final start = userLocation.split(",").map((e) => double.parse(e.trim()) / cellSize).toList();
<<<<<<< Updated upstream
>>>>>>> Stashed changes
=======
>>>>>>> Stashed changes

      final start = userLocation.split(",").map((e) => int.parse(e.trim()) ~/ 50).toList();
      final heading = await FlutterCompass.events!.first; // One-time heading fetch

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MapScreen(
            path: currentPath,
            startLocation: start,
            headingDegrees: heading.heading ?? 0.0,
          ),
        ),
      );
    }


  // ------------------- UI Build -------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
<<<<<<< Updated upstream
      backgroundColor: Colors.white,
      // AppBar with larger logo.
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1) Select Event (Dropdown; non-editable)
            const Text(
              "Select Event:",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[200],
              ),
              child: DropdownButton<String>(
                value: _selectedEvent.isEmpty ? _events[0] : _selectedEvent,
                isExpanded: true,
                underline: const SizedBox(),
                items: _events.map((event) {
                  return DropdownMenuItem<String>(
                    value: event,
                    child: Text(event),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedEvent = val);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),

            // 2) Connect To Event (Beacon scan)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: startScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kTealColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                child: const Text("Connect To Event"),
              ),
            ),
            const SizedBox(height: 12),

            // 4) Enter Booth Name (Autocomplete from backend)
            const Text(
              "Enter Booth Name:",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            RawAutocomplete<String>(
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<String>.empty();
                }
                return boothNames.where((booth) => booth
                    .toLowerCase()
                    .contains(textEditingValue.text.toLowerCase()));
              },
              onSelected: (selection) {
                setState(() {
                  selectedBooth = selection;
                });
                requestPath(selection); // Automatically request path
              },
              fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                controller.text = selectedBooth;
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    hintText: "Type booth name here...",
                    filled: true,
                    fillColor: Colors.grey[200],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
=======
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
<<<<<<< Updated upstream
>>>>>>> Stashed changes
=======
>>>>>>> Stashed changes
                    ),
                  ),
                  onChanged: (value) => selectedBooth = value,
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Material(
                  elevation: 4.0,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: options.map((option) {
                      return ListTile(
                        title: Text(option),
                        onTap: () => onSelected(option),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 6) Show Path (Open Map Screen)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  estimateUserLocation();
                  openMapScreen();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kTealColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                child: const Text("Show Map"),
              ),
            ),
            const SizedBox(height: 12),

            // 7) Game Mode (Navigate to GameScreen)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await _scanSubscription?.cancel();
                  _scanSubscription = null;
                  setState(() {
                    scannedDevices.clear();
                  });
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const GameScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kTealColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                child: const Text("Game Mode"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Vector2D {
  final double x, y;
  Vector2D(this.x, this.y);
}

Vector2D? trilaterate(Map<String, double> d, Map<String, List<double>> p) {
  if (d.length < 3) return null;
  final keys = d.keys.toList();
  final p1 = Vector2D(p[keys[0]]![0], p[keys[0]]![1]);
  final p2 = Vector2D(p[keys[1]]![0], p[keys[1]]![1]);
  final p3 = Vector2D(p[keys[2]]![0], p[keys[2]]![1]);
  final r1 = d[keys[0]]!, r2 = d[keys[1]]!, r3 = d[keys[2]]!;
  final A = 2 * (p2.x - p1.x), B = 2 * (p2.y - p1.y);
  final C = r1 * r1 - r2 * r2 - p1.x * p1.x + p2.x * p2.x - p1.y * p1.y + p2.y * p2.y;
  final D = 2 * (p3.x - p2.x), E = 2 * (p3.y - p2.y);
  final F = r2 * r2 - r3 * r3 - p2.x * p2.x + p3.x * p3.x - p2.y * p2.y + p3.y * p3.y;
  final denom = A * E - B * D;
  if (denom.abs() < 1e-6) return null;
  final x = (C * E - B * F) / denom;
  final y = (A * F - C * D) / denom;
<<<<<<< Updated upstream
  final clampedX = x < 0 ? 0.0 : x;
  final clampedY = y < 0 ? 0.0 : y;
  return Vector2D(clampedX, clampedY);
  return Vector2D(clampedX, clampedY);
=======
  return Vector2D(x, y);
}


// ========================
// 🧭 MAP SCREEN
// ========================
class MapScreen extends StatefulWidget {
  final List<List<dynamic>> path;
  final List<double> startLocation;
  final ValueNotifier<List<double>> startLocationNotifier;
  final VoidCallback onStartScan;
  MapScreen({required this.path,required this.startLocation,required this.startLocationNotifier, required this.onStartScan,});
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<dynamic> elements = [];
  double maxX = 0;
  double maxY = 0;
  List<double> currentLocation = [0.0, 0.0];
  double userHeading = 0.0; // in degrees



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
    FlutterCompass.events?.listen((CompassEvent event) {
        setState(() {
    userHeading = event.heading ?? 0.0;
  });
});
    
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
              painter: MapPainter(elements, widget.path, currentLocation,userHeading),
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
  final List<double> startLocation;
  static const double cellSize = 10.0;
  final double heading;

  MapPainter(this.elements, this.path, this.startLocation, this.heading);

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

    final userCenter = Offset(
      (startLocation[0]) * cellSize,
      (startLocation[1]) * cellSize,
    );

    // Cone direction indicator (like Google Maps)
    final coneAngle = pi / 6; // 30 degrees
    final coneRadius = 70.0;
    final angleRad = (heading - 90) * pi / 180;
    final startAngle = angleRad - coneAngle;
    final endAngle = angleRad + coneAngle;

    final conePath = Path()
      ..moveTo(userCenter.dx, userCenter.dy)
      ..lineTo(
        userCenter.dx + coneRadius * cos(startAngle),
        userCenter.dy + coneRadius * sin(startAngle),
      )
      ..arcToPoint(
        Offset(
          userCenter.dx + coneRadius * cos(endAngle),
          userCenter.dy + coneRadius * sin(endAngle),
        ),
        radius: Radius.circular(coneRadius),
        largeArc: false,
      )
      ..close();

    canvas.drawPath(conePath, paintCone); // Draw cone first
    canvas.drawCircle(userCenter, 8, paintUser); // Then user dot on top

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
>>>>>>> Stashed changes
}



