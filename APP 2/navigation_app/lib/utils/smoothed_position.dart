import 'dart:async';
import 'dart:math';
import '../models/beacon.dart';
import './positioning.dart';
import './vector2d.dart';

class SmoothedPositionTracker {
  // Configuration properties
  final double alpha;
  final int intervalMs;

  // State
  Vector2D _currentPosition = Vector2D(0, 0);
  Vector2D _lastPosition = Vector2D(0, 0);
  List<Beacon> _beacons = [];
  double _metersToGridFactor = 2.0;

  // Timer for position updates
  Timer? _timer;

  // Stream controller to broadcast position updates
  final _positionController = StreamController<Vector2D>.broadcast();
  Stream<Vector2D> get positionStream => _positionController.stream;
  Vector2D get position => _currentPosition;

  SmoothedPositionTracker({
    this.alpha = 0.95,
    this.intervalMs = 500,
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
    _metersToGridFactor = metersToGridFactor;
  }

  void _updatePosition() {
    // Use a safe default position if we can't calculate one
    Vector2D newPos = _lastPosition;

    // Only consider beacons with valid RSSI values
    final connected = _beacons.where((b) => b.rssi != null).toList();

    if (connected.length >= 3) {
      // If we have 3+ beacons, use trilateration
      final calculatedPos = multilaterate(connected, _metersToGridFactor);
      newPos = Vector2D(calculatedPos['x']!, calculatedPos['y']!);
    } else if (connected.isNotEmpty) {
      // If we have 1-2 beacons, use the closest one
      connected.sort((a, b) {
        final da = rssiToDistance(a.rssi ?? a.baseRssi, a.baseRssi);
        final db = rssiToDistance(b.rssi ?? b.baseRssi, b.baseRssi);
        return da.compareTo(db);
      });

      final closest = connected.first;
      if (closest.position != null) {
        newPos = Vector2D(closest.position!.x, closest.position!.y);
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