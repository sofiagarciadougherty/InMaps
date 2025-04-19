import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'dart:async';

class BLEScannerService {
  static final BLEScannerService _instance = BLEScannerService._internal();
  factory BLEScannerService() => _instance;

  BLEScannerService._internal();

  final FlutterReactiveBle flutterReactiveBle = FlutterReactiveBle();
  final Map<String, int> scannedDevices = {};
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  
  // Stream controller for RSSI updates
  final _rssiController = StreamController<Map<String, int>>.broadcast();
  Stream<Map<String, int>> get rssiStream => _rssiController.stream;

  final Map<String, List<int>> beaconIdToPosition = {
    "14j906Gy": [0, 0],
    "14jr08Ef": [200, 0],
    "14j606Gv": [0, 200],
  };

  void startScan(Function(String, int) onUpdate) {
    _scanSubscription?.cancel();

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
          onUpdate(beaconId, device.rssi);
          
          // Emit the updated RSSI values to the stream
          _rssiController.add(Map<String, int>.from(scannedDevices));
        }
      }
    }, onError: (e) => print("❌ Scan error: $e"));
  }

  // Method for FusedPositionTracker to start scanning without callback
  void startScanning() {
    _scanSubscription?.cancel();

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
          
          // Emit the updated RSSI values to the stream
          _rssiController.add(Map<String, int>.from(scannedDevices));
        }
      }
    }, onError: (e) => print("❌ Scan error: $e"));
    
    print("📱 BLE scanning started");
  }

  void stopScan() {
    _scanSubscription?.cancel();
  }
  
  // Alias for stopScan to match FusedPositionTracker API
  void stopScanning() {
    stopScan();
    print("📱 BLE scanning stopped");
  }
  
  void dispose() {
    stopScan();
    _rssiController.close();
  }

  Map<String, int> getScannedDevices() => scannedDevices;
}
