import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

void main() {
  runApp(const NavigationApp());
}

class NavigationApp extends StatelessWidget {
  const NavigationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Navigation',
      home: BLEScannerPage(),
    );
  }
}

class BLEScannerPage extends StatefulWidget {
  const BLEScannerPage({super.key});

  @override
  State<BLEScannerPage> createState() => _BLEScannerPageState();
}

class _BLEScannerPageState extends State<BLEScannerPage> {
  final flutterReactiveBle = FlutterReactiveBle();
  late Stream<DiscoveredDevice> scanStream;
  final Map<String, int> scannedDevices = {};

  void startScan() {
    scannedDevices.clear();

    // Simulate a 2-second scan delay
    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        scannedDevices["D1:AA:BE:01:01:01"] = -60;
        scannedDevices["D2:BB:BE:02:02:02"] = -78;
        scannedDevices["D3:CC:BE:03:03:03"] = -82;
      });
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("BLE Navigation")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: startScan,
              child: const Text("Scan for Beacons"),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                children: scannedDevices.entries
                    .map((e) => ListTile(
                  title: Text("Device ID: ${e.key}"),
                  subtitle: Text("RSSI: ${e.value}"),
                ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

