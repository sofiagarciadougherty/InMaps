import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Event representing a detected step with its characteristics
class StepEvent {
  final DateTime timestamp;
  final double stepLength; // in meters
  final double confidence; // 0.0 to 1.0
  final double acceleration; // magnitude of acceleration

  StepEvent({
    required this.timestamp,
    required this.stepLength,
    required this.confidence,
    required this.acceleration,
  });

  @override
  String toString() => 'StepEvent(time: $timestamp, length: ${stepLength.toStringAsFixed(2)}m, confidence: ${(confidence * 100).toStringAsFixed(0)}%)';
}

/// Detector for user steps using accelerometer data with advanced filtering
class StepDetector {
  // Configuration
  final double _accelerationThreshold;
  final double _minStepInterval;
  final double _maxStepInterval;
  final int _windowSize;
  
  // State
  final List<double> _accelerationWindow = [];
  final List<DateTime> _stepTimestamps = [];
  double _currentVariance = 0.0;
  double _baselineAcceleration = 9.8; // Earth's gravity
  bool _isRunning = false;
  
  // Step statistics for adaptivity
  double _averageStepFrequency = 1.8; // steps per second
  double _averageStepLength = 0.7; // meters
  
  // Stream controller for step events
  final _stepController = StreamController<StepEvent>.broadcast();
  Stream<StepEvent> get stepStream => _stepController.stream;
  
  // Subscription to accelerometer
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  
  // Step pattern recognition
  bool _isPotentialStep = false;
  double _lastPeakAcceleration = 0;
  double _lastTroughAcceleration = 0;
  DateTime _lastStepTime = DateTime.now();
  
  StepDetector({
    double accelerationThreshold = 1.8,
    double minStepIntervalMs = 250.0, // minimum 250ms between steps (max 4 steps/second)
    double maxStepIntervalMs = 2000.0, // maximum 2s between steps
    int windowSize = 10,
  }) : _accelerationThreshold = accelerationThreshold,
       _minStepInterval = minStepIntervalMs,
       _maxStepInterval = maxStepIntervalMs,
       _windowSize = windowSize;
  
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    
    // Subscribe to accelerometer events
    _accelerometerSubscription = accelerometerEvents.listen(_processAccelerometerEvent);
    debugPrint('👟 StepDetector started');
  }
  
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    debugPrint('⏹️ StepDetector stopped');
  }
  
  void dispose() {
    stop();
    _stepController.close();
  }
  
  /// Process incoming accelerometer data for step detection
  void _processAccelerometerEvent(AccelerometerEvent event) {
    // Calculate acceleration magnitude (removing gravity)
    final acceleration = _calculateAccelerationMagnitude(event);
    
    // Add to window
    _updateAccelerationWindow(acceleration);
    
    // Check for steps with peak detection
    _detectStepWithPeakTrough(acceleration);
  }
  
  /// Calculate the magnitude of acceleration after removing gravity
  double _calculateAccelerationMagnitude(AccelerometerEvent event) {
    // Calculate total acceleration magnitude
    final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    
    // Adaptive baseline (gravity) estimation using exponential smoothing
    _baselineAcceleration = _baselineAcceleration * 0.98 + magnitude * 0.02;
    
    // Return the deviation from baseline
    return magnitude - _baselineAcceleration;
  }
  
  /// Update window of acceleration values and calculate variance
  void _updateAccelerationWindow(double acceleration) {
    _accelerationWindow.add(acceleration);
    
    if (_accelerationWindow.length > _windowSize) {
      _accelerationWindow.removeAt(0);
    }
    
    if (_accelerationWindow.length >= 4) {
      _currentVariance = _calculateVariance(_accelerationWindow);
    }
  }
  
  /// Calculate variance of a list of values
  double _calculateVariance(List<double> values) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    final squares = values.map((x) => (x - mean) * (x - mean));
    return squares.reduce((a, b) => a + b) / values.length;
  }
  
  /// Detect steps using peak and trough pattern recognition
  void _detectStepWithPeakTrough(double acceleration) {
    final now = DateTime.now();
    final timeSinceLastStep = now.difference(_lastStepTime).inMilliseconds;
    
    // Initialize pattern recognition
    if (_accelerationWindow.length < 5) return;
    
    // Detect peaks and troughs for step pattern
    if (!_isPotentialStep && acceleration > _accelerationThreshold &&
        _accelerationWindow[_accelerationWindow.length - 2] < acceleration) {
      // Found a peak, start potential step
      _isPotentialStep = true;
      _lastPeakAcceleration = acceleration;
      return;
    }
    
    // After finding a peak, look for corresponding trough
    if (_isPotentialStep && 
        acceleration < -_accelerationThreshold / 2 &&
        _accelerationWindow[_accelerationWindow.length - 2] > acceleration) {
      _lastTroughAcceleration = acceleration;
      
      // Check if this is a step pattern
      final peakToDiff = _lastPeakAcceleration - _lastTroughAcceleration;
      
      if (peakToDiff > _accelerationThreshold * 1.5 && 
          timeSinceLastStep > _minStepInterval) {
        
        // Validate step with timing
        bool validStep = true;
        
        // Invalidate too frequent steps
        if (timeSinceLastStep < _minStepInterval) {
          validStep = false;
        }
        
        // Invalidate too infrequent steps, but only if we already have some steps
        if (_stepTimestamps.isNotEmpty && timeSinceLastStep > _maxStepInterval) {
          validStep = false;
        }
        
        if (validStep) {
          _onStepDetected(peakToDiff);
        }
      }
      
      // Reset state
      _isPotentialStep = false;
    }
  }
  
  /// Handle a detected step
  void _onStepDetected(double stepStrength) {
    final now = DateTime.now();
    _lastStepTime = now;
    _stepTimestamps.add(now);
    
    // Keep only recent steps for frequency calculation
    final maxStepHistory = 5;
    while (_stepTimestamps.length > maxStepHistory) {
      _stepTimestamps.removeAt(0);
    }
    
    // Calculate step frequency if enough history
    if (_stepTimestamps.length > 1) {
      final oldestTimestamp = _stepTimestamps.first;
      final durationSeconds = now.difference(oldestTimestamp).inMilliseconds / 1000;
      if (durationSeconds > 0) {
        final frequency = (_stepTimestamps.length - 1) / durationSeconds;
        // Smooth update to average frequency
        _averageStepFrequency = _averageStepFrequency * 0.7 + frequency * 0.3;
      }
    }
    
    // Adjust step length based on frequency (faster walking = longer steps)
    final baseStepLength = 0.7; // Base step length in meters
    final frequencyFactor = _averageStepFrequency / 1.8; // Normalized to typical walking frequency
    final stepLength = baseStepLength * sqrt(frequencyFactor).clamp(0.7, 1.3);
    
    // Calculate confidence based on step strength and variance
    final confidenceFactor = min(1.0, stepStrength / (_accelerationThreshold * 2));
    final varianceFactor = min(1.0, _currentVariance / 5.0); 
    final confidence = (confidenceFactor * 0.7 + varianceFactor * 0.3).clamp(0.0, 1.0);
    
    // Create step event
    final stepEvent = StepEvent(
      timestamp: now,
      stepLength: stepLength,
      confidence: confidence,
      acceleration: stepStrength,
    );
    
    // Update step length for adaptivity
    _averageStepLength = _averageStepLength * 0.8 + stepLength * 0.2;
    
    // Broadcast step event
    _stepController.add(stepEvent);
    
    debugPrint('👣 Step detected! Strength: ${stepStrength.toStringAsFixed(1)}, '
               'Frequency: ${_averageStepFrequency.toStringAsFixed(1)} steps/s, '
               'Length: ${stepLength.toStringAsFixed(2)}m');
  }
}