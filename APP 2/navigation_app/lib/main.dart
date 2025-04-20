import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:io' show Platform;
// carlota
// Import game_screen.dart but hide MapScreen to avoid conflict.
import './game_screen.dart' hide MapScreen;
import './map_screen.dart';
import './models/beacon.dart';
import './utils/positioning.dart';
import './utils/smoothed_position.dart';
import './utils/fused_position.dart';
import './utils/vector2d.dart';
import './utils/unit_converter.dart';
import './ble_scanner_service.dart';  // Added missing import

// Choose a teal color for buttons.
const Color kTealColor = Color(0xFF008C9E);

void main() => runApp(NavigationApp());

class NavigationApp extends StatelessWidget {
  const NavigationApp({super.key});

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
  const BLEScannerPage({super.key});

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

  // Unit converter
  final UnitConverter converter = UnitConverter();

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
  bool isConfigLoaded = false;

  // Calibration variables
  int txPower = -59; // Default reference power at 1m

  // New positioning system with smoothing and fusion
  List<Beacon> beaconList = [];
  late SmoothedPositionTracker blePositionTracker;
  late FusedPositionTracker positionTracker;
  Vector2D currentPosition = const Vector2D(0, 0);

  // Path request throttling
  DateTime _lastPathRequest = DateTime.now();
  static const Duration _pathRequestThreshold = Duration(milliseconds: 1000);

  // Movement detection
  bool _isMoving = false;
  Vector2D _lastSignificantPosition = const Vector2D(0, 0);
  static const double _movementThreshold = 15.0; // pixels

  final flutterReactiveBle = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<Vector2D>? _positionSubscription;

  // Simulation mode
  bool simulateBeacons = false;
  Timer? simulationTimer;

  // Simulated beacons (real IDs and pixel positions from poi_coordinates.csv)
  final List<Beacon> simulatedBeacons = [
    Beacon(
      id: 'beacon_2',
      name: 'beacon_2',
      rssi: -60,
      baseRssi: -59,
      position: Vector2D(520, 573),
    ),
    Beacon(
      id: 'beacon_3',
      name: 'beacon_3',
      rssi: -65,
      baseRssi: -59,
      position: Vector2D(524, 519),
    ),
    Beacon(
      id: 'beacon_4',
      name: 'beacon_4',
      rssi: -70,
      baseRssi: -59,
      position: Vector2D(593, 482),
    ),
  ];

  void startBeaconSimulation() {
    simulationTimer?.cancel();
    simulationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Optionally randomize RSSI for realism
      final beacons = simulatedBeacons.map((b) => Beacon(
        id: b.id,
        name: b.name,
        rssi: b.rssi! + (Random().nextInt(7) - 3),
        baseRssi: b.baseRssi,
        position: b.position,
      )).toList();
      setState(() {
        beaconList = beacons;
      });
      // Update the SmoothedPositionTracker directly
      blePositionTracker.updateBeacons(beacons);
      // Optionally still update the fused tracker if needed elsewhere
      // positionTracker.updateBeacons(beacons);
    });
  }

  void stopBeaconSimulation() {
    simulationTimer?.cancel();
  }

  @override
  void initState() {
    super.initState();
    _selectedEvent = _events.isNotEmpty ? _events[0] : "";
    flutterReactiveBle.statusStream.listen((status) {
      debugPrint("Bluetooth status: $status");
    });

    // Initialize BLE position tracker
    blePositionTracker = SmoothedPositionTracker(alpha: 0.8, intervalMs: 800);
    blePositionTracker.start(); // <-- Ensure the tracker is running

    // Initialize fused position tracker with BLE base
    positionTracker = FusedPositionTracker(
      bleScanner: BLEScannerService(),
      initialPosition: const Vector2D(0, 0),
      useSimulators: false,
      updateIntervalMs: 100,
      debugMode: true,
    );

    // Configure the BLE scanner service with the MAC mappings
    final bleScanner = BLEScannerService();
    bleScanner.configure(
      macToIdMap: mac_to_id_map,
      beaconPositions: beaconIdToPosition,
    );

    // Subscribe to position updates
    _positionSubscription = positionTracker.positionStream.listen((position) {
      // Check if significant movement has occurred
      final distanceMoved = Vector2D.distance(position, _lastSignificantPosition);
      final isSignificantMovement = distanceMoved > _movementThreshold;

      setState(() {
        currentPosition = position;
        userLocation = converter.formatPositionForDisplay(position);

        // Update movement status for UI feedback
        if (isSignificantMovement) {
          _isMoving = true;
          _lastSignificantPosition = position;
        } else {
          _isMoving = false;
        }
      });

      // Request path automatically when location updates and booth is selected
      if (selectedBooth.isNotEmpty) {
        final now = DateTime.now();
        if (now.difference(_lastPathRequest) > _pathRequestThreshold) {
          _lastPathRequest = now;
          requestPath(selectedBooth);
        }
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
    stopBeaconSimulation();
    super.dispose();
  }

  // Convert scanned devices to Beacon objects
  void _updateBeaconList() {
    final List<Beacon> updatedBeacons = [];

    scannedDevices.forEach((id, rssi) {
      if (beaconIdToPosition.containsKey(id)) {
        final position = beaconIdToPosition[id]!;
        updatedBeacons.add(Beacon(
          id: id,
          name: id,
          rssi: rssi,
          baseRssi: txPower,
          position: Vector2D(position[0].toDouble(), position[1].toDouble()),
        ));
      }
    });

    setState(() {
      beaconList = updatedBeacons;
    });

    // Update the position tracker with new beacon data
    positionTracker.updateBeacons(beaconList);

    // Add debug logging
    if (beaconList.isNotEmpty) {
      debugPrint(
          "🔍 Current beacons: ${beaconList.map((b) => '${b.id}: (${b.position?.x}, ${b.position?.y})').join(', ')}");
    }
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
          final gridCellSize = data['gridCellSize'] ?? 50;
          beaconIdToPosition = positions.map((key, value) => MapEntry(key, [
                ((value['x'] as num).toInt() * gridCellSize).toInt(),
                ((value['y'] as num).toInt() * gridCellSize).toInt()
              ]));

          // Parse beacon ID mapping
          beacon_mac_map = Map<String, String>.from(data['beaconIdMapping']);
          mac_to_id_map = {};
          beacon_mac_map.forEach((id, mac) {
            mac_to_id_map[mac] = id;
          });

          // Configure the BLEScannerService with updated mappings from backend
          final bleScanner = BLEScannerService();
          bleScanner.configure(
            macToIdMap: mac_to_id_map,
            beaconPositions: beaconIdToPosition,
          );

          // Parse scale factors and calibration values
          final pixelsPerGridCell = (data['gridCellSize'] ?? 50).toDouble();
          final metersToGridFactor =
              (data['metersToGridFactor'] ?? 2.0).toDouble();
          txPower = data['txPower'] ?? -59;

          // Configure the central unit converter
          converter.configure(
            pixelsPerGridCell: pixelsPerGridCell,
            metersToGridFactor: metersToGridFactor,
          );

          isConfigLoaded = true;
          debugPrint("✅ Configuration loaded from backend");
          debugPrint(
              "📏 Meters to Grid Factor: ${converter.metersToGridFactor}");

          // Update calibration in the position tracker
          positionTracker.updateCalibration(converter.metersToGridFactor);
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

      // Configure with default values
      converter.configure(
        pixelsPerGridCell: 50.0,
        metersToGridFactor: 2.0,
      );

      // Configure the BLEScannerService with the default mappings
      final bleScanner = BLEScannerService();
      bleScanner.configure(
        macToIdMap: mac_to_id_map,
        beaconPositions: beaconIdToPosition,
      );

      txPower = -59; // Default reference power at 1m

      isConfigLoaded = true;
      debugPrint("⚠️ Using default configuration");

      // Update calibration in the position tracker
      positionTracker.updateCalibration(converter.metersToGridFactor);
    });
  }

  // ------------------- Request Path -------------------
  Future<void> requestPath(String boothName) async {
    if (boothName.trim().isEmpty ||
        userLocation.isEmpty ||
        !userLocation.contains(",")) {
      return;
    }

    final gridCoords = converter.positionToBackendGrid(currentPosition);
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/path'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"from_": gridCoords, "to": boothName}),
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
          debugPrint(
              "🧭 Path to $boothName: ${path.map((p) => "(${p[0]}, ${p[1]})").join(" → ")}");
        }
      }
    } catch (e) {
      debugPrint("❌ Error requesting path: $e");
    }
  }

  // ------------------- Open Map Screen -------------------
  void openMapScreen() async {
    if (userLocation.isEmpty || selectedBooth.isEmpty) return;

    // Convert the current position to grid coordinates
    final gridCoords = converter.positionToGridCoords(currentPosition);

    final heading = await FlutterCompass.events!.first;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          path: currentPath,
          startLocation: gridCoords,
          headingDegrees: heading.heading ?? 0.0,
          initialPosition: currentPosition,
          // Use the stream from the tracker receiving simulated beacons
          positionStream: blePositionTracker.positionStream,
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
        actions: [
          // Simulation toggle button
          Row(
            children: [
              const Text('Simulate', style: TextStyle(color: Colors.black)),
              Switch(
                value: simulateBeacons,
                onChanged: (val) {
                  setState(() {
                    simulateBeacons = val;
                  });
                  if (val) {
                    startBeaconSimulation();
                  } else {
                    stopBeaconSimulation();
                  }
                },
              ),
            ],
          ),
        ],
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

            // Display current position
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.teal[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Current Position:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      // Show movement indicator
                      if (_isMoving)
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Moving',
                            style: TextStyle(fontSize: 10, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                      'X: ${currentPosition.x.toStringAsFixed(2)}, Y: ${currentPosition.y.toStringAsFixed(2)}'),
                  Text(
                      'Grid: ${converter.positionToGridCoords(currentPosition)[0]}, ${converter.positionToGridCoords(currentPosition)[1]}'),
                  Text(
                      'Meters: ${converter.pixelsToMeters(currentPosition.x).toStringAsFixed(1)}m, ${converter.pixelsToMeters(currentPosition.y).toStringAsFixed(1)}m'),
                  const SizedBox(height: 4),
                  Text('Detected beacons: ${beaconList.length}'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 2) Connect To Event (Beacon scan)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _startScanning,
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
              fieldViewBuilder:
                  (context, controller, focusNode, onEditingComplete) {
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

            // Beacon information
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
                    const Text(
                      'Beacon Information:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...beaconList.map((beacon) {
                      final distance = rssiToDistance(
                          beacon.rssi ?? beacon.baseRssi, beacon.baseRssi);
                      final gridDistance = converter.metersToGrid(distance);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Text(
                          '${beacon.id}: RSSI ${beacon.rssi}dBm (≈${distance.toStringAsFixed(1)}m / ${gridDistance.toStringAsFixed(1)} grid)',
                          style: const TextStyle(fontSize: 14),
                        ),
                      );
                    }),
                  ],
                ),
              ),

            // Movement Debugging Panel
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hybrid Positioning System:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('Status: ${_isMoving ? "Moving" : "Stationary"}'),
                  Text(
                      'Positioning Mode: ${_isMoving ? "BLE+IMU Fusion" : "BLE Multilateration"}'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        // Start scanning for BLE devices
                        _startScanning();
                      });
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: kTealColor),
                    child: const Text('Refresh Beacons'),
                  ),
                ],
              ),
            ),

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
                    MaterialPageRoute(builder: (_) => const GameScreen()),    setState(() {
                  );r();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kTealColor,
                  foregroundColor: Colors.white, // iOS-specific scanning
                  padding: const EdgeInsets.symmetric(vertical: 12),   _scanSubscription = flutterReactiveBle.scanForDevices(
                  textStyle: const TextStyle(fontSize: 16),       withServices: [],
                ),        scanMode: ScanMode.lowLatency,
                child: const Text("Game Mode"),      ).listen((device) {
              ),        if (device.name.toLowerCase() == "kontakt" &&
            ),            device.serviceData.containsKey(Uuid.parse("FE6A"))) {





















}  }    }      // ...existing code...    } else if (Platform.isAndroid) {      // ...existing code...    if (Platform.isIOS) {    await _scanSubscription?.cancel();  void _startScanning() async {  // ------------------- Start BLE Scanning -------------------  }    );      ),        ),          ],          final rawData = device.serviceData[Uuid.parse("FE6A")]!;
          final asciiBytes = rawData.sublist(13);
          final beaconId = String.fromCharCodes(asciiBytes);

          if (beaconIdToPosition.containsKey(beaconId)) {
            setState(() {
              scannedDevices[beaconId] = device.rssi;
            });
            _updateBeaconList();
          }
        }
      }, onError: (e) {
        debugPrint("❌ iOS BLE scan error: $e");
      });
    } else if (Platform.isAndroid) {
      // Android-specific scanning
      _scanSubscription = flutterReactiveBle.scanForDevices(
        withServices: [],
        scanMode: ScanMode.lowLatency,
      ).listen((device) {
        // Handle both Kontakt beacons and generic BLE devices
        if (device.name.toLowerCase() == "kontakt" && 
            device.serviceData.containsKey(Uuid.parse("FE6A"))) {
          // Kontakt beacon format - similar to iOS
          final rawData = device.serviceData[Uuid.parse("FE6A")]!;
          final asciiBytes = rawData.sublist(13);
          final beaconId = String.fromCharCodes(asciiBytes);
          
          if (beaconIdToPosition.containsKey(beaconId)) {
            setState(() {
              scannedDevices[beaconId] = device.rssi;
            });
            _updateBeaconList();
          }
        } else {
          // For other devices, check if the MAC address is in our mapping
          final mac = device.id; // On Android, device.id is the MAC address
          if (mac_to_id_map.containsKey(mac)) {
            final beaconId = mac_to_id_map[mac]!;
            if (beaconIdToPosition.containsKey(beaconId)) {
              setState(() {
                scannedDevices[beaconId] = device.rssi;
              });
              _updateBeaconList();
              debugPrint("🔗 Mapped MAC $mac to beacon ID $beaconId");
            }
          }
        }
      }, onError: (e) {
        debugPrint("❌ Android BLE scan error: $e");
      });
    }
    
    debugPrint("📡 BLE scanning started on ${Platform.isAndroid ? 'Android' : 'iOS'}");
  }
}



