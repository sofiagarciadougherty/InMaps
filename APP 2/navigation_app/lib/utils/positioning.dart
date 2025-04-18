import 'dart:math';
import '../models/beacon.dart';

// Convert RSSI to estimated distance in meters
double rssiToDistance(int rssi, int txPower = -59, double pathLossExponent = 2.0) {
  return pow(10, (txPower - rssi) / (10 * pathLossExponent)).toDouble();
}

// Calculate quality factor based on beacon staleness
double calculateStalenessFactor(Beacon beacon, int staleThresholdMs) {
  final ageMs = beacon.getAgeMs();
  
  // Fresh beacons get full weight (1.0)
  if (ageMs < staleThresholdMs * 0.25) {
    return 1.0;
  }
  
  // Linear degradation between 0.25x and 1.0x threshold
  if (ageMs < staleThresholdMs) {
    return 1.0 - (ageMs - staleThresholdMs * 0.25) / (staleThresholdMs * 0.75);
  }
  
  // Beyond threshold, weight decays exponentially
  return max(0.1, exp(-(ageMs - staleThresholdMs) / staleThresholdMs));
}

// Calculate quality factor based on distance
double calculateDistanceFactor(double distanceMeters, double maxRangeMeters) {
  // Closer beacons get higher weight
  if (distanceMeters < maxRangeMeters * 0.3) {
    return 1.0; // Full weight for close beacons
  }
  
  // Linear degradation between 0.3x and 1.0x max range
  if (distanceMeters < maxRangeMeters) {
    return 1.0 - (distanceMeters - maxRangeMeters * 0.3) / (maxRangeMeters * 0.7);
  }
  
  // Beyond max range, weight decays based on square of distance
  return max(0.1, maxRangeMeters / (distanceMeters * 1.5));
}

// Find intersections between two circle signals
List<Map<String, double>> getCircleIntersections(
    double x1, double y1, double r1, double x2, double y2, double r2) {
  // Calculate distance between circle centers
  final d = sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2));
  
  // Check if circles are too far apart or one inside another
  if (d > r1 + r2 || d < (r1 - r2).abs()) {
    // No proper intersections, return midpoint of the closest points
    final closestX1 = x1 + (r1 * (x2 - x1)) / d;
    final closestY1 = y1 + (r1 * (y2 - y1)) / d;
    final closestX2 = x2 - (r2 * (x2 - x1)) / d;
    final closestY2 = y2 - (r2 * (y2 - y1)) / d;
    return [{'x': (closestX1 + closestX2) / 2, 'y': (closestY1 + closestY2) / 2}];
  }
  
  // Calculate intersection points
  final a = (r1 * r1 - r2 * r2 + d * d) / (2 * d);
  final h = sqrt(r1 * r1 - a * a);
  final xm = x1 + (a * (x2 - x1)) / d;
  final ym = y1 + (a * (y2 - y1)) / d;
  
  return [
    {'x': xm + (h * (y2 - y1)) / d, 'y': ym - (h * (x2 - x1)) / d},
    {'x': xm - (h * (y2 - y1)) / d, 'y': ym + (h * (x2 - x1)) / d},
  ];
}

// Find position using beacon signal intersections
Map<String, double>? trilaterateByIntersections(
    List<Beacon> beacons, double metersToGridFactor, {
    int staleThresholdMs = 10000,
    double maxRangeMeters = 15.0,
}) {
  if (beacons.length < 2) return null;
  
  final intersections = <Map<String, double>>[];
  final weights = <double>[];
  
  for (int i = 0; i < beacons.length; i++) {
    for (int j = i + 1; j < beacons.length; j++) {
      final b1 = beacons[i];
      final b2 = beacons[j];
      
      // Skip if either beacon doesn't have valid data
      if (b1.rssi == null || b2.rssi == null || 
          b1.position == null || b2.position == null) {
        continue;
      }
      
      // Calculate distance in grid units
      final r1 = rssiToDistance(b1.rssi!, b1.baseRssi) * metersToGridFactor;
      final r2 = rssiToDistance(b2.rssi!, b2.baseRssi) * metersToGridFactor;

      // Calculate quality factors
      final stalenessFactor1 = calculateStalenessFactor(b1, staleThresholdMs);
      final stalenessFactor2 = calculateStalenessFactor(b2, staleThresholdMs);
      final distanceFactor1 = calculateDistanceFactor(rssiToDistance(b1.rssi!, b1.baseRssi), maxRangeMeters);
      final distanceFactor2 = calculateDistanceFactor(rssiToDistance(b2.rssi!, b2.baseRssi), maxRangeMeters);
      
      // The combined quality of this intersection
      final pairQuality = (stalenessFactor1 * stalenessFactor2 * distanceFactor1 * distanceFactor2);
      
      try {
        // Find intersection between the two beacon circles
        final newIntersections = getCircleIntersections(
          b1.position!.x, b1.position!.y, r1,
          b2.position!.x, b2.position!.y, r2
        );
        
        // Add each intersection with its weight
        for (final intersection in newIntersections) {
          intersections.add(intersection);
          weights.add(pairQuality);
        }
      } catch (e) {
        print('Error calculating intersections: $e');
        continue;
      }
    }
  }
  
  if (intersections.isEmpty) return null;
  
  // Compute weighted average position
  double totalWeight = weights.fold(0, (sum, weight) => sum + weight);
  double weightedSumX = 0;
  double weightedSumY = 0;
  
  for (int i = 0; i < intersections.length; i++) {
    weightedSumX += intersections[i]['x']! * weights[i];
    weightedSumY += intersections[i]['y']! * weights[i];
  }
  
  return {
    'x': weightedSumX / totalWeight,
    'y': weightedSumY / totalWeight
  };
}

// Calculate position using both trilateration and weighted averaging
Map<String, double> multilaterate(
    List<Beacon> beacons, double metersToGridFactor, {
    int staleThresholdMs = 10000,
    double maxRangeMeters = 15.0,
}) {
  if (beacons.isEmpty) return {'x': 0, 'y': 0};

  // For just one beacon, return its position
  if (beacons.length == 1 && beacons[0].position != null) {
    return {
      'x': beacons[0].position!.x, 
      'y': beacons[0].position!.y
    };
  }
  
  // For two beacons, find the closest one
  if (beacons.length == 2) {
    Beacon best = beacons[0];
    double bestDist = rssiToDistance(best.rssi ?? best.baseRssi, best.baseRssi);
    
    final otherDist = rssiToDistance(beacons[1].rssi ?? beacons[1].baseRssi, beacons[1].baseRssi);
    if (otherDist < bestDist) {
      best = beacons[1];
      bestDist = otherDist;
    }
    
    if (best.position != null) {
      return {'x': best.position!.x, 'y': best.position!.y};
    }
  }

  // Try trilateration first
  if (beacons.length >= 3) {
    final trilaterated = trilaterateByIntersections(
      beacons, 
      metersToGridFactor,
      staleThresholdMs: staleThresholdMs,
      maxRangeMeters: maxRangeMeters
    );
    
    if (trilaterated != null) {
      return trilaterated;
    }
  }

  // Fall back to weighted average
  double totalWeight = 0;
  double weightedSumX = 0;
  double weightedSumY = 0;

  for (final beacon in beacons) {
    if (beacon.position == null || beacon.rssi == null) continue;
    
    // Calculate staleness and distance quality factors
    final stalenessFactor = calculateStalenessFactor(beacon, staleThresholdMs);
    final distance = rssiToDistance(beacon.rssi!, beacon.baseRssi);
    final distanceFactor = calculateDistanceFactor(distance, maxRangeMeters);
    
    // Combined quality factor for this beacon
    final qualityFactor = stalenessFactor * distanceFactor;
    
    // Inverse squared distance for weight calculation
    final distanceWeight = 1 / max(0.1, distance * distance);
    
    // Final weight is quality factor multiplied by inverse squared distance
    final weight = qualityFactor * distanceWeight;
    
    weightedSumX += beacon.position!.x * weight;
    weightedSumY += beacon.position!.y * weight;
    totalWeight += weight;
  }

  if (totalWeight > 0) {
    return {
      'x': weightedSumX / totalWeight,
      'y': weightedSumY / totalWeight
    };
  }

  // Final fallback
  return {'x': 0, 'y': 0};
}