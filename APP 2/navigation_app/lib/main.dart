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
import 'package:navigation_app/models/beacon.dart';
import 'package:navigation_app/utils/positioning.dart';
import 'package:navigation_app/utils/smoothed_position.dart';

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

  // New positioning system with smoothing
  List<Beacon> beaconList = [];
  late SmoothedPositionTracker positionTracker;
  Vector2D currentPosition = Vector2D(0, 0);

  // New position confidence metric
  double positionConfidence = 1.0;
  
  // New configuration for beacon quality thresholds
  final int staleThresholdMs = 10000; // 10 seconds
  final double maxRangeMeters = 15.0; // 15 meters

  final flutterReactiveBle = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<Vector2D>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _selectedEvent = _events.isNotEmpty ? _events[0] : "";
    flutterReactiveBle.statusStream.listen((status) {
      debugPrint("Bluetooth status: $status");
    });
    
    // Initialize position tracker with enhanced configuration
    positionTracker = SmoothedPositionTracker(
      alpha: 0.85,            // Baseline smoothing factor
      intervalMs: 500,        // Update interval
      staleThresholdMs: staleThresholdMs,
      maxRangeMeters: maxRangeMeters,
      useAdaptiveThresholds: true, // Enable adaptive thresholds
    );
    
    _positionSubscription = positionTracker.positionStream.listen((position) {
      setState(() {
        currentPosition = position;
        userLocation = "${position.x.round()}, ${position.y.round()}";
        positionConfidence = positionTracker.confidence;
      });
      
      // Request path automatically when location updates and booth is selected
      if (selectedBooth.isNotEmpty) {
        requestPath(selectedBooth);
      }
    });
    
    fetchConfiguration().then((_) {
      fetchBoothNames();
    });
    
    // Start position tracking
    positionTracker.start();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _positionSubscription?.cancel();
    positionTracker.dispose();
    super.dispose();
  }

  // Convert scanned devices to Beacon objects with timestamp updates
  void _updateBeaconList() {
    final List<Beacon> updatedBeacons = [];
    final now = DateTime.now().millisecondsSinceEpoch;
    
    scannedDevices.forEach((id, rssi) {
      if (beaconIdToPosition.containsKey(id)) {
        final position = beaconIdToPosition[id]!;
        
        // Check if this beacon already exists in our list
        final existingBeaconIndex = beaconList.indexWhere((b) => b.id == id);
        
        if (existingBeaconIndex >= 0) {
          // Update existing beacon
          final existingBeacon = beaconList[existingBeaconIndex];
          updatedBeacons.add(existingBeacon.copyWith(
            rssi: rssi,
            lastUpdated: now,
            isActive: true,
          ));
        } else {
          // Create new beacon
          updatedBeacons.add(Beacon(
            id: id,
            name: id,
            rssi: rssi,
            baseRssi: txPower,
            position: Position(
              x: position[0].toDouble(), 
              y: position[1].toDouble()
            ),
            lastUpdated: now,
          ));
        }
      }
    });
    
    // Keep beacons that still exist but weren't updated in this scan
    // (they might be stale but we'll let the positioning system decide that)
    beaconList.forEach((existingBeacon) {
      if (!updatedBeacons.any((b) => b.id == existingBeacon.id)) {
        // Only keep beacons that aren't extremely stale (3x threshold)
        if (!existingBeacon.isStale(staleThresholdMs * 3)) {
          updatedBeacons.add(existingBeacon);
        }
      }
    });
    
    setState(() {
      beaconList = updatedBeacons;
    });
    
    // Update the position tracker with new beacon data
    positionTracker.updateBeacons(beaconList);
    positionTracker.updateCalibration(metersToGridFactor);
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
          
          // Update calibration in the position tracker
          positionTracker.updateCalibration(metersToGridFactor);
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
          setState(() {
            scannedDevices[beaconId!] = device.rssi;
          });
          
          // Update the beacon list with the new RSSI data
          _updateBeaconList();
          
          debugPrint("📶 Beacon: $beaconId, RSSI: ${device.rssi}");

          // Trigger connected popup exactly once
          if (scannedDevices.length >= 3 && !hasShownConnectedPopup) {
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
        }
      }
    }, onError: (error) {
      debugPrint("❌ Scan error: $error");
    });
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

            // Display current position with confidence indicator
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.teal[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Position:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text('X: ${currentPosition.x.toStringAsFixed(2)}, Y: ${currentPosition.y.toStringAsFixed(2)}'),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Text('Confidence: '),
                      _buildConfidenceMeter(positionConfidence),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text('Detected beacons: ${beaconList.length}'),
                ],
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
                onPressed: openMapScreen,
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

            // Beacon information with quality indicators
            if (beaconList.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Beacon Information:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    ...beaconList.map((beacon) {
                      final distance = rssiToDistance(beacon.rssi ?? beacon.baseRssi, beacon.baseRssi);
                      final isStale = beacon.isStale(staleThresholdMs);
                      final stalenessFactor = calculateStalenessFactor(beacon, staleThresholdMs);
                      final distanceFactor = calculateDistanceFactor(distance, maxRangeMeters);
                      
                      // Decide icon based on quality factors
                      String qualityIcon = '⚠️'; // Warning by default
                      
                      if (stalenessFactor > 0.8 && distanceFactor > 0.8) {
                        qualityIcon = '✓'; // Good
                      } else if (stalenessFactor > 0.5 && distanceFactor > 0.5) {
                        qualityIcon = '⚠️'; // Warning
                      } else {
                        qualityIcon = '⛔'; // Poor
                      }
                      
                      // Format time since update
                      final now = DateTime.now().millisecondsSinceEpoch;
                      final ageSeconds = (now - beacon.lastUpdated) / 1000;
                      final ageText = ageSeconds < 60 
                          ? '${ageSeconds.toStringAsFixed(1)}s ago' 
                          : '${(ageSeconds / 60).toStringAsFixed(1)}m ago';
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Row(
                          children: [
                            Text(qualityIcon),
                            SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${beacon.id}: RSSI ${beacon.rssi}dBm (≈${distance.toStringAsFixed(1)}m) - $ageText',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isStale ? Colors.grey : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
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
  
  // Helper method to show position confidence
  Widget _buildConfidenceMeter(double confidence) {
    Color barColor = Colors.red;
    if (confidence > 0.7) {
      barColor = Colors.green;
    } else if (confidence > 0.4) {
      barColor = Colors.orange;
    }
    
    return Row(
      children: [
        Container(
          width: 100,
          height: 10,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            color: Colors.grey[300],
          ),
          child: Row(
            children: [
              Container(
                width: 100 * confidence,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  color: barColor,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 8),
        Text('${(confidence * 100).toStringAsFixed(0)}%'),
      ],
    );
  }
}



