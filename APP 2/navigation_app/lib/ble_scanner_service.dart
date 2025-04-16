import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'dart:async';

const double metersPerCell = 0.5;
const double pixelsPerMeter = 50.0;
const double cellSize = metersPerCell * pixelsPerMeter;


class BLEScannerService {
  static final BLEScannerService _instance = BLEScannerService._internal();
  factory BLEScannerService() => _instance;

  BLEScannerService._internal();

  final FlutterReactiveBle flutterReactiveBle = FlutterReactiveBle();
  final Map<String, int> scannedDevices = {};
  StreamSubscription<DiscoveredDevice>? _scanSubscription;

  // Beacon positions in METERS now
  final Map<String, List<double>> beaconIdToPosition = {
    "14j906Gy": [0.0, 25.0],
    "14jr08Ef": [8.66, 15.0],
    "14j606Gv": [0.0, 0.0],
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
        }
      }
    }, onError: (e) => print("❌ Scan error: \$e"));
  }

  void stopScan() {
    _scanSubscription?.cancel();
  }

  Map<String, int> getScannedDevices() => scannedDevices;
}
