import 'dart:async';
import '../models/beacon.dart';
import './positioning.dart';
import './vector2d.dart';
import './unit_converter.dart';
import '../ble_scanner_service.dart';

class SmoothedPositionTracker {
  // Configuration properties
  final double alpha;
  final int intervalMs;

  // State
  Vector2D _currentPosition = const Vector2D(0, 0);
  Vector2D _lastPosition = const Vector2D(0, 0);
  List<Beacon> _beacons = [];

  // Add access to UnitConverter or its factors
  final UnitConverter _converter = UnitConverter(); // Assuming default config is okay initially

  // Timer for position updates
  Timer? _timer;

  // Stream controller to broadcast position updates
  final _positionController = StreamController<Vector2D>.broadcast();
  Stream<Vector2D> get positionStream => _positionController.stream;
  Vector2D get position => _currentPosition;

  // BLEScannerService instance
  final BLEScannerService bleScanner;

  SmoothedPositionTracker({
    this.alpha = 0.95,
    this.intervalMs = 500,
    required this.bleScanner,
  });

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _updatePosition();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    _positionController.close();
  }

  void updateBeacons(List<Beacon> beacons) {
    _beacons = beacons;
  }

  void updateCalibration(double metersToGridFactor) {
    _converter.metersToGridFactor = metersToGridFactor; // Keep converter updated
  }

  void _updatePosition() {
    // Use a safe default position if we can't calculate one
    Vector2D newPos = _lastPosition;
    final now = DateTime.now();

    // Only consider beacons with valid RSSI, position, and recent lastSeen
    final connected = _beacons.where((b) =>
      b.rssi != null &&
      b.position != null &&
      bleScanner.lastSeenMap[b.id] != null &&
      now.difference(bleScanner.lastSeenMap[b.id]!) < Duration(seconds: 10)
    ).toList();

    if (connected.isNotEmpty) {
      // Calculate pixels per meter using the converter
      final pixelsPerMeter = _converter.metersToGridFactor * _converter.pixelsPerGridCell;

      if (connected.length >= 3) {
        // If we have 3+ beacons, use multilaterate with pixelsPerMeter
        final calculatedPos = multilaterate(connected, pixelsPerMeter);
        newPos = Vector2D(calculatedPos['x']!, calculatedPos['y']!);
      } else {
        // If we have 1-2 beacons, use the closest one
        connected.sort((a, b) {
          final da = rssiToDistance(a.rssi!, a.baseRssi);
          final db = rssiToDistance(b.rssi!, b.baseRssi);
          return da.compareTo(db);
        });

        final closest = connected.first;
        // Position is already in pixels (Vector2D)
        newPos = closest.position!;
      }
    }

    // Apply exponential smoothing
    final smoothed = Vector2D(
        _lastPosition.x * (1 - alpha) + newPos.x * alpha,
        _lastPosition.y * (1 - alpha) + newPos.y * alpha
    );

    _lastPosition = smoothed;
    _currentPosition = smoothed;

    // Broadcast the new position
    _positionController.add(_currentPosition);
  }
}