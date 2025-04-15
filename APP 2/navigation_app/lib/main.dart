import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(NavigationApp());
}

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
  // Map to store scanned device info.
  Map<String, int> scannedDevices = {};
  String userLocation = "";
  String selectedBooth = "";
  List<String> boothNames = [];

  // Dictionary mapping beacon Major values (as strings) to their [x, y] position.
  final Map<String, List<int>> beaconIdToPosition = {
      "14j906Gy": [0, 0],
      "14jr08Ef": [20, 0],
      "14j606Gv": [0, 20],
      // Add more based on what you find from the logs
    };


  // Your known iBeacon Proximity UUID (without header).
  final String knownIBeaconUUID = "f7826da6-4fa2-4e98-8024-bc5b71e0893e";

  // Initialize FlutterReactiveBle instance and scan subscription.
  final flutterReactiveBle = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    // Listen to Bluetooth status for debugging.
    flutterReactiveBle.statusStream.listen((status) {
      print("Bluetooth status: $status");
    });
    fetchBoothNames();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }

  /// Formats 16 bytes into a standard UUID string (8-4-4-4-12).
  String _formatAsUuid(List<int> bytes) {
    final sb = StringBuffer();
    for (int i = 0; i < bytes.length; i++) {
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
      if (i == 3 || i == 5 || i == 7 || i == 9) sb.write('-');
    }
    return sb.toString().toLowerCase();
  }

  /// Parses the iBeacon advertisement manufacturer data.
  /// Returns the Proximity UUID if the data is in proper iBeacon format.
  String? parseIBeaconUUID(List<int> data) {
    if (data.length < 25) {
      print("Manufacturer data length is less than expected: ${data.length}");
      return null;
    }
    // Check that the first 4 bytes match the iBeacon header: [0x4c, 0x00, 0x02, 0x15].
    if (!(data[0] == 0x4c && data[1] == 0x00 && data[2] == 0x02 && data[3] == 0x15)) {
      print("Data does not match iBeacon header: ${data.sublist(0, 4)}");
      return null;
    }
    // Extract the 16-byte Proximity UUID.
    final uuidBytes = data.sublist(4, 20);
    final uuidStr = _formatAsUuid(uuidBytes);
    print("Parsed Proximity UUID: $uuidStr");
    return uuidStr;
  }

  /// Extracts the Major value from iBeacon advertisement data.
  int? parseMajor(List<int> data) {
    if (data.length < 25) return null;
    final major = (data[20] << 8) + data[21];
    print("Parsed Major: $major");
    return major;
  }

  // Start scanning for devices.
    void startScan() async {
      await _scanSubscription?.cancel();
      setState(() {
        scannedDevices.clear();
      });

      _scanSubscription = flutterReactiveBle.scanForDevices(
        withServices: [], // Scan all
        scanMode: ScanMode.lowLatency,
      ).listen((device) {
        // ✅ Filter only Kontakt beacons
        if (device.name.toLowerCase() == "kontakt" &&
            device.serviceData.containsKey(Uuid.parse("FE6A"))) {

          final rawData = device.serviceData[Uuid.parse("FE6A")]!;
          final asciiBytes = rawData.sublist(13);
          final beaconId = String.fromCharCodes(asciiBytes);

          print("🔎 Beacon ID: $beaconId");
          print("📶 RSSI: ${device.rssi}");

          // Match beaconId to a location
          if (beaconIdToPosition.containsKey(beaconId)) {
            final pos = beaconIdToPosition[beaconId]!;
            print("📍 Mapped Position: $pos");

            setState(() {
              scannedDevices[beaconId] = device.rssi;
            });
          } else {
            print("⚠️ Unknown beacon ID: $beaconId");
          }
        }
      }, onError: (error) {
        print("❌ Scan error: $error");
      });
    }



  Future<void> fetchBoothNames() async {
    final url = Uri.parse('http://143.215.53.49:8000/booths');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> booths = jsonDecode(response.body);
        setState(() {
          boothNames = booths.map((b) => b["name"] as String).toList();
        });
      } else {
        print("⚠️ Error fetching booths: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Exception while fetching booth list: $e");
    }
  }

  Future<void> sendToBackend(Map<String, int> scannedDevices) async {
    final url = Uri.parse('http://143.215.53.49:8000/locate');
    final body = {
      "ble_data": scannedDevices.entries
          .map((e) => {
                "uuid": e.key, // Consider sending additional data (such as Major) if needed.
                "rssi": e.value,
              })
          .toList()
    };
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          userLocation = "${data['x']}, ${data['y']}";
        });
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text("Your Location"),
            content: Text("You are at: ($userLocation)"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("OK"))
            ],
          ),
        );
      } else {
        print("⚠️ Server error: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Error connecting to backend: $e");
    }
  }

  Future<void> requestPath(String boothName) async {
    if (boothName.trim().isEmpty) {
      print("❌ Booth name is empty.");
      return;
    }
    if (userLocation.isEmpty || !userLocation.contains(",")) {
      print("❌ Invalid user location: $userLocation");
      return;
    }
    final start = userLocation.split(",").map((e) => int.parse(e.trim())).toList();
    final url = Uri.parse('http://143.215.53.49:8000/path');
    final body = {
      "from_": [start[0], start[1]],
      "to": boothName,
    };
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final path = data["path"];
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text("Path to $boothName"),
            content: path.isEmpty
                ? Text("No path found.")
                : Text(path.map((p) => "(${p[0]}, ${p[1]})").join(" → ")),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("OK"),
              ),
            ],
          ),
        );
      } else {
        print("⚠️ Path request error: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Error requesting path: $e");
    }
  }

  void openMapScreen() async {
    if (userLocation.isEmpty || selectedBooth.isEmpty) {
      print("Missing location or booth");
      return;
    }
    final start = userLocation.split(",").map((e) => int.parse(e.trim())).toList();
    final url = Uri.parse('http://143.215.53.49:8000/path');
    final body = {
      "from_": [start[0], start[1]],
      "to": selectedBooth,
    };
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final path = List<List<dynamic>>.from(data["path"]);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MapScreen(path: path, startLocation: start)),
        );
      } else {
        print("⚠️ Path request error: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Error requesting path: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("BLE Navigation")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: startScan,
              child: Text("Scan for Beacons"),
            ),
            SizedBox(height: 16),
            for (var entry in scannedDevices.entries)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Device ID: ${entry.key}", style: TextStyle(fontSize: 16)),
                  Text("RSSI: ${entry.value}", style: TextStyle(fontSize: 14)),
                  SizedBox(height: 10),
                ],
              ),
            if (scannedDevices.isNotEmpty)
              ElevatedButton(
                onPressed: () => sendToBackend(scannedDevices),
                child: Text("Get My Location"),
              ),
            if (userLocation.isNotEmpty) ...[
              SizedBox(height: 20),
              RawAutocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text == '')
                    return const Iterable<String>.empty();
                  return boothNames.where((String option) {
                    return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                  });
                },
                onSelected: (String selection) {
                  setState(() {
                    selectedBooth = selection;
                  });
                },
                fieldViewBuilder: (BuildContext context, TextEditingController textEditingController, FocusNode focusNode, VoidCallback onFieldSubmitted) {
                  return TextField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'Enter booth name',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      selectedBooth = value;
                    },
                  );
                },
                optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4.0,
                      child: ListView(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: options.map((String option) {
                          return ListTile(
                            title: Text(option),
                            onTap: () => onSelected(option),
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
              SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => requestPath(selectedBooth),
                child: Text("Find Path"),
              )
            ],
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: openMapScreen,
              child: Text("Show Map"),
            )
          ],
        ),
      ),
    );
  }
}

// ========================
// 🧭 MAP SCREEN
// ========================
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
    final url = Uri.parse("http://143.215.53.49:8000/map-data");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final fetchedElements = json["elements"];
        // Compute bounds.
        double maxXLocal = 0, maxYLocal = 0;
        for (var el in fetchedElements) {
          final start = el["start"];
          final end = el["end"];
          maxXLocal = [start["x"], end["x"], maxXLocal].reduce((a, b) => a > b ? a : b).toDouble();
          maxYLocal = [start["y"], end["y"], maxYLocal].reduce((a, b) => a > b ? a : b).toDouble();
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

      if (name.toLowerCase().contains("bathroom")) {
        debugPrint("🛁 Drawing bathroom at $startOffset to $endOffset");
      }

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

