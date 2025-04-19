import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import './vector2d.dart';
import './step_detector.dart';
import './sensor_simulator.dart';
import './beacon_simulator.dart';
import '../models/beacon.dart';
import '../ble_scanner_service.dart';

/// Class for fusing BLE and IMU data to provide accurate position tracking
class FusedPositionTracker {
  // Configuration
  bool _isRunning = false;
  final bool _useSimulators;
  final int _updateIntervalMs;
  final bool _debugMode;
  
  // Data sources
  final BLEScannerService _bleScanner;
  final StepDetector _stepDetector;
  final BeaconSimulator _beaconSimulator = BeaconSimulator();
  final SensorSimulator _sensorSimulator = SensorSimulator();
  
  // Position data
  Vector2D _currentPosition;
  Vector2D _lastBlePosition = const Vector2D(0, 0);
  Vector2D _imuOffset = const Vector2D(0, 0);
  double _currentHeading = 0; // Degrees
  
  // Positioning state
  DateTime _lastBleUpdate = DateTime.now();
  int _stepsSinceLastBleUpdate = 0;
  double _driftCorrectionFactor = 1.0;
  double _lastDrift = 0.0;
  
  // Confidence weights (0.0-1.0)
  double _bleConfidence = 0.8;  
  double _imuConfidence = 0.2;
  
  // Streams
  final _positionController = StreamController<Vector2D>.broadcast();
  Stream<Vector2D> get positionStream => _positionController.stream;
  
  // Subscriptions
  StreamSubscription? _compassSubscription;
  StreamSubscription<StepEvent>? _stepSubscription;
  StreamSubscription<Map<String, int>>? _bleSubscription;
  StreamSubscription<Map<String, int>>? _simulatedBleSubscription;
  Timer? _updateTimer;
  
  // Beacon data
  List<Beacon> _knownBeacons = [];
  
  // Debug data
  final Map<String, dynamic> _debugInfo = {
    'blePosition': {'x': 0.0, 'y': 0.0},
    'imuOffset': {'x': 0.0, 'y': 0.0},
    'driftCorrectionFactor': 1.0,
    'stepsSinceLastBleUpdate': 0,
    'lastDrift': 0.0,
    'confidence': {'ble': 0.8, 'imu': 0.2},
  };
  
  FusedPositionTracker({
    required BLEScannerService bleScanner,
    required Vector2D initialPosition,
    bool useSimulators = false,
    int updateIntervalMs = 100,
    bool debugMode = true,
  }) : _bleScanner = bleScanner,
       _currentPosition = initialPosition, 
       _useSimulators = useSimulators,
       _updateIntervalMs = updateIntervalMs,
       _debugMode = debugMode,
       _stepDetector = StepDetector(useSimulator: useSimulators);
  
  /// Start tracking position
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    
    // Initialize state
    _lastBlePosition = _currentPosition.copy();
    _imuOffset = const Vector2D(0, 0);
    
    // Start step detection
    _stepDetector.start();
    _stepSubscription = _stepDetector.stepStream.listen(_onStep);
    
    // Start compass updates
    if (_useSimulators) {
      _sensorSimulator.start();
      _compassSubscription = _sensorSimulator.compassStream.listen(_onSimulatedCompassUpdate);
    } else {
      _compassSubscription = FlutterCompass.events?.listen(_onCompassUpdate);
    }
    
    // Start BLE scanning
    if (_useSimulators) {
      _beaconSimulator.setupDefaultBeacons();
      _beaconSimulator.start();
      _simulatedBleSubscription = _beaconSimulator.beaconUpdateStream.listen(_onBeaconUpdate);
    } else {
      _bleScanner.startScanning();
      _bleSubscription = _bleScanner.rssiStream.listen(_onBeaconUpdate);
    }
    
    // Periodic updates for position blending
    _updateTimer = Timer.periodic(Duration(milliseconds: _updateIntervalMs), (_) {
      _updateFusedPosition();
    });
    
    debugPrint('🔄 Started fusion position tracker${_useSimulators ? ' in simulation mode' : ' with real sensors'}');
  }
  
  /// Stop tracking position
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    
    // Stop step detection
    _stepDetector.stop();
    _stepSubscription?.cancel();
    _stepSubscription = null;
    
    // Stop compass updates
    _compassSubscription?.cancel();
    _compassSubscription = null;
    if (_useSimulators) {
      _sensorSimulator.stop();
    }
    
    // Stop BLE scanning
    _bleSubscription?.cancel();
    _bleSubscription = null;
    _simulatedBleSubscription?.cancel();
    _simulatedBleSubscription = null;
    if (!_useSimulators) {
      _bleScanner.stopScanning();
    }
    if (_useSimulators) {
      _beaconSimulator.stop();
    }
    
    // Stop periodic updates
    _updateTimer?.cancel();
    _updateTimer = null;
    
    debugPrint('⏹️ Stopped fusion position tracker');
  }
  
  /// Dispose all resources
  void dispose() {
    stop();
    _positionController.close();
  }
  
  /// Register known beacon positions for triangulation
  void registerBeacons(List<Beacon> beacons) {
    _knownBeacons = beacons;
    if (_useSimulators) {
      _beaconSimulator.setupBeacons(beacons);
    }
    debugPrint('📡 Registered ${beacons.length} beacons for positioning');
  }
  
  /// Alias for registerBeacons to maintain API compatibility
  void updateBeacons(List<Beacon> beacons) {
    registerBeacons(beacons);
  }
  
  /// Update the calibration factor for distance calculations
  void updateCalibration(double metersToGridFactor) {
    debugPrint('📏 Updating calibration factor: $metersToGridFactor');
    // Store the calibration factor if needed for future calculations
    // This method is called from main.dart when calibration changes
  }
  
  /// Handle compass updates from real device
  void _onCompassUpdate(CompassEvent event) {
    if (event.heading != null) {
      _currentHeading = event.heading!;
      
      // Update debug info
      if (_debugMode) {
        _debugInfo['heading'] = _currentHeading;
      }
    }
  }

  /// Handle compass updates from simulator
  void _onSimulatedCompassUpdate(SimulatedCompassEvent event) {
    if (event.heading != null) {
      _currentHeading = event.heading!;
      
      // Update debug info
      if (_debugMode) {
        _debugInfo['heading'] = _currentHeading;
      }
    }
  }
  
  /// Handle beacon RSSI updates
  void _onBeaconUpdate(Map<String, int> rssiValues) {
    // Calculate position using multilateration
    final position = _calculatePositionFromRSSI(rssiValues);
    if (position != null) {
      _lastBleUpdate = DateTime.now();
      
      // Calculate drift between BLE and dead reckoning
      _lastBlePosition = position;
      
      // Calculate the drift that occurred since last BLE update
      if (_stepsSinceLastBleUpdate > 0) {
        final drift = Vector2D.distance(
          _currentPosition, 
          _lastBlePosition
        );
        
        _lastDrift = drift;
        
        // Adapt the correction factor to minimize drift
        if (drift > 5) { // More than 5 pixels drift
          // Increase BLE confidence temporarily
          _bleConfidence = min(0.95, _bleConfidence + 0.1);
          _imuConfidence = 1.0 - _bleConfidence;
          
          // Adjust dead reckoning correction factor
          if (_stepsSinceLastBleUpdate > 0) {
            final driftPerStep = drift / _stepsSinceLastBleUpdate;
            
            if (driftPerStep > 2) {
              // Significant drift, adjust correction factor
              _driftCorrectionFactor *= 0.9;
            } else if (driftPerStep < 1) {
              // Low drift, slightly increase factor
              _driftCorrectionFactor *= 1.05;
            }
            
            // Clamp to reasonable range
            _driftCorrectionFactor = _driftCorrectionFactor.clamp(0.5, 1.5);
          }
        } else {
          // Low drift, gradually restore confidence balance
          _bleConfidence = max(0.5, _bleConfidence - 0.05);
          _imuConfidence = 1.0 - _bleConfidence;
        }
      }
      
      _stepsSinceLastBleUpdate = 0;
      
      // Update debug info
      if (_debugMode) {
        _debugInfo['blePosition'] = {'x': position.x, 'y': position.y};
        _debugInfo['lastDrift'] = _lastDrift;
        _debugInfo['driftCorrectionFactor'] = _driftCorrectionFactor;
        _debugInfo['confidence'] = {
          'ble': _bleConfidence,
          'imu': _imuConfidence,
        };
      }
    }
  }
  
  /// Calculate position from RSSI values using multilateration
  Vector2D? _calculatePositionFromRSSI(Map<String, int> rssiValues) {
    // Need at least 3 beacons with known positions for triangulation
    final usableBeacons = _knownBeacons.where((b) => 
      b.position != null && 
      rssiValues.containsKey(b.id)).toList();
      
    if (usableBeacons.length < 3) return null;
    
    // Calculate estimated distances from RSSI values
    final Map<String, double> distances = {};
    for (final beacon in usableBeacons) {
      final rssi = rssiValues[beacon.id]!;
      final distance = _calculateDistanceFromRSSI(rssi, beacon.baseRssi);
      distances[beacon.id] = distance;
    }
    
    // Apply multilateration algorithm
    // We're using a weighted average approach for simplicity
    double totalWeight = 0;
    double weightedX = 0;
    double weightedY = 0;
    
    for (final beacon in usableBeacons) {
      if (beacon.position != null) {
        final distance = distances[beacon.id]!;
        
        // Closer beacons get higher weights
        final weight = 1.0 / (distance * distance);
        totalWeight += weight;
        
        weightedX += beacon.position!.x * weight;
        weightedY += beacon.position!.y * weight;
      }
    }
    
    if (totalWeight > 0) {
      final x = weightedX / totalWeight;
      final y = weightedY / totalWeight;
      
      return Vector2D(x, y);
    }
    
    return null;
  }
  
  /// Convert RSSI to distance using the log-distance path loss model
  double _calculateDistanceFromRSSI(int rssi, int baseRssi) {
    // Path loss exponent (typically between 2.0 for free space and 4.0 for indoor)
    const pathLossExponent = 2.2;
    
    // Estimate distance using the path loss formula
    final distance = pow(10, (baseRssi - rssi) / (10 * pathLossExponent));
    
    // Convert to pixels based on our coordinate system (assuming 40px = 1m)
    return distance * 40;
  }
  
  /// Handle step events
  void _onStep(StepEvent event) {
    // Convert step length from meters to pixels (40px = 1m)
    final stepLengthPixels = event.stepLength * 40;
    
    // Apply correction factor to step length
    final correctedStepLength = stepLengthPixels * _driftCorrectionFactor;
    
    // Convert heading to radians
    final headingRadians = _currentHeading * pi / 180;
    
    // Calculate step vector
    final stepVector = Vector2D.fromPolar(
      correctedStepLength,
      headingRadians,
    );
    
    // Update IMU-based position estimate
    _imuOffset = _imuOffset + stepVector;
    _stepsSinceLastBleUpdate++;
    
    // After significant movement, gradually increase IMU confidence
    if (_stepsSinceLastBleUpdate > 3) {
      _imuConfidence = min(0.7, _imuConfidence + 0.05);
      _bleConfidence = 1.0 - _imuConfidence;
    }
    
    // Update debug info
    if (_debugMode) {
      _debugInfo['imuOffset'] = {'x': _imuOffset.x, 'y': _imuOffset.y};
      _debugInfo['stepsSinceLastBleUpdate'] = _stepsSinceLastBleUpdate;
      _debugInfo['confidence'] = {
        'ble': _bleConfidence,
        'imu': _imuConfidence,
      };
    }
  }
  
  /// Update the fused position using weighted average of BLE and IMU
  void _updateFusedPosition() {
    if (!_isRunning) return;
    
    // Calculate time since last BLE update
    final timeSinceLastBle = DateTime.now().difference(_lastBleUpdate).inMilliseconds;
    
    // If BLE update is too old, rely more on IMU
    if (timeSinceLastBle > 5000) { // More than 5 seconds
      _bleConfidence = max(0.2, _bleConfidence - 0.05);
      _imuConfidence = 1.0 - _bleConfidence;
    }
    
    // Calculate fused position using weighted average
    final fusedPosition = Vector2D(
      (_lastBlePosition.x * _bleConfidence) + ((_lastBlePosition.x + _imuOffset.x) * _imuConfidence),
      (_lastBlePosition.y * _bleConfidence) + ((_lastBlePosition.y + _imuOffset.y) * _imuConfidence),
    );
    
    // Update current position
    _currentPosition = fusedPosition;
    
    // Broadcast the position update
    _positionController.add(_currentPosition);
    
    // Update debug info
    if (_debugMode) {
      _debugInfo['fusedPosition'] = {
        'x': _currentPosition.x,
        'y': _currentPosition.y,
      };
    }
  }
  
  /// Get debug information about the positioning system
  Map<String, dynamic> getDebugInfo() {
    return Map<String, dynamic>.from(_debugInfo);
  }
  
  /// Set current position manually (for initialization/calibration)
  void setPosition(Vector2D position) {
    _currentPosition = position.copy();
    _lastBlePosition = position.copy();
    _imuOffset = const Vector2D(0, 0);
    _stepsSinceLastBleUpdate = 0;
    _positionController.add(_currentPosition);
    
    debugPrint('📍 Position manually set to: (${position.x}, ${position.y})');
  }
  
  /// Utility to manually override the current heading
  void setHeading(double headingDegrees) {
    _currentHeading = headingDegrees % 360;
    debugPrint('🧭 Heading manually set to: ${_currentHeading.toStringAsFixed(1)}°');
  }
}