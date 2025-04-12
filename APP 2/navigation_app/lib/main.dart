import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  Map<String, int> scannedDevices = {};
  String userLocation = "";
  String selectedBooth = "";
  List<String> boothNames = [];

  @override
  void initState() {
    super.initState();
    fetchBoothNames();
  }

  void startScan() {
    scannedDevices.clear();
    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        scannedDevices["D1:AA:BE:01:01:01"] = -60;
        scannedDevices["D2:BB:BE:02:02:02"] = -78;
        scannedDevices["D3:CC:BE:03:03:03"] = -82;
      });
    });
  }

  Future<void> fetchBoothNames() async {
    final url = Uri.parse('http://10.0.2.2:8000/booths');
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
    final url = Uri.parse('http://10.0.2.2:8000/locate');
    final body = {
      "ble_data": scannedDevices.entries.map((e) => {
        "uuid": e.key,
        "rssi": e.value,
      }).toList()
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
              TextButton(onPressed: () => Navigator.pop(context), child: Text("OK"))
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
    final url = Uri.parse('http://10.0.2.2:8000/path');
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
    final url = Uri.parse('http://10.0.2.2:8000/path');
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
                  if (textEditingValue.text == '') return const Iterable<String>.empty();
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
    final url = Uri.parse("http://10.0.2.2:8000/map-data");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final fetchedElements = json["elements"];

        // Compute bounds
        double maxXLocal = 0, maxYLocal = 0;
        for (var el in fetchedElements) {
          final start = el["start"];
          final end = el["end"];

          maxXLocal = [start["x"], end["x"], maxXLocal].reduce((a, b) => a > b ? a : b).toDouble();
          maxYLocal = [start["y"], end["y"], maxYLocal].reduce((a, b) => a > b ? a : b).toDouble();
        }

        setState(() {
          elements = fetchedElements;
          maxX = maxXLocal + 100; // 100 px padding
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
      final type = el["type"].toString().toLowerCase(); // normalize the type

      final startOffset = Offset(start["x"].toDouble(), start["y"].toDouble());
      final endOffset = Offset(end["x"].toDouble(), end["y"].toDouble());
      final center = Offset(
        (start["x"] + end["x"]) / 2,
        (start["y"] + end["y"]) / 2,
      );

      // DEBUG
      if (name.toLowerCase().contains("bathroom")) {
        debugPrint("🛁 Drawing bathroom at $startOffset to $endOffset");
      }

      Paint paint;
      if (type == "blocker") {
        paint = paintBlocker;
      } else if (type == "booth") {
        paint = paintBooth;
      } else {
        paint = paintOther; // Fallback paint
      }

      canvas.drawRect(
        Rect.fromPoints(startOffset, endOffset),
        type == "blocker"
            ? paintBlocker
            : type == "booth"
            ? paintBooth
            : paintOther,
      );

      canvas.drawCircle(
        Offset((startLocation[0]+0.5) * cellSize, (startLocation[1]+0.5) * cellSize),
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


    // Draw navigation path
    if (path.isNotEmpty) {
      for (int i = 0; i < path.length - 1; i++) {
        final p1 = Offset((path[i][0] + 0.5) * cellSize, (path[i][1] + 0.5) * cellSize);
        final p2 = Offset((path[i + 1][0]+0.5) * cellSize, (path[i + 1][1] + 0.5) * cellSize);
        canvas.drawLine(p1, p2, paintPath);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}




