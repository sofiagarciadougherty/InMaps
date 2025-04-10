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
  List<String> boothSuggestions = [
    'Tesla',
    'Google',
    'Amazon',
    'Walmart',
    'Apple',
  ];

  // 🧪 Mock booth location map
  final Map<String, List<int>> mockBoothCoords = {
    "Tesla": [1, 7],
    "Google": [5, 2],
    "Amazon": [8, 6],
    "Walmart": [2, 3],
    "Apple": [6, 6],
  };

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

  Future<void> sendToBackend(Map<String, int> scannedDevices) async {
    final url = Uri.parse('http://128.61.122.99:8000/locate');
    final body = {
      "ble_data": scannedDevices.entries.map((e) => {
        "uuid": e.key,
        "rssi": e.value
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
        print("📍 You are at: ($userLocation)");
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
    final url = Uri.parse('http://128.61.122.99:8000/path');
    final body = {
      "from_": [start[0], start[1]],
      "to": boothName
    };

    print("📤 Sending path request: $body");

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final path = data["path"];
        print("🛣️ Path: $path");

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
        print("🧾 Response body: ${response.body}");
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
              TextField(
                onChanged: (value) {
                  setState(() {
                    selectedBooth = value;
                  });
                },
                decoration: InputDecoration(
                  labelText: "Enter booth name",
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => requestPath(selectedBooth),
                child: Text("Find Path"),
              )
            ]
          ],
        ),
      ),
    );
  }
}



