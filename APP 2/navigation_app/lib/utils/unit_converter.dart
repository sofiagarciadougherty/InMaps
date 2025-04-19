import 'dart:math';
import './vector2d.dart';

class UnitConverter {
  // Default conversion factor (meters to grid units)
  final double defaultMetersToGridFactor = 10.0;
  
  // Current conversion factor
  double _metersToGridFactor;
  // Pixels per grid cell for UI rendering
  double _pixelsPerGridCell = 50.0;
  
  UnitConverter({double? metersToGridFactor}) 
      : _metersToGridFactor = metersToGridFactor ?? 10.0;
  
  // Getters and setters
  double get metersToGridFactor => _metersToGridFactor;
  set metersToGridFactor(double value) => _metersToGridFactor = value;
  
  double get pixelsPerGridCell => _pixelsPerGridCell;
  
  // Configure the converter with new values
  void configure({double? pixelsPerGridCell, double? metersToGridFactor}) {
    if (pixelsPerGridCell != null) {
      _pixelsPerGridCell = pixelsPerGridCell;
    }
    if (metersToGridFactor != null) {
      _metersToGridFactor = metersToGridFactor;
    }
  }
  
  // Convert position from UI coordinates to backend grid coordinates
  Map<String, dynamic> positionToBackendGrid(Vector2D position) {
    // Convert UI coordinates to grid coordinates
    final gridX = position.x / _pixelsPerGridCell;
    final gridY = position.y / _pixelsPerGridCell;
    
    return {
      'x': gridX,
      'y': gridY
    };
  }
  
  // Convert position to grid coordinates
  List<int> positionToGridCoords(Vector2D position) {
    final gridX = (position.x / _pixelsPerGridCell).toInt();
    final gridY = (position.y / _pixelsPerGridCell).toInt();
    return [gridX, gridY];
  }
  
  // Convert pixels to meters
  double pixelsToMeters(double pixels) {
    return pixels / _pixelsPerGridCell / _metersToGridFactor;
  }
  
  // Convert meters to grid units
  double metersToGridUnits(double meters) {
    return meters * _metersToGridFactor;
  }
  
  // Convert grid units to meters
  double gridUnitsToMeters(double gridUnits) {
    return gridUnits / _metersToGridFactor;
  }
  
  // Converts meters to grid units (double)
  double metersToGrid(double meters) {
    return meters * _metersToGridFactor;
  }

  // Converts grid units to pixels (double)
  double gridToPixels(double gridUnits) {
    return gridUnits * _pixelsPerGridCell;
  }

  // Converts pixels to grid units (double)
  double pixelsToGrid(double pixels) {
    return pixels / _pixelsPerGridCell;
  }
  
  // Convert RSSI to approximate distance in meters
  // Using the log-distance path loss model: RSSI = -10 * n * log10(d) + A
  // Where:
  // - n is the path loss exponent (typically 2-4)
  // - d is the distance in meters
  // - A is the RSSI at 1 meter distance (typically around -70 dBm)
  double rssiToMeters(int rssi, {double n = 2.0, double a = -70.0}) {
    return pow(10, (a - rssi) / (10 * n)) as double;
  }
  
  // Convert distance to grid coordinates
  double distanceToGridUnits(double distanceInMeters) {
    return distanceInMeters * _metersToGridFactor;
  }
  
  // Format position for display in the UI
  String formatPositionForDisplay(Vector2D position) {
    return "(${position.x.toStringAsFixed(1)}, ${position.y.toStringAsFixed(1)})";
  }
  
  // Update the conversion factor based on calibration
  void updateCalibrationFactor(double newFactor) {
    _metersToGridFactor = newFactor;
  }
}