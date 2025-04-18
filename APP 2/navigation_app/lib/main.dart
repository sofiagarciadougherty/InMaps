import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:io' show Platform;

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

  // Backend URL
  final String backendUrl = 'https://inmaps.onrender.com';
  
  // Configuration from backend
  Map<String, dynamic> configData = {};
  Map<String, List<int>> beaconIdToPosition = {};
  Map<String, String> beacon_mac_map = {};
  Map<String, String> mac_to_id_map = {};
  int gridCellSize = 50;
  int pixelsPerMeter = 40;
  bool isConfigLoaded = false;
  
  // Calibration variables - still needed for conversion but not exposed in UI
  double metersToGridFactor = 2.0;  // Default, will be updated from backend
  int txPower = -59;  // Default reference power at 1m

  final flutterReactiveBle = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _selectedEvent = _events.isNotEmpty ? _events[0] : "";
    flutterReactiveBle.statusStream.listen((status) {
      debugPrint("Bluetooth status: $status");
    });
    fetchConfiguration().then((_) {
      fetchBoothNames();
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }

  // Fetch configuration from backend
  Future<void> fetchConfiguration() async {
    try {
      final response = await http.get(Uri.parse('$backendUrl/config'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          configData = data;
          
          // Parse beacon positions
          final positions = data['beaconPositions'] as Map<String, dynamic>;
          beaconIdToPosition = positions.map((key, value) => 
            MapEntry(key, [
              (value['x'] as num).toInt() * gridCellSize, 
              (value['y'] as num).toInt() * gridCellSize
            ])
          );
          
          // Parse beacon ID mapping
          beacon_mac_map = Map<String, String>.from(data['beaconIdMapping']);
          mac_to_id_map = {};
          beacon_mac_map.forEach((id, mac) {
            mac_to_id_map[mac] = id;
          });
          
          // Parse scale factors and calibration values
          gridCellSize = data['gridCellSize'] ?? 50;
          metersToGridFactor = (data['metersToGridFactor'] ?? 2.0).toDouble();
          txPower = data['txPower'] ?? -59;
          
          isConfigLoaded = true;
          debugPrint("✅ Configuration loaded from backend");
          debugPrint("📏 Meters to Grid Factor: $metersToGridFactor");
        });
      } else {
        debugPrint("❌ Failed to load configuration: ${response.statusCode}");
        // Fall back to hardcoded values
        _initializeDefaultConfig();
      }
    } catch (e) {
      debugPrint("❌ Error loading configuration: $e");
      // Fall back to hardcoded values
      _initializeDefaultConfig();
    }
  }
  
  // Initialize with default hardcoded values if backend config fails
  void _initializeDefaultConfig() {
    setState(() {
      beaconIdToPosition = {
        "14j906Gy": [0, 0],
        "14jr08Ef": [200, 0],
        "14j606Gv": [0, 200],
      };
      
      beacon_mac_map = {
        "14b00739": "00:FA:B6:2F:50:8C",
        "14b6072G": "00:FA:B6:2F:51:28",
        "14b7072H": "00:FA:B6:2F:51:25",
        "14bC072N": "00:FA:B6:2F:51:16",
        "14bE072Q": "00:FA:B6:2F:51:10",
        "14bF072R": "00:FA:B6:2F:51:0D",
        "14bK072V": "00:FA:B6:2F:51:01",
        "14bM072X": "00:FA:B6:2F:50:FB",
        "14j006gQ": "00:FA:B6:31:02:BA",
        "14j606Gv": "00:FA:B6:31:12:F8",
        "14j706Gw": "00:FA:B6:31:12:F5",
        "14j706gX": "00:FA:B6:31:02:A5",
        "14j906Gy": "00:FA:B6:31:12:EF",
        "14jd06i0": "00:FA:B6:31:01:A0",
        "14jj06i6": "00:FA:B6:31:01:8E",
        "14jr06gF": "00:FA:B6:31:02:D5",
        "14jr08Ef": "00:FA:B6:30:C2:F1",
        "14js06gG": "00:FA:B6:31:02:D2",
        "14jv06gK": "00:FA:B6:31:02:C9",
        "14jw08Ek": "00:FA:B6:30:C2:E2"
      };
      
      mac_to_id_map = {};
      beacon_mac_map.forEach((id, mac) {
        mac_to_id_map[mac] = id;
      });
      
      metersToGridFactor = 2.0; // Default value
      txPower = -59; // Default reference power at 1m
      
      isConfigLoaded = true;
      debugPrint("⚠️ Using default configuration");
    });
  }

  // Update the way we estimate distance using the proper path loss model
  double estimateDistance(int rssi, int txPower) =>
      pow(10, (txPower - rssi) / (10 * 2.0)).toDouble();  // Using path loss exponent of 2.0

  // Flag to track connection status
  bool hasShownConnectedPopup = false;

  void startScan() async {
    if (!isConfigLoaded) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: Colors.teal[50],
          title: const Text(
            "Configuration Loading",
            style: TextStyle(color: kTealColor, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            "Please wait while the configuration is loading...",
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
      return;
    }

    await _scanSubscription?.cancel();
    setState(() {
      scannedDevices.clear();
      hasShownConnectedPopup = false;
    });

    _scanSubscription = flutterReactiveBle.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      // Debug information
      debugPrint("Found device: ${device.name}, ID: ${device.id}");

      String? beaconId;

      // Process Kontakt beacons
      if (device.name.toLowerCase() == "kontakt") {
        if (Platform.isAndroid) {
          // For Android: Check if the MAC address is in our mapping
          if (mac_to_id_map.containsKey(device.id)) {
            beaconId = mac_to_id_map[device.id];
            debugPrint("✓ Android: Mapped MAC ${device.id} to ID $beaconId");
          }
        }

        // For both platforms: Try to extract ID from service data
        if (device.serviceData.containsKey(Uuid.parse("FE6A"))) {
          final rawData = device.serviceData[Uuid.parse("FE6A")]!;
          final asciiBytes = rawData.sublist(13);
          final extractedId = String.fromCharCodes(asciiBytes);

          debugPrint("Extracted ID from service data: $extractedId");

          // On iOS we use the extracted ID directly
          if (Platform.isIOS || beaconId == null) {
            beaconId = extractedId;
          }
        }

        // Process the beacon if we've identified it
        if (beaconId != null && beaconIdToPosition.containsKey(beaconId)) {
          scannedDevices[beaconId] = device.rssi;
          debugPrint("📶 Beacon: $beaconId, RSSI: ${device.rssi}");

          // Trigger connected popup exactly once
          if (scannedDevices.length == 2 && !hasShownConnectedPopup) {
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
          if (scannedDevices.length >= 2) {
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
    scannedDevices.forEach((id, rssi) {
      // Use the meters-to-grid factor to convert physical distance to grid units
      double physicalDistanceMeters = estimateDistance(rssi, txPower);
      distances[id] = physicalDistanceMeters * metersToGridFactor;
      debugPrint("📏 Beacon $id: RSSI $rssi → ${physicalDistanceMeters.toStringAsFixed(2)}m → ${distances[id].toStringAsFixed(2)} grid units");
    });

    final position = _trilaterate(distances);
    if (position != null) {
      double x = position.x < 0 ? 0 : position.x;
      double y = position.y < 0 ? 0 : position.y;
      userLocation = "${x.round()}, ${y.round()}";
      debugPrint("📍 [Auto-update] Current estimated location: $userLocation");

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
    final url = Uri.parse('$backendUrl/booths');
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

    final start = userLocation.split(",").map((e) => int.parse(e.trim()) ~/ gridCellSize).toList();
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/path'),
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

  // ------------------- Open Map Screen -------------------
  void openMapScreen() async {
    if (userLocation.isEmpty || selectedBooth.isEmpty) return;

    final start = userLocation.split(",").map((e) => int.parse(e.trim()) ~/ gridCellSize).toList();
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
}



