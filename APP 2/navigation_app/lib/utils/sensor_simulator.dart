import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import './vector2d.dart';
import './step_detector.dart';
import '../models/beacon.dart';

/// A simulated compass event for testing
class SimulatedCompassEvent {
  final double? heading;
  SimulatedCompassEvent(this.heading);
}

/// A service that provides simulated sensor data for testing in emulators
class SensorSimulator {
  // Singleton instance
  static final SensorSimulator _instance = SensorSimulator._internal();
  factory SensorSimulator() => _instance;
  SensorSimulator._internal();

  // Configuration
  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;
  
  // Simulated values
  double _heading = 0.0;
  double _accelerationMagnitude = 0.0;
  Position _position = Position(x: 200, y: 200);
  final Vector2D _velocity = Vector2D(0, 0);
  
  // Controllers for streams
  final _compassController = StreamController<SimulatedCompassEvent>.broadcast();
  final _accelerometerController = StreamController<AccelerometerEvent>.broadcast();
  final _stepController = StreamController<StepEvent>.broadcast();
  
  // Timers for simulation
  Timer? _compassTimer;
  Timer? _accelerometerTimer;
  Timer? _stepTimer;
  Timer? _movementTimer;
  
  // Public streams
  Stream<SimulatedCompassEvent> get compassStream => _compassController.stream;
  Stream<AccelerometerEvent> get accelerometerStream => _accelerometerController.stream;
  Stream<StepEvent> get stepStream => _stepController.stream;
  
  // Public methods to start and stop the simulator
  void start() {
    setEnabled(true);
  }
  
  void stop() {
    setEnabled(false);
  }
  
  // Enable or disable the simulator
  void setEnabled(bool enabled) {
    if (_isEnabled == enabled) return;
    
    _isEnabled = enabled;
    if (_isEnabled) {
      _startSimulation();
    } else {
      _stopSimulation();
    }
    debugPrint('🤖 Sensor Simulator ${_isEnabled ? 'enabled' : 'disabled'}');
  }
  
  // Start all simulations
  void _startSimulation() {
    _startCompassSimulation();
    _startAccelerometerSimulation();
    _startMovementSimulation();
  }
  
  // Stop all simulations
  void _stopSimulation() {
    _compassTimer?.cancel();
    _accelerometerTimer?.cancel();
    _stepTimer?.cancel();
    _movementTimer?.cancel();
    
    _compassTimer = null;
    _accelerometerTimer = null;
    _stepTimer = null;
    _movementTimer = null;
  }
  
  // Start compass simulation - emit heading values
  void _startCompassSimulation() {
    _compassTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      // Small random drift
      if (Random().nextDouble() < 0.1) {
        _heading += (Random().nextDouble() - 0.5) * 5.0; 
      }
      _compassController.add(SimulatedCompassEvent(_heading));
    });
  }
  
  // Start accelerometer simulation - emit acceleration values
  void _startAccelerometerSimulation() {
    _accelerometerTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      // Base acceleration (gravity)
      const gravityZ = 9.8;
      
      // Add noise
      final noiseX = (Random().nextDouble() - 0.5) * 0.5;
      final noiseY = (Random().nextDouble() - 0.5) * 0.5;
      final noiseZ = (Random().nextDouble() - 0.5) * 0.5;
      
      // Add simulated step if moving
      final stepVector = Vector2D(cos(_heading * pi / 180), sin(_heading * pi / 180));
      final stepAcceleration = stepVector * _accelerationMagnitude;
      _accelerometerController.add(AccelerometerEvent(
        stepAcceleration.x + noiseX,
        stepAcceleration.y + noiseY,
        gravityZ + noiseZ
      ));
    });
  }
  
  // Start movement simulation - periodically simulate steps
  void _startMovementSimulation() {
    _movementTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      // Update position based on velocity
      _position = Position(
        x: _position.x + _velocity.x,
        y: _position.y + _velocity.y
      );
    });
  }
  
  // -- Public API for controlling simulation --
  
  // Set heading to a specific direction
  void setHeading(double degrees) {
    _heading = degrees % 360;
    debugPrint('🧭 Simulated heading: ${_heading.toStringAsFixed(1)}°');
    // Immediately emit the new heading
    _compassController.add(SimulatedCompassEvent(_heading));
  }
  
  // Rotate by specified degrees (positive = clockwise)
  void rotate(double degrees) {
    setHeading(_heading + degrees);
  }
  
  // Simulate a step in the current heading direction
  void simulateStep({double stepLength = 0.7}) {
    // Create a step acceleration pattern
    _accelerationMagnitude = 5.0;
    
    // Create and emit a step event
    final stepEvent = StepEvent(
      timestamp: DateTime.now(),
      stepLength: stepLength,
      confidence: 0.9,
      acceleration: _accelerationMagnitude,
    );
    
    _stepController.add(stepEvent);
    
    // Reset acceleration after a delay
    Future.delayed(const Duration(milliseconds: 300), () {
      _accelerationMagnitude = 0.0;
    });
    
    debugPrint('👣 Simulated step: ${stepLength}m in direction: ${_heading.toStringAsFixed(1)}°');
  }
  
  // Simulate multiple steps in the current heading
  void simulateWalk({int steps = 3, double stepLength = 0.7}) {
    // Start walking
    int stepCount = 0;
    _stepTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      simulateStep(stepLength: stepLength);
      stepCount++;
      
      if (stepCount >= steps) {
        timer.cancel();
      }
    });
  }
  
  // Get the current simulated position
  Position getPosition() => _position;
  
  // Set the simulated position
  void setPosition(Position position) {
    _position = position;
  }
  
  void dispose() {
    _stopSimulation();
    _compassController.close();
    _accelerometerController.close();
    _stepController.close();
  }
}