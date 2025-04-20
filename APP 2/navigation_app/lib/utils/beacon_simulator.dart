import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/beacon.dart';
import './sensor_simulator.dart';
import './vector2d.dart';

/// Simulator for Bluetooth beacons in emulator environments
class BeaconSimulator {
  // Singleton pattern
  static final BeaconSimulator _instance = BeaconSimulator._internal();
  factory BeaconSimulator() => _instance;
  BeaconSimulator._internal();
  
  // Configuration
  bool _isRunning = false;
  int _updateIntervalMs = 1000;
  double _maxSignalDistance = 20.0; // in meters
  
  // Simulated beacons
  List<Beacon> _beacons = [];
  
  // Controller for RSSI updates
  final _beaconController = StreamController<Map<String, int>>.broadcast();
  Stream<Map<String, int>> get beaconUpdateStream => _beaconController.stream;
  
  // Update timer
  Timer? _updateTimer;
  
  // Sensor simulator for position
  final SensorSimulator _sensorSimulator = SensorSimulator();
  
  /// Start the beacon simulator
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    
    // Start periodic updates
    _updateTimer = Timer.periodic(
      Duration(milliseconds: _updateIntervalMs),
      (_) => _emitBeaconUpdate()
    );
    
    debugPrint('📡 Beacon simulator started with ${_beacons.length} beacons');
  }
  
  /// Stop the beacon simulator
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    
    _updateTimer?.cancel();
    _updateTimer = null;
    
    debugPrint('⏹️ Beacon simulator stopped');
  }
  
  /// Dispose resources
  void dispose() {
    stop();
    _beaconController.close();
  }
  
  /// Set up beacons with provided list
  void setupBeacons(List<Beacon> beacons) {
    _beacons = beacons;
    debugPrint('📡 Beacon simulator using ${beacons.length} custom beacons');
  }
  
  /// Set up some default beacons if none were provided
  void setupDefaultBeacons() {
    final beacons = [
      Beacon(
        id: 'beacon_1',
        name: 'Corner Beacon',
        position: Vector2D(100, 100),
        baseRssi: -59,
      ),
      Beacon(
        id: 'beacon_2',
        name: 'Center Beacon',
        position: Vector2D(300, 300),
        baseRssi: -59,
      ),
      Beacon(
        id: 'beacon_3',
        name: 'Far Beacon',
        position: Vector2D(500, 100),
        baseRssi: -59,
      ),
      Beacon(
        id: 'beacon_4',
        name: 'Entrance Beacon',
        position: Vector2D(100, 400),
        baseRssi: -59,
      ),
      Beacon(
        id: 'beacon_5',
        name: 'Exit Beacon',
        position: Vector2D(500, 400),
        baseRssi: -59,
      ),
    ];
    
    _beacons = beacons;
    debugPrint('📡 Beacon simulator using ${beacons.length} default beacons');
  }
  
  /// Return the current list of simulated beacons
  List<Beacon> get beacons => _beacons;
  
  /// Update interval between RSSI updates
  void setUpdateInterval(int milliseconds) {
    _updateIntervalMs = milliseconds;
    
    // Restart timer if running
    if (_isRunning) {
      _updateTimer?.cancel();
      _updateTimer = Timer.periodic(
        Duration(milliseconds: _updateIntervalMs),
        (_) => _emitBeaconUpdate()
      );
    }
  }
  
  /// Set maximum distance for beacon signal detection (meters)
  void setMaxDistance(double maxDistanceMeters) {
    _maxSignalDistance = maxDistanceMeters;
  }
  
  /// Generate and emit simulated RSSI values for all beacons
  void _emitBeaconUpdate() {
    if (!_isRunning || _beacons.isEmpty) return;
    
    final userPosition = _sensorSimulator.getPosition();
    final rssiValues = <String, int>{};
    
    // For each beacon, calculate RSSI based on distance
    for (final beacon in _beacons) {
      if (beacon.position != null) {
        final distance = sqrt(pow(userPosition.x - beacon.position!.x, 2) + pow(userPosition.y - beacon.position!.y, 2));
        
        // Convert from pixels to meters (40px = 1m)
        final distanceMeters = distance / 40;
        
        // Only include beacons within range
        if (distanceMeters <= _maxSignalDistance) {
          final rssi = _calculateRssiFromDistance(
            distanceMeters,
            baseRssi: beacon.baseRssi
          );
          
          rssiValues[beacon.id] = rssi;
        }
      }
    }
    
    // Emit the update if there are any beacons in range
    if (rssiValues.isNotEmpty) {
      _beaconController.add(rssiValues);
    }
  }
  
  /// Calculate RSSI from distance using the log-distance path loss model
  int _calculateRssiFromDistance(double distanceMeters, {int baseRssi = -59}) {
    if (distanceMeters <= 0) return baseRssi;
    
    // Path loss exponent (typically between 2.0 for free space and 4.0 for indoor)
    const pathLossExponent = 2.2;
    
    // Calculate RSSI using inverse of distance formula
    final calculatedRssi = baseRssi - (10 * pathLossExponent * log(distanceMeters) / log(10));
    
    // Add some realistic noise (±2 dB)
    final noise = Random().nextInt(5) - 2;
    
    return calculatedRssi.round() + noise;
  }
  
  /// Force an immediate beacon update
  void forceUpdate() {
    _emitBeaconUpdate();
  }
  
  /// Add a temporary simulated beacon
  void addTemporaryBeacon(Vector2D position, {Duration? duration}) {
    final id = 'temp_beacon_${DateTime.now().millisecondsSinceEpoch}';
    final beacon = Beacon(
      id: id,
      name: 'Temporary Beacon',
      position: position,
      baseRssi: -59,
    );
    
    _beacons.add(beacon);
    
    debugPrint('📡 Added temporary beacon at (${position.x}, ${position.y})');
    
    // Remove after duration if specified
    if (duration != null) {
      Future.delayed(duration, () {
        _beacons.removeWhere((b) => b.id == id);
        debugPrint('📡 Removed temporary beacon ($id)');
      });
    }
  }
}