import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/beacon.dart';
import './positioning.dart';
import './smoothed_position.dart';
import './vector2d.dart';
import './unit_converter.dart';
import './step_detector.dart';

/// A fused positioning system that combines BLE multilateration with IMU step detection
/// for more responsive and accurate indoor positioning.
class FusedPositionTracker {
  // Configuration
  final double _bleWeight;
  final double _imuWeight;
  final double _driftThreshold;
  final int _intervalMs;

  // State
  Vector2D _currentPosition = Vector2D(0, 0);
  Vector2D _lastBlePosition = Vector2D(0, 0);
  Vector2D _imuOffset = Vector2D(0, 0);
  double _driftCorrectionFactor = 1.0;
  double _headingRadians = 0.0;
  bool _hasInitialPosition = false;
  DateTime _lastBleUpdate = DateTime.now();
  int _stepsSinceLastBleUpdate = 0;
  
  // Source trackers
  final SmoothedPositionTracker _bleTracker;
  final StepDetector _stepDetector;
  StreamSubscription<CompassEvent>? _compassSub;
  
  // Converter
  final UnitConverter _converter = UnitConverter();
  
  // Position broadcast
  final _positionController = StreamController<Vector2D>.broadcast();
  Stream<Vector2D> get positionStream => _positionController.stream;
  Vector2D get position => _currentPosition;
  
  // Tracking state
  bool _isRunning = false;
  Timer? _updateTimer;
  
  // Positioning confidence values
  double _bleConfidence = 0.7; // Start with medium-high confidence in BLE
  double _imuConfidence = 0.3; // Start with lower confidence in IMU
  
  // Debug info
  bool _wasBleCorrected = false;
  double _lastDrift = 0.0;
  
  FusedPositionTracker({
    required SmoothedPositionTracker bleTracker,
    double bleWeight = 0.7,
    double imuWeight = 0.3,
    double driftThreshold = 50.0, // pixels
    int intervalMs = 100, // More frequent position updates
  }) : _bleTracker = bleTracker,
       _bleWeight = bleWeight,
       _imuWeight = imuWeight,
       _driftThreshold = driftThreshold,
       _intervalMs = intervalMs,
       _stepDetector = StepDetector();
  
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    
    // Start listening to BLE position updates
    _bleTracker.start();
    _bleTracker.positionStream.listen(_onBlePositionUpdate);
    
    // Start detecting steps
    _stepDetector.start();
    _stepDetector.stepStream.listen(_onStepDetected);
    
    // Start listening to compass updates
    _compassSub = FlutterCompass.events?.listen(_onCompassUpdate);
    
    // Start periodic position updates
    _updateTimer = Timer.periodic(Duration(milliseconds: _intervalMs), (_) {
      _updateFusedPosition();
    });
    
    debugPrint('🔄 FusedPositionTracker started');
  }
  
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    
    _bleTracker.stop();
    _stepDetector.stop();
    _compassSub?.cancel();
    _updateTimer?.cancel();
    
    debugPrint('⏹️ FusedPositionTracker stopped');
  }
  
  void dispose() {
    stop();
    _positionController.close();
    _bleTracker.dispose();
    _stepDetector.dispose();
    _compassSub?.cancel();
  }
  
  // Update the beacons for BLE positioning
  void updateBeacons(List<Beacon> beacons) {
    _bleTracker.updateBeacons(beacons);
  }
  
  // Update the calibration for BLE positioning
  void updateCalibration(double metersToGridFactor) {
    _bleTracker.updateCalibration(metersToGridFactor);
  }
  
  // Handle BLE position updates
  void _onBlePositionUpdate(Vector2D blePosition) {
    // If this is our first BLE position, initialize everything
    if (!_hasInitialPosition) {
      _currentPosition = blePosition;
      _lastBlePosition = blePosition;
      _hasInitialPosition = true;
      _positionController.add(_currentPosition);
      debugPrint('🔵 Initial BLE position: $blePosition');
      return;
    }
    
    // Calculate time since last BLE update
    final now = DateTime.now();
    final timeSinceLastUpdate = now.difference(_lastBleUpdate).inMilliseconds;
    
    // Calculate drift between predicted position and BLE position
    final predictedPosition = Vector2D(
      _lastBlePosition.x + _imuOffset.x,
      _lastBlePosition.y + _imuOffset.y
    );
    
    final drift = Vector2D.distance(predictedPosition, blePosition);
    _lastDrift = drift;
    _wasBleCorrected = drift > _driftThreshold;
    
    // If drift is significant, adjust correction factor
    if (_wasBleCorrected && _stepsSinceLastBleUpdate > 0) {
      _adjustDriftCorrection(blePosition);
      debugPrint('📏 Drift correction applied. Drift: ${drift.toStringAsFixed(2)}px, Steps: $_stepsSinceLastBleUpdate, New factor: ${_driftCorrectionFactor.toStringAsFixed(3)}');
    }
    
    // Update step count tracking
    _stepsSinceLastBleUpdate = 0;
    
    // Update last BLE position and timestamp
    _lastBlePosition = blePosition;
    _lastBleUpdate = now;
    
    // If we haven't moved much with IMU, reset the IMU offset
    if (drift < _driftThreshold / 2) {
      _imuOffset = Vector2D(0, 0);
    }
    
    // If we've been stationary for a while, trust BLE more
    if (timeSinceLastUpdate > 2000) {
      _bleConfidence = min(0.9, _bleConfidence + 0.1);
      _imuConfidence = max(0.1, _imuConfidence - 0.1);
    }
    
    _updateFusedPosition();
  }
  
  // Handle step detection events
  void _onStepDetected(StepEvent event) {
    if (!_hasInitialPosition) return;
    
    final stepDistanceInMeters = event.stepLength; // Use detected step length
    final stepDistanceInPixels = _converter.metersToPixels(stepDistanceInMeters);
    
    // Apply drift correction factor
    final correctedStepDistance = stepDistanceInPixels * _driftCorrectionFactor;
    
    // Calculate step vector based on compass heading
    final stepVector = Vector2D(
      cos(_headingRadians) * correctedStepDistance,
      sin(_headingRadians) * correctedStepDistance
    );
    
    // Update IMU offset
    _imuOffset = Vector2D(
      _imuOffset.x + stepVector.x,
      _imuOffset.y + stepVector.y
    );
    
    // Count steps since last BLE update
    _stepsSinceLastBleUpdate++;
    
    // If we're moving, trust IMU more
    _bleConfidence = max(0.3, _bleConfidence - 0.05);
    _imuConfidence = min(0.7, _imuConfidence + 0.05);
    
    _updateFusedPosition();
    
    debugPrint('👣 Step detected. Distance: ${stepDistanceInMeters.toStringAsFixed(2)}m, Heading: ${(_headingRadians * 180 / pi).toStringAsFixed(0)}°');
  }
  
  // Handle compass updates
  void _onCompassUpdate(CompassEvent event) {
    if (event.heading != null) {
      _headingRadians = event.heading! * pi / 180;
    }
  }
  
  // Update the fused position by combining BLE and IMU data
  void _updateFusedPosition() {
    if (!_hasInitialPosition) return;
    
    // Calculate IMU-based position
    final imuPosition = Vector2D(
      _lastBlePosition.x + _imuOffset.x,
      _lastBlePosition.y + _imuOffset.y
    );
    
    // Apply weighted average based on current confidence values
    final weight = _wasBleCorrected ? 0.9 : _bleConfidence / (_bleConfidence + _imuConfidence);
    
    final fusedPosition = Vector2D(
      _lastBlePosition.x * weight + imuPosition.x * (1 - weight),
      _lastBlePosition.y * weight + imuPosition.y * (1 - weight)
    );
    
    // Update current position
    _currentPosition = fusedPosition;
    
    // Broadcast the new position
    _positionController.add(_currentPosition);
  }
  
  // Adjust drift correction factor based on observed drift
  void _adjustDriftCorrection(Vector2D blePosition) {
    if (_stepsSinceLastBleUpdate == 0) return;
    
    final predictedPosition = Vector2D(
      _lastBlePosition.x + _imuOffset.x,
      _lastBlePosition.y + _imuOffset.y
    );
    
    final dx = blePosition.x - predictedPosition.x;
    final dy = blePosition.y - predictedPosition.y;
    
    // Calculate correction per step
    final correctionX = dx / _stepsSinceLastBleUpdate;
    final correctionY = dy / _stepsSinceLastBleUpdate;
    
    // Calculate magnitude of correction
    final correctionMagnitude = sqrt(correctionX * correctionX + correctionY * correctionY);
    
    // Calculate new correction factor (adaptive learning rate)
    final learningRate = 0.2;
    final correctionFactor = 1.0 - (correctionMagnitude / (_converter.metersToPixels(0.7) * _stepsSinceLastBleUpdate)) * learningRate;
    
    // Apply correction with bounds
    _driftCorrectionFactor = _driftCorrectionFactor * correctionFactor;
    _driftCorrectionFactor = _driftCorrectionFactor.clamp(0.5, 1.5);
  }
  
  // Get debug information about the tracker state
  Map<String, dynamic> getDebugInfo() {
    return {
      'position': {
        'x': _currentPosition.x,
        'y': _currentPosition.y,
      },
      'blePosition': {
        'x': _lastBlePosition.x,
        'y': _lastBlePosition.y,
      },
      'imuOffset': {
        'x': _imuOffset.x,
        'y': _imuOffset.y,
      },
      'heading': _headingRadians * 180 / pi,
      'driftCorrectionFactor': _driftCorrectionFactor,
      'stepsSinceLastBleUpdate': _stepsSinceLastBleUpdate,
      'lastDrift': _lastDrift,
      'confidence': {
        'ble': _bleConfidence,
        'imu': _imuConfidence,
      },
    };
  }
}