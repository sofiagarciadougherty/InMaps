import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

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

  // MAC address to beacon ID mapping
  Map<String, String> _macToIdMap = {};
  
  // Store beacon positions for quick lookup
  Map<String, List<int>> beaconIdToPosition = {
    "14j906Gy": [0, 0],
    "14jr08Ef": [200, 0],
    "14j606Gv": [0, 200],
  };

  // Configure the service with mapping data from backend
  void configure({
    required Map<String, String> macToIdMap,
    required Map<String, List<int>> beaconPositions,
  }) {
    _macToIdMap = macToIdMap;
    beaconIdToPosition = beaconPositions;
    debugPrint("📱 BLE Scanner Service configured with ${_macToIdMap.length} MAC mappings");
  }

  void startScan(Function(String, int) onUpdate) {
    _scanSubscription?.cancel();

    _scanSubscription = flutterReactiveBle.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      // Handle iOS Kontakt beacons
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
      // Handle Android devices using MAC address
      else if (Platform.isAndroid) {
        final mac = device.id; // On Android, device.id is the MAC address
        if (_macToIdMap.containsKey(mac)) {
          final beaconId = _macToIdMap[mac]!;
          if (beaconIdToPosition.containsKey(beaconId)) {
            scannedDevices[beaconId] = device.rssi;
            onUpdate(beaconId, device.rssi);
            
            // Emit the updated RSSI values to the stream
            _rssiController.add(Map<String, int>.from(scannedDevices));
            debugPrint("🔗 BLE Service: Mapped MAC $mac to beacon ID $beaconId");
          }
        }
      }
    }, onError: (e) => debugPrint("❌ Scan error: $e"));
    
    debugPrint("📱 BLE scanning started on ${Platform.isAndroid ? 'Android' : 'iOS'}");
  }

  // Method for FusedPositionTracker to start scanning without callback
  void startScanning() {
    _scanSubscription?.cancel();

    _scanSubscription = flutterReactiveBle.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      // Process iOS Kontakt beacons
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
      // Process Android devices using MAC address mapping
      else if (Platform.isAndroid) {
        final mac = device.id;
        if (_macToIdMap.containsKey(mac)) {
          final beaconId = _macToIdMap[mac]!;
          if (beaconIdToPosition.containsKey(beaconId)) {
            scannedDevices[beaconId] = device.rssi;
            
            // Emit the updated RSSI values to the stream
            _rssiController.add(Map<String, int>.from(scannedDevices));
          }
        }
      }
    }, onError: (e) => debugPrint("❌ Scan error: $e"));
    
    debugPrint("📱 BLE scanning started");
  }

  void stopScan() {
    _scanSubscription?.cancel();
  }
  
  // Alias for stopScan to match FusedPositionTracker API
  void stopScanning() {
    stopScan();
    debugPrint("📱 BLE scanning stopped");
  }
  
  void dispose() {
    stopScan();
    _rssiController.close();
  }

  Map<String, int> getScannedDevices() => scannedDevices;
}
