import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/beacon.dart';
import './vector2d.dart';

/// Service to simulate BLE beacon signals for testing in emulators
class BleSimulator {
  // Singleton instance
  static final BleSimulator _instance = BleSimulator._internal();
  factory BleSimulator() => _instance;
  BleSimulator._internal();

  // Configuration
  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;
  int _updateIntervalMs = 1000;
  
  // Simulated beacons
  final Map<String, Beacon> _simulatedBeacons = {};
  final Map<String, Vector2D> _simulatedBeaconPositions = {};
  Vector2D _userPosition = const Vector2D(0, 0);
  
  // Output
  final Map<String, int> _scannedBeaconsRssi = {};
  Map<String, int> get scannedBeacons => _scannedBeaconsRssi;
  
  // Controllers
  final _beaconsController = StreamController<Map<String, int>>.broadcast();
  Stream<Map<String, int>> get beaconStream => _beaconsController.stream;
  
  // Simulation timer
  Timer? _simulationTimer;
  
  // Path loss model parameters (for realistic RSSI simulation)
  final double _referenceRssi = -59.0;  // RSSI at reference distance (1m)
  final double _pathLossExponent = 2.2; // Path loss exponent (2.0 for free space, higher for indoor)
  final double _noiseSigma = 2.0;       // Standard deviation of noise
  
  // Enable or disable the simulator
  void setEnabled(bool enabled) {
    if (_isEnabled == enabled) return;
    
    _isEnabled = enabled;
    if (_isEnabled) {
      _startSimulation();
    } else {
      _stopSimulation();
    }
    debugPrint('📡 BLE Simulator ${_isEnabled ? 'enabled' : 'disabled'}');
  }
  
  // Configure the beacon positions and properties
  void configureBeacons(Map<String, List<int>> beaconPositions, {int referenceRssi = -59}) {
    _simulatedBeacons.clear();
    _simulatedBeaconPositions.clear();
    
    beaconPositions.forEach((id, position) {
      final beaconPosition = Vector2D(position[0].toDouble(), position[1].toDouble());
      
      _simulatedBeaconPositions[id] = beaconPosition;
      _simulatedBeacons[id] = Beacon(
        id: id,
        name: id,
        baseRssi: referenceRssi,
        position: Position(
          x: beaconPosition.x,
          y: beaconPosition.y,
        ),
      );
    });
    
    debugPrint('📡 Configured ${_simulatedBeacons.length} simulated beacons');
  }
  
  // Set the current user position (to calculate realistic RSSI values)
  void setUserPosition(Vector2D position) {
    _userPosition = position;
    // Immediately update beacon readings
    if (_isEnabled) {
      _updateBeaconReadings();
    }
  }
  
  // Set how often the beacon readings update
  void setUpdateInterval(int milliseconds) {
    _updateIntervalMs = milliseconds;
    if (_isEnabled) {
      _stopSimulation();
      _startSimulation();
    }
  }
  
  // Start the beacon simulation
  void _startSimulation() {
    _simulationTimer = Timer.periodic(Duration(milliseconds: _updateIntervalMs), (_) {
      _updateBeaconReadings();
    });
    // Immediately update once
    _updateBeaconReadings();
  }
  
  // Stop the beacon simulation
  void _stopSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
  }
  
  // Update simulated beacon RSSI readings based on user position
  void _updateBeaconReadings() {
    _scannedBeaconsRssi.clear();
    
    _simulatedBeaconPositions.forEach((id, beaconPosition) {
      // Calculate distance between user and beacon
      final distance = Vector2D.distance(_userPosition, beaconPosition);
      
      // Calculate expected RSSI at this distance using log-distance path loss model
      final expectedRssi = _calculateRssiAtDistance(distance);
      
      // Add random noise
      final noise = _generateGaussianNoise(_noiseSigma);
      final rssi = (expectedRssi + noise).round();
      
      // Occasionally drop readings to simulate real-world behavior
      if (Random().nextDouble() > 0.1) { // 10% chance to drop reading
        _scannedBeaconsRssi[id] = rssi;
      }
    });
    
    // Broadcast the updated scanned beacons
    _beaconsController.add(_scannedBeaconsRssi);
  }
  
  // Calculate expected RSSI at a given distance using log-distance path loss model
  double _calculateRssiAtDistance(double distanceMeters) {
    if (distanceMeters <= 0.1) {
      distanceMeters = 0.1; // Prevent division by zero or log of zero
    }
    
    // Log-distance path loss model: RSSI = P₀ - 10 * n * log₁₀(d/d₀)
    // where P₀ is the power at reference distance d₀ (usually 1m)
    // n is the path loss exponent
    return _referenceRssi - 10 * _pathLossExponent * log(distanceMeters) / log(10);
  }
  
  // Generate Gaussian (normal) distributed random noise
  double _generateGaussianNoise(double sigma) {
    // Box-Muller transform to generate Gaussian noise from uniform distribution
    final u1 = Random().nextDouble();
    final u2 = Random().nextDouble();
    final z = sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
    return z * sigma;
  }
  
  // Add a single beacon with fixed RSSI for testing
  void addFixedBeacon(String id, int rssi) {
    _scannedBeaconsRssi[id] = rssi;
    _beaconsController.add(_scannedBeaconsRssi);
  }
  
  void dispose() {
    _stopSimulation();
    _beaconsController.close();
  }
}