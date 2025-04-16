import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';

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

  // Known beacon positions
  final Map<String, List<int>> beaconIdToPosition = {
    "14j906Gy": [0, 0],
    "14jr08Ef": [200, 0],
    "14j606Gv": [0, 200],
  };

  final flutterReactiveBle = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;

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

  double estimateDistance(int rssi, int txPower) =>
      pow(10, (txPower - rssi) / 20).toDouble();

  // ------------------- Start Scanning for Beacons -------------------
  void startScan() async {
    await _scanSubscription?.cancel();
    setState(() {
      scannedDevices.clear();
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
          setState(() {
            scannedDevices[beaconId] = device.rssi;
            debugPrint("📶 Updated $beaconId with RSSI ${device.rssi}");
          });
        }
      }
    }, onError: (error) {
      debugPrint("❌ Scan error: $error");
    });
  }

  // ------------------- Get My Location Button -------------------
  void estimateUserLocation() {
    if (scannedDevices.length < 3) {
      debugPrint("Not enough beacons scanned (${scannedDevices.length}). Using fallback location (5, 5).");
      setState(() {
        userLocation = "5, 5";
      });
      return;
    }

    final distances = <String, double>{};
    scannedDevices.forEach((id, rssi) {
      double dist = estimateDistance(rssi, -59);
      distances[id] = dist;
      debugPrint("Beacon $id: RSSI = $rssi, estimated distance = $dist");
    });

    final position = _trilaterate(distances);
    if (position != null) {
      setState(() {
        double x = position.x < 0 ? 0 : position.x;
        double y = position.y < 0 ? 0 : position.y;
        userLocation = "${x.round()}, ${y.round()}";
      });
      debugPrint("📍 Estimated location: $userLocation");
      if (selectedBooth.isNotEmpty) {
        requestPath(selectedBooth);
      }
    } else {
      debugPrint("Trilateration returned null – check beacon data and txPower value.");
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
    final url = Uri.parse('http://128.61.115.73:8001/booths');
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
    final start = userLocation.split(",").map((e) => int.parse(e.trim()) ~/ 50).toList();
    try {
      final response = await http.post(
        Uri.parse('http://128.61.115.73:8001/path'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"from_": start, "to": boothName}),
      );
      if (response.statusCode == 200) {
        final path = jsonDecode(response.body)["path"];
        setState(() {
          currentPath = List<List<dynamic>>.from(path);
        });
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text("Path to $boothName"),
            content: path.isEmpty
                ? Text("No path found.")
                : Text(path.map<String>((p) => "(${p[0]}, ${p[1]})").join(" → ")),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text("OK"))
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ Error requesting path: $e");
    }
  }

  // ------------------- Open Map Screen -------------------
  void openMapScreen() {
    if (userLocation.isEmpty || selectedBooth.isEmpty) {
      debugPrint("Cannot open map – no location or booth selected.");
      return;
    }
    final start = userLocation.split(",").map((e) => int.parse(e.trim()) ~/ 50).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(path: currentPath, startLocation: start),
      ),
    );
  }

  // ------------------- UI Build -------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
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

            // 3) Get My Location (manually update location)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: estimateUserLocation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kTealColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                child: const Text("Get My Location"),
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
                setState(() => selectedBooth = selection);
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

            // 5) Find Path (update location then request path)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  estimateUserLocation();
                  requestPath(selectedBooth);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kTealColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                child: const Text("Find Path"),
              ),
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
            const SizedBox(height: 20),
            // Optional debug info for scanned beacons.
            if (scannedDevices.isNotEmpty)
              const Text("Scanned Beacons:", style: TextStyle(fontWeight: FontWeight.bold)),
            for (var entry in scannedDevices.entries)
              Text("Beacon: ${entry.key}, RSSI: ${entry.value}"),
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
  final clampedX = x < 0 ? 0.0 : x;
  final clampedY = y < 0 ? 0.0 : y;
  return Vector2D(clampedX, clampedY);
  return Vector2D(clampedX, clampedY);
}



