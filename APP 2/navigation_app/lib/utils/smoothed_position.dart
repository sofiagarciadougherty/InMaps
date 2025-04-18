import 'dart:async';
import 'dart:math';
import '../models/beacon.dart';
import './positioning.dart';

class Position {
  final double x;
  final double y;

  const Position({required this.x, required this.y});
  
  double distanceTo(Position other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return sqrt(dx * dx + dy * dy);
  }
}

class SmoothedPositionTracker {
  // Configuration
  final double baselineAlpha; // Base smoothing factor (0.0-1.0)
  final int intervalMs;       // Update interval in milliseconds
  final int staleThresholdMs; // Time threshold for stale beacons in milliseconds
  final double maxRangeMeters; // Maximum effective range of beacons
  final bool useAdaptiveThresholds; // Whether to adapt smoothing based on quality metrics
  
  // State 
  List<Beacon> _beacons = [];
  double _metersToGridFactor = 1.0;
  Position _currentPosition = Position(x: 0.0, y: 0.0);
  double _confidence = 1.0; // Overall confidence in position (0.0-1.0)
  
  // Timers and controllers
  Timer? _timer;
  final _positionController = StreamController<Position>.broadcast();
  Stream<Position> get positionStream => _positionController.stream;
  
  // Statistics for adaptive thresholds
  int _consecutiveGoodUpdates = 0;
  int _consecutivePoorUpdates = 0;
  double _currentAlpha;
  double _currentJumpThreshold = 3.0; // Initial jump threshold in grid units
  
  SmoothedPositionTracker({
    this.baselineAlpha = 0.85,
    this.intervalMs = 500,
    this.staleThresholdMs = 10000,
    this.maxRangeMeters = 15.0,
    this.useAdaptiveThresholds = true,
  }) : _currentAlpha = baselineAlpha {
    // Initialize with default values
  }
  
  // Get the current confidence level
  double get confidence => _confidence;
  
  // Get the current position
  Position get position => _currentPosition;
  
  // Start position tracking updates
  void start() {
    if (_timer != null) {
      _timer!.cancel();
    }
    
    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _updatePosition();
    });
  }
  
  // Stop position tracking updates
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
  
  // Update the list of beacons
  void updateBeacons(List<Beacon> beacons) {
    _beacons = beacons;
  }
  
  // Update the calibration factor
  void updateCalibration(double metersToGridFactor) {
    _metersToGridFactor = metersToGridFactor;
  }
  
  // Calculate overall beacon quality based on active beacons, staleness, and distance
  Map<String, dynamic> _calculateBeaconQuality() {
    if (_beacons.isEmpty) {
      return {
        'qualityScore': 0.0,
        'activeCount': 0,
        'freshCount': 0,
        'closeCount': 0
      };
    }
    
    int activeCount = 0;
    int freshCount = 0;
    int closeCount = 0;
    double totalQuality = 0.0;
    
    for (final beacon in _beacons) {
      if (beacon.isActive && beacon.position != null && beacon.rssi != null) {
        activeCount++;
        
        final stalenessFactor = calculateStalenessFactor(beacon, staleThresholdMs);
        final distance = rssiToDistance(beacon.rssi!, beacon.baseRssi);
        final distanceFactor = calculateDistanceFactor(distance, maxRangeMeters);
        
        // Count beacons that are fresh (not stale)
        if (stalenessFactor > 0.7) freshCount++;
        
        // Count beacons that are close
        if (distanceFactor > 0.7) closeCount++;
        
        // Sum up the quality scores
        totalQuality += stalenessFactor * distanceFactor;
      }
    }
    
    // Calculate final quality score (0.0-1.0)
    final qualityScore = activeCount > 0 
        ? min(1.0, totalQuality / activeCount)
        : 0.0;
        
    return {
      'qualityScore': qualityScore,
      'activeCount': activeCount,
      'freshCount': freshCount,
      'closeCount': closeCount
    };
  }
  
  // Dynamically adjust smoothing factor and thresholds based on quality
  void _adjustParameters(double qualityScore, int activeCount) {
    if (!useAdaptiveThresholds) return;
    
    // Adjust alpha (smoothing factor) based on quality score
    if (qualityScore > 0.8 && activeCount >= 3) {
      _currentAlpha = min(0.95, baselineAlpha + 0.1);
      _consecutiveGoodUpdates++;
      _consecutivePoorUpdates = 0;
      
      // If we have several consistent good updates, we can be more responsive
      if (_consecutiveGoodUpdates > 5) {
        _currentAlpha = min(0.98, baselineAlpha + 0.15);
      }
    } 
    else if (qualityScore < 0.4 || activeCount < 2) {
      _currentAlpha = max(0.6, baselineAlpha - 0.25);
      _consecutivePoorUpdates++;
      _consecutiveGoodUpdates = 0;
      
      // If position quality is consistently poor, smooth more aggressively
      if (_consecutivePoorUpdates > 3) {
        _currentAlpha = max(0.4, baselineAlpha - 0.4);
      }
    }
    else {
      // Default case - use baseline with small adjustments
      _currentAlpha = baselineAlpha;
      _consecutiveGoodUpdates = 0;
      _consecutivePoorUpdates = 0;
    }
    
    // Adjust jump threshold based on quality
    // Lower quality = higher threshold (harder to make big jumps)
    _currentJumpThreshold = qualityScore > 0.7 
        ? 4.0  // Allow bigger jumps when quality is good
        : 2.0; // Be more conservative when quality is poor
  }
  
  // Update the position based on beacon data
  void _updatePosition() {
    if (_beacons.isEmpty) {
      // No beacons available, reduce confidence
      _confidence = max(0.1, _confidence - 0.1);
      return;
    }
    
    // Get active beacons that have position and signal data
    final activeBeacons = _beacons.where((b) => 
      b.isActive && 
      b.position != null && 
      b.rssi != null
    ).toList();
    
    if (activeBeacons.isEmpty) {
      // No active beacons with valid data
      _confidence = max(0.1, _confidence - 0.1);
      return;
    }
    
    // Calculate overall beacon quality metrics
    final quality = _calculateBeaconQuality();
    final qualityScore = quality['qualityScore'] as double;
    final activeCount = quality['activeCount'] as int;
    
    // Update confidence based on quality and beacon count
    _confidence = _calculateConfidence(qualityScore, activeCount);
    
    // Adjust smoothing parameters based on quality
    _adjustParameters(qualityScore, activeCount);
    
    // Calculate new position
    final rawPosition = multilaterate(
      activeBeacons, 
      _metersToGridFactor,
      staleThresholdMs: staleThresholdMs,
      maxRangeMeters: maxRangeMeters
    );
    
    final newRawPos = Position(
      x: rawPosition['x']!.toDouble(), 
      y: rawPosition['y']!.toDouble()
    );
    
    // Check if this is a "jump" that should be rejected
    final distance = newRawPos.distanceTo(_currentPosition);
    if (distance > _currentJumpThreshold && _confidence < 0.7) {
      // If this is a big jump with low confidence, apply stronger smoothing
      final jumpAlpha = max(0.2, _currentAlpha - 0.3);
      
      _currentPosition = Position(
        x: _currentPosition.x * (1 - jumpAlpha) + newRawPos.x * jumpAlpha,
        y: _currentPosition.y * (1 - jumpAlpha) + newRawPos.y * jumpAlpha
      );
    } else {
      // Normal smoothing with current alpha
      _currentPosition = Position(
        x: _currentPosition.x * (1 - _currentAlpha) + newRawPos.x * _currentAlpha,
        y: _currentPosition.y * (1 - _currentAlpha) + newRawPos.y * _currentAlpha
      );
    }
    
    // Broadcast the updated position
    _positionController.add(_currentPosition);
  }
  
  // Calculate confidence based on beacon quality
  double _calculateConfidence(double qualityScore, int activeCount) {
    // Base confidence on quality score
    double newConfidence = qualityScore;
    
    // Adjust based on number of active beacons
    if (activeCount >= 3) {
      // Boost confidence with 3+ beacons
      newConfidence = min(1.0, newConfidence * 1.2);
    } else if (activeCount <= 1) {
      // Reduce confidence with only 0-1 beacons
      newConfidence = max(0.1, newConfidence * 0.7);
    }
    
    // Smooth the confidence itself to prevent rapid fluctuations
    return _confidence * 0.7 + newConfidence * 0.3;
  }
  
  // Clean up resources
  void dispose() {
    _timer?.cancel();
    _positionController.close();
  }
}