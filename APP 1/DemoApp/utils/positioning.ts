import { Beacon } from '../src/types';

export function rssiToDistance(rssi: number, txPower = -59, pathLossExponent = 2): number {
  return Math.pow(10, (txPower - rssi) / (10 * pathLossExponent));
}

export function getCircleIntersections(x1: number, y1: number, r1: number, x2: number, y2: number, r2: number) {
  const d = Math.hypot(x2 - x1, y1 - y2);
  if (d > r1 + r2 || d < Math.abs(r1 - r2)) {
    const closestX1 = x1 + (r1 * (x2 - x1)) / d;
    const closestY1 = y1 + (r1 * (y2 - y1)) / d;
    const closestX2 = x2 - (r2 * (x2 - x1)) / d;
    const closestY2 = y2 - (r2 * (y2 - y1)) / d;
    return [{ x: (closestX1 + closestX2) / 2, y: (closestY1 + closestY2) / 2 }];
  }

  const a = (r1 ** 2 - r2 ** 2 + d ** 2) / (2 * d);
  const h = Math.sqrt(r1 ** 2 - a ** 2);
  const xm = x1 + (a * (x2 - x1)) / d;
  const ym = y1 + (a * (y2 - y1)) / d;

  return [
    { x: xm + (h * (y2 - y1)) / d, y: ym - (h * (x2 - x1)) / d },
    { x: xm - (h * (y2 - y1)) / d, y: ym + (h * (x2 - x1)) / d },
  ];
}

export function trilaterateByIntersections(beacons: Beacon[], metersToGridFactor: number) {
  const intersections = [];

  for (let i = 0; i < beacons.length; i++) {
    for (let j = i + 1; j < beacons.length; j++) {
      const b1 = beacons[i];
      const b2 = beacons[j];
      
      // Skip if either beacon doesn't have a valid position object
      if (!b1?.position || !b2?.position) continue;
      
      // Skip if position doesn't have valid x,y numeric coordinates
      if (typeof b1.position.x !== 'number' || typeof b1.position.y !== 'number' || 
          typeof b2.position.x !== 'number' || typeof b2.position.y !== 'number') continue;
      
      const r1 = rssiToDistance(b1.rssi ?? b1.baseRssi, b1.baseRssi) * metersToGridFactor;
      const r2 = rssiToDistance(b2.rssi ?? b2.baseRssi, b2.baseRssi) * metersToGridFactor;

      try {
        // Catch any potential errors in the intersection calculation
        const newIntersections = getCircleIntersections(
          b1.position.x, b1.position.y, r1,
          b2.position.x, b2.position.y, r2
        );
        
        if (newIntersections && Array.isArray(newIntersections)) {
          intersections.push(...newIntersections);
        }
      } catch (error) {
        console.warn('Error calculating intersections:', error);
        // Continue with next beacon pair if there's an error
        continue;
      }
    }
  }

  if (intersections.length === 0) return undefined;

  // Compute the average position of intersections
  const avgX = intersections.reduce((sum, p) => sum + p.x, 0) / intersections.length;
  const avgY = intersections.reduce((sum, p) => sum + p.y, 0) / intersections.length;
  return { x: avgX, y: avgY };
}

export function multilaterate(beacons: Beacon[], metersToGridFactor: number) {
  if (beacons.length === 0) return { x: 0, y: 0 };

  if (beacons.length < 3) {
    let best = beacons[0];
    let bestDist = rssiToDistance(best.rssi ?? best.baseRssi, best.baseRssi);
    beacons.forEach(b => {
      const d = rssiToDistance(b.rssi ?? b.baseRssi, b.baseRssi);
      if (d < bestDist) {
        best = b;
        bestDist = d;
      }
    });
    // Ensure we return a valid position object even if best.position is undefined
    return best?.position ? { x: best.position.x, y: best.position.y } : { x: 0, y: 0 };
  }

  if (beacons.length >= 3) {
    const trilaterated = trilaterateByIntersections(beacons, metersToGridFactor);
    if (trilaterated) return trilaterated;
  }

  // Weighted average as fallback
  let totalWeight = 0;
  const weightedSum = { x: 0, y: 0 };

  beacons.forEach(b => {
    if (!b.position) return;
    
    const dist = rssiToDistance(b.rssi ?? b.baseRssi, b.baseRssi);
    // Inverse square weighting - closer beacons have higher weight
    const weight = 1 / Math.max(0.1, dist * dist);

    weightedSum.x += b.position.x * weight;
    weightedSum.y += b.position.y * weight;
    totalWeight += weight;
  });

  if (totalWeight > 0) {
    return {
      x: weightedSum.x / totalWeight,
      y: weightedSum.y / totalWeight
    };
  }

  // Final fallback to avoid undefined
  return { x: 0, y: 0 };
}
