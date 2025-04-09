import { useEffect, useRef, useState } from 'react';
import { Beacon, multilaterate, rssiToDistance } from '../utils/positioning';

export function useSmoothedPosition(
  beacons: Beacon[],
  metersToGridFactor: number,
  alpha: number = 0.95,
  intervalMs: number = 300
) {
  const [position, setPosition] = useState({ x: 0, y: 0 });
  const lastPosition = useRef({ x: 0, y: 0 });

  useEffect(() => {
    const interval = setInterval(() => {
      const connected = beacons.filter(b => b.rssi !== undefined);

      let newPos;
      if (connected.length >= 3) {
        newPos = multilaterate(connected, metersToGridFactor);
      } else if (connected.length > 0) {
        const sorted = connected.sort((a, b) => {
          const da = rssiToDistance(a.rssi ?? a.baseRssi, a.baseRssi);
          const db = rssiToDistance(b.rssi ?? b.baseRssi, b.baseRssi);
          return da - db;
        });
        newPos = sorted[0].position;
      } else {
        newPos = lastPosition.current;
      }

      if (newPos && newPos.x !== undefined && newPos.y !== undefined) {
        const smoothed = {
          x: lastPosition.current.x * (1 - alpha) + newPos.x * alpha,
          y: lastPosition.current.y * (1 - alpha) + newPos.y * alpha,
        };
        lastPosition.current = smoothed;
        setPosition(smoothed);
      }
    }, intervalMs);

    return () => clearInterval(interval);
  }, [beacons, metersToGridFactor, alpha, intervalMs]);

  return position;
}
