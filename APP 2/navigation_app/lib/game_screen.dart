import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:http/http.dart' as http;
import 'package:navigation_app/map_screen.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:navigation_app/models/beacon.dart';
import 'package:navigation_app/utils/positioning.dart';
import 'package:navigation_app/utils/smoothed_position.dart';
import './utils/vector2d.dart';

// Global variable to preserve total points between screen navigations.
int globalTotalPoints = 0;
final Set<String> completedBoothNames = {};

class GameScreen extends StatefulWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  // ---------------- BLE & Positioning ----------------
  final flutterReactiveBle = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  late SmoothedPositionTracker positionTracker;
  Vector2D currentPosition = Vector2D(0, 0);
  StreamSubscription<Vector2D>? _positionSubscription;

  /// Mapping of known beacon IDs to their [x, y] positions.
  final Map<String, List<int>> beaconIdToPosition = {
    "14j906Gy": [0, 0],
    "14jr08Ef": [200, 0],
    "14j606Gv": [0, 200],
  };

  /// Stores scanned devices: beacon ID → RSSI.
  Map<String, int> scannedDevices = {};

  /// Current user location as a string "x, y".
  String userLocation = "";

  // Configuration from backend
  Map<String, dynamic> configData = {};
  int gridCellSize = 50;
  double metersToGridFactor = 2.0;
  int txPower = -59;
  bool isConfigLoaded = false;

  // ---------------- Map Data ----------------
  List<dynamic> elements = [];
  bool isMapDataLoaded = false;

  // ---------------- Game Tasks ----------------
  /// Each task contains fields:
  /// "id", "name", "category", "description", "x", "y", "points", and "completed".
  List<Map<String, dynamic>> tasks = [];
  int totalPoints = 0; // Loaded from globalTotalPoints.

  // Loading state for tasks.
  bool isLoading = true;

  // ---------------- Reward Popup Animation ----------------
  bool showReward = false;
  String rewardText = "";
  late final AnimationController _animationController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  // ---------------- Periodic Timer ----------------
  Timer? _proximityTimer;

  // ---------------- Request Path from Backend ----------------
  List<List<dynamic>> currentPath = [];

  @override
  void initState() {
    super.initState();
    // Load any existing points.
    totalPoints = globalTotalPoints;

    // Initialize position tracker with smoothing
    positionTracker = SmoothedPositionTracker(alpha: 0.85, intervalMs: 500);
    _positionSubscription = positionTracker.positionStream.listen((position) {
      setState(() {
        currentPosition = position;
        userLocation = "${position.x.round()}, ${position.y.round()}";
      });
    });

    // Start position tracking
    positionTracker.start();

    _startBleScan();
    fetchConfiguration().then((_) {
      _fetchMapData().then((_) {
        _fetchTasks(); // After fetching, isLoading is set to false.
      });
    });

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _scaleAnimation = Tween<double>(begin: 0, end: 1).animate(_animationController);
    _opacityAnimation = Tween<double>(begin: 0, end: 1).animate(_animationController);

    // Update user location and check proximity every second.
    _proximityTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _estimateUserLocation();
      _checkProximity();
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _positionSubscription?.cancel();
    positionTracker.dispose();
    _animationController.dispose();
    _proximityTimer?.cancel();
    super.dispose();
  }

  // Fetch configuration from backend
  Future<void> fetchConfiguration() async {
    try {
      final response = await http.get(Uri.parse('https://inmaps.onrender.com/config'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          configData = data;

          // Parse beacon positions
          final positions = data['beaconPositions'] as Map<String, dynamic>;
          beaconIdToPosition.clear();
          positions.forEach((key, value) {
            beaconIdToPosition[key] = [
              (value['x'] as num).toInt() * gridCellSize,
              (value['y'] as num).toInt() * gridCellSize
            ];
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
        _initializeDefaultConfig();
      }
    } catch (e) {
      debugPrint("❌ Error loading configuration: $e");
      _initializeDefaultConfig();
    }
  }

  // Initialize with default hardcoded values if backend config fails
  void _initializeDefaultConfig() {
    setState(() {
      gridCellSize = 50;
      metersToGridFactor = 2.0;
      txPower = -59;
      isConfigLoaded = true;
      debugPrint("⚠️ Using default configuration");
    });
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
          position: Position(
              x: position[0].toDouble(),
              y: position[1].toDouble()
          ),
        ));
      }
    });

    // Update the position tracker with new beacon data
    positionTracker.updateBeacons(updatedBeacons);
    positionTracker.updateCalibration(metersToGridFactor);

    // Add debug logging
    if (updatedBeacons.isNotEmpty) {
      debugPrint("🔍 Current beacons: ${updatedBeacons.map((b) => '${b.id}: (${b.position?.x}, ${b.position?.y})').join(', ')}");
    }
  }

  // ---------------- BLE Scanning ----------------
  void _startBleScan() async {
    await _scanSubscription?.cancel();
    if (mounted) {
      setState(() => scannedDevices.clear());
    }

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
          if (mounted) {
            setState(() {
              scannedDevices[beaconId] = device.rssi;
            });
            _updateBeaconList(); // Update beacons whenever we get new RSSI values
          }
        }
      }
    }, onError: (err) {
      debugPrint("❌ BLE scan error: $err");
    });
  }

  // ---------------- Estimate User Location ----------------
  void _estimateUserLocation() {
    // Convert scanned devices to Beacon objects
    final List<Beacon> beacons = [];
    scannedDevices.forEach((id, rssi) {
      if (beaconIdToPosition.containsKey(id)) {
        final pos = beaconIdToPosition[id]!;
        beacons.add(Beacon(
          id: id,
          rssi: rssi,
          baseRssi: -59, // Use the same reference power as in main.dart
          position: Position(
            x: pos[0].toDouble(),
            y: pos[1].toDouble(),
          ),
        ));
      }
    });

    // Use the utils version of multilaterate
    if (beacons.isNotEmpty) {
      final position = multilaterate(beacons, 1.0); // Use 1.0 as metersToGridFactor since we're already in grid units
      if (mounted) {
        setState(() => userLocation = "${position['x']!.round()}, ${position['y']!.round()}");
      }
    }
  }

  // ---------------- Fetch Map Data ----------------
  Future<void> _fetchMapData() async {
    debugPrint("🗺️ Starting map data fetch...");
    final url = Uri.parse("https://inmaps.onrender.com/map-data");
    try {
      debugPrint("📡 Sending request to $url");
      final response = await http.get(url);
      debugPrint("📥 Received response with status: ${response.statusCode}");
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final fetchedElements = json["elements"];
        debugPrint("📊 Received ${fetchedElements.length} elements");
        
        // Count zones
        int zoneCount = 0;
        for (var el in fetchedElements) {
          if (el["type"].toString().toLowerCase() == "zone") {
            zoneCount++;
          }
        }
        
        if (mounted) {
          setState(() {
            elements = fetchedElements;
            isMapDataLoaded = true;
          });
        }
        debugPrint("✅ Map data loaded successfully:");
        debugPrint("  - Total elements: ${elements.length}");
        debugPrint("  - Walkable zones: $zoneCount");
      } else {
        debugPrint("❌ Map fetch failed with status: ${response.statusCode}");
        debugPrint("Response body: ${response.body}");
      }
    } catch (e, stackTrace) {
      debugPrint("❌ Map fetch failed with error: $e");
      debugPrint("Stack trace: $stackTrace");
    }
  }

  // ---------------- Fetch Tasks ----------------
  Future<void> _fetchTasks() async {
    final url = Uri.parse('https://inmaps.onrender.com/booths');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);
        List<dynamic> booths;
        if (data is List) {
          booths = data;
        } else if (data is Map && data.containsKey("elements")) {
          booths = data["elements"];
        } else {
          throw Exception("Unexpected JSON format");
        }
        debugPrint("DEBUG: Fetched booths: ${booths.length} items.");
        if (mounted) {
          setState(() {
            // Map tasks and filter only those with type "booth"
            tasks = booths.map<Map<String, dynamic>>((b) {
              final start = b["start"] ?? {"x": 0, "y": 0};
              final end = b["end"] ?? {"x": 0, "y": 0};
              final centerX = ((start["x"] as num) + (end["x"] as num)) / 2;
              final centerY = ((start["y"] as num) + (end["y"] as num)) / 2;
              // Check if this booth was previously completed
              final existingTask = tasks.firstWhere(
                    (t) => t["name"] == b["name"],
                orElse: () => {"completed": false},
              );
              return {
                "id": b["booth_id"]?.toString() ?? "",
                "name": b["name"] ?? "Unnamed",
                "type": b["type"]?.toString().toLowerCase() ?? "",
                "description": b["description"] ?? "No description available",
                "x": centerX,
                "y": centerY,
                "points": b["points"] ?? 20,
                "completed": completedBoothNames.contains(b["name"]), // Preserve completion status
              };
            }).where((t) => t["type"] == "booth").toList();
            isLoading = false;
            debugPrint("DEBUG: tasks in GameScreen: ${tasks.length} items.");
          });
        }
      } else {
        debugPrint("❌ Could not fetch tasks. Status = ${response.statusCode}");
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint("❌ Task fetch error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ---------------- Check Proximity ----------------
  void _checkProximity() {
    if (userLocation.isEmpty || tasks.isEmpty) return;
    final parts = userLocation.split(',');
    if (parts.length < 2) return;
    final userX = double.tryParse(parts[0].trim()) ?? 0;
    final userY = double.tryParse(parts[1].trim()) ?? 0;
    const proximityThreshold = 5.0;

    for (var task in tasks) {
      if (!task["completed"]) {
        final dx = (task["x"] as double) - userX;
        final dy = (task["y"] as double) - userY;
        final dist = sqrt(dx * dx + dy * dy);

        // Do not auto-complete here! Only optionally show UI
        if (dist < proximityThreshold) {
          debugPrint("ℹ️ Nearby booth: ${task["name"]}, but not marking completed.");
        }
      }
    }
  }

  // ---------------- Show Task Notification Dialog ----------------
  void _showTaskDialog(Map<String, dynamic> task) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(task["name"]),
        content: Text("If you go to ${task["name"]}, you win ${task["points"]} points!"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(); // just close the dialog
            },
            child: const Text("Exit"),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(); // close the dialog
              _navigateToTask(task);             // immediately call your navigation
            },
            child: const Text("Go Now"),
          ),
        ],
      ),
    );
  }

  // ---------------- Request Path from Backend ----------------
  Future<void> requestPath(String boothName, List<int> start) async {
    debugPrint("🔍 Requesting path to $boothName");
    try {
      final response = await http.post(
        Uri.parse('https://inmaps.onrender.com/path'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "from_": start,
          "to": boothName
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        currentPath = List<List<dynamic>>.from(decoded["path"]);
        debugPrint("✅ Path received with ${currentPath.length} points");
      } else {
        debugPrint("❌ Non-200 status: ${response.statusCode}");
        debugPrint("Response body: ${response.body}");
        throw Exception("Failed to get path");
      }
    } catch (e) {
      debugPrint("❌ Path request error: $e");
      throw e;
    }
  }

  // ---------------- Navigate to Map Screen for the Selected Task ----------------
  Future<void> _navigateToTask(Map<String, dynamic> task) async {
    debugPrint("\n🚀 Starting navigation to booth: ${task["name"]}");
    debugPrint("Current state:");
    debugPrint("  - Map data loaded: $isMapDataLoaded");
    debugPrint("  - Elements count: ${elements.length}");
    debugPrint("  - User location: $userLocation");
    
    if (!isMapDataLoaded) {
      debugPrint("❌ Map data not loaded yet");
      _showErrorDialog("Please wait while map data is loading...");
      await _fetchMapData();
      if (!isMapDataLoaded) {
        debugPrint("❌ Still couldn't load map data");
        return;
      }
    }

    // Check if we have a valid location
    if (userLocation.isEmpty) {
      debugPrint("❌ No valid location yet");
      _showErrorDialog("Please wait while we detect your location...");
      return;
    }

    // 1) Convert to grid coords & capture start
    var parts = userLocation.split(",");
    if (parts.length != 2) parts = ["0","0"];
    final userX = double.tryParse(parts[0].trim()) ?? 0.0;
    final userY = double.tryParse(parts[1].trim()) ?? 0.0;
    const double cellSize = 40.0;
    final int gridX = (userX / cellSize).floor();
    final int gridY = (userY / cellSize).floor();
    final start = [gridX, gridY];

    // Check if we have a valid grid position
    if (gridX == 0 && gridY == 0) {
      debugPrint("❌ Invalid grid position: $start");
      _showErrorDialog("Please wait while we get a better location fix...");
      return;
    }

    // 2) Get heading
    final heading = await FlutterCompass.events!.first;
    final double headingDegrees = heading.heading ?? 0.0;
    debugPrint("🧭 Current heading: $headingDegrees°");

    try {
      // 3) Get path from backend
      await requestPath(task["name"], start);

      // 4) Prepend our start cell to the returned route
      final displayPath = [
        [gridX, gridY],
        ...currentPath
      ];

      // 5) Navigate with that complete path
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MapScreen(
            path: displayPath,
            startLocation: start,
            headingDegrees: headingDegrees,
            initialPosition: Vector2D(gridX * cellSize, gridY * cellSize),
            selectedBoothName: task["name"],
            onArrival: (arrived) {
              debugPrint("🏁 onArrival: $arrived");
              if (arrived && !completedBoothNames.contains(task["name"])) {
                setState(() {
                  task["completed"] = true;
                  completedBoothNames.add(task["name"]);
                  totalPoints += (task["points"] as int);
                  globalTotalPoints = totalPoints;
                  rewardText = "+${task["points"]} points!";
                  showReward = true;
                });
                _animationController.forward(from: 0);
                Future.delayed(const Duration(milliseconds: 1500), () {
                  if (mounted) setState(() => showReward = false);
                });
              }
            },
          ),
        ),
      );
      debugPrint("✅ Navigator.push() done");
    } catch (e, st) {
      debugPrint("❌ Navigation error: $e\n$st");
      _showErrorDialog("An error occurred. Please try again.");
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Navigation Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Game Mode"),
        backgroundColor: Colors.green.shade700,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : tasks.isEmpty
          ? const Center(child: Text("No booths found."))
          : Stack(
        children: [
          // Main content: header and task list.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Total Points",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      "$totalPoints",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "Booths",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final t = tasks[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: t["completed"] ? Colors.green : Colors.grey.shade300,
                          width: t["completed"] ? 2 : 1,
                        ),
                      ),
                      child: InkWell(
                        onTap: () => _showTaskDialog(t),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: t["completed"] ? Colors.green.shade50 : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    t["completed"] ? Icons.check_circle : Icons.store,
                                    color: t["completed"] ? Colors.green : Colors.grey,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      t["name"],
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: t["completed"] ? Colors.green.shade700 : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                t["type"] ?? "Booth",
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t["completed"] ? "✅ Completed" : "🕓 Pending",
                                style: TextStyle(
                                  color: t["completed"] ? Colors.green : Colors.orange,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Reward: ${t["points"]} pts",
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          // Reward popup overlay.
          if (showReward)
            Positioned.fill(
              child: Center(
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: FadeTransition(
                    opacity: _opacityAnimation,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.green.shade400,
                            Colors.green.shade600,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
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
                            Icons.stars,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            rewardText,
                            style: const TextStyle(
                              fontSize: 24,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
