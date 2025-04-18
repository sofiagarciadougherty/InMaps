import 'dart:math';
import '../models/beacon.dart';
import './vector2d.dart';

/// Converts RSSI value to physical distance in meters
double rssiToDistance(int rssi, int txPower, {double pathLossExponent = 2.0}) {
  return pow(10, (txPower - rssi) / (10 * pathLossExponent)).toDouble();
}

/// Calculates the intersection points between two circles
List<Map<String, double>> getCircleIntersections(
  double x1, double y1, double r1, 
  double x2, double y2, double r2
) {
  final d = sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2));
  
  // If circles don't intersect or one is inside the other
  if (d > r1 + r2 || d < (r1 - r2).abs()) {
    final closestX1 = x1 + (r1 * (x2 - x1)) / d;
    final closestY1 = y1 + (r1 * (y2 - y1)) / d;
    final closestX2 = x2 - (r2 * (x2 - x1)) / d;
    final closestY2 = y2 - (r2 * (y2 - y1)) / d;
    
    // Return midpoint of closest points on each circle
    return [{'x': (closestX1 + closestX2) / 2, 'y': (closestY1 + closestY2) / 2}];
  }

  // Calculate intersection points
  final a = (pow(r1, 2) - pow(r2, 2) + pow(d, 2)) / (2 * d);
  final h = sqrt(pow(r1, 2) - pow(a, 2));
  final xm = x1 + (a * (x2 - x1)) / d;
  final ym = y1 + (a * (y2 - y1)) / d;

  return [
    {
      'x': xm + (h * (y2 - y1)) / d,
      'y': ym - (h * (x2 - x1)) / d
    },
    {
      'x': xm - (h * (y2 - y1)) / d,
      'y': ym + (h * (x2 - x1)) / d
    },
  ];
}

/// Trilaterates position using circle intersections
Map<String, double>? trilaterateByIntersections(List<Beacon> beacons, double metersToGridFactor) {
  final List<Map<String, double>> intersections = [];

  for (int i = 0; i < beacons.length; i++) {
    for (int j = i + 1; j < beacons.length; j++) {
      final b1 = beacons[i];
      final b2 = beacons[j];
      
      // Skip if either beacon doesn't have a valid position
      if (b1.position == null || b2.position == null) continue;
      
      final r1 = rssiToDistance(b1.rssi ?? b1.baseRssi, b1.baseRssi) * metersToGridFactor;
      final r2 = rssiToDistance(b2.rssi ?? b2.baseRssi, b2.baseRssi) * metersToGridFactor;

      try {
        final newIntersections = getCircleIntersections(
          b1.position!.x, b1.position!.y, r1,
          b2.position!.x, b2.position!.y, r2
        );
        
        intersections.addAll(newIntersections);
      } catch (error) {
        print('Error calculating intersections: $error');
        continue;
      }
    }
  }

  if (intersections.isEmpty) return null;

  // Compute the average position of intersections
  final avgX = intersections.fold(0.0, (sum, p) => sum + p['x']!) / intersections.length;
  final avgY = intersections.fold(0.0, (sum, p) => sum + p['y']!) / intersections.length;
  return {'x': avgX, 'y': avgY};
}

/// Main positioning function that handles various scenarios of beacon availability
Map<String, double> multilaterate(List<Beacon> beacons, double metersToGridFactor) {
  if (beacons.isEmpty) return {'x': 0.0, 'y': 0.0};

  if (beacons.length < 3) {
    var best = beacons[0];
    var bestDist = rssiToDistance(best.rssi ?? best.baseRssi, best.baseRssi);
    
    for (final b in beacons) {
      final d = rssiToDistance(b.rssi ?? b.baseRssi, b.baseRssi);
      if (d < bestDist) {
        best = b;
        bestDist = d;
      }
    }
    
    // Return position of nearest beacon or default
    return best.position != null 
        ? {'x': best.position!.x, 'y': best.position!.y} 
        : {'x': 0.0, 'y': 0.0};
  }

  if (beacons.length >= 3) {
    final trilaterated = trilaterateByIntersections(beacons, metersToGridFactor);
    if (trilaterated != null) return trilaterated;
  }

  // Weighted average as fallback
  double totalWeight = 0;
  double weightedSumX = 0;
  double weightedSumY = 0;

  for (final b in beacons) {
    if (b.position == null) continue;
    
    final dist = rssiToDistance(b.rssi ?? b.baseRssi, b.baseRssi);
    // Inverse square weighting - closer beacons have higher weight
    final weight = 1 / max(0.1, dist * dist);

    weightedSumX += b.position!.x * weight;
    weightedSumY += b.position!.y * weight;
    totalWeight += weight;
  }

  if (totalWeight > 0) {
    return {
      'x': weightedSumX / totalWeight,
      'y': weightedSumY / totalWeight
    };
  }

  // Final fallback
  return {'x': 0.0, 'y': 0.0};
}