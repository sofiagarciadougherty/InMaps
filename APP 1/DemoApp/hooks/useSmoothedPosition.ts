import { useEffect, useRef, useState } from 'react';
import { Beacon } from '../src/types';
import { rssiToDistance, multilaterate } from '../utils/positioning';

export function useSmoothedPosition(
  beacons: Beacon[],
  metersToGridFactor: number,
  alpha: number = 0.95,
  intervalMs: number = 500
) {
  // Initialize with default coordinates to ensure we never return undefined
  const [position, setPosition] = useState({ x: 0, y: 0 });
  const lastPosition = useRef({ x: 0, y: 0 });

  useEffect(() => {
    const interval = setInterval(() => {
      // Use a safe default position if we can't calculate one
      let newPos = { x: lastPosition.current.x, y: lastPosition.current.y };
      
      const connected = beacons.filter(b => b.rssi !== undefined);

      if (connected.length >= 3) {
        const calculatedPos = multilaterate(connected, metersToGridFactor);
        // Only use the calculated position if it exists and has valid x,y properties
        if (calculatedPos && typeof calculatedPos.x === 'number' && typeof calculatedPos.y === 'number') {
          newPos = calculatedPos;
        }
      } else if (connected.length > 0) {
        const sorted = connected.sort((a, b) => {
          const da = rssiToDistance(a.rssi ?? a.baseRssi, a.baseRssi);
          const db = rssiToDistance(b.rssi ?? b.baseRssi, b.baseRssi);
          return da - db;
        });
        if (sorted[0]?.position && typeof sorted[0].position.x === 'number' && typeof sorted[0].position.y === 'number') {
          newPos = sorted[0].position;
        }
      }

      // Always ensure we have valid x and y coordinates
      const smoothed = {
        x: lastPosition.current.x * (1 - alpha) + newPos.x * alpha,
        y: lastPosition.current.y * (1 - alpha) + newPos.y * alpha,
      };
      lastPosition.current = smoothed;
      setPosition(smoothed);
    }, intervalMs);

    return () => clearInterval(interval);
  }, [beacons, metersToGridFactor, alpha, intervalMs]);

  // Return position, guaranteed to have x and y properties
  return position;
}
