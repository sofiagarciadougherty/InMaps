// useDistanceAveraging.ts
import { useRef, useEffect } from 'react';

// Define the structure of a single RSSI sample
interface RssiSample {
  rssi: number;
  distance: number;
  timestamp: number;
}

// Props: beaconList array and setBeaconList updater
export function useDistanceAveraging(
  beaconList: { id: string; [key: string]: any }[],
  setBeaconList: React.Dispatch<React.SetStateAction<any[]>>,
  txPower = -59,
  pathLossExponent = 2
) {
  const rssiHistoryRef = useRef<{ [beaconId: string]: RssiSample[] }>({});

  const handlePacket = (device: { id: string; rssi: number }) => {
    const distance = Math.pow(10, (txPower - device.rssi) / (10 * pathLossExponent));

    if (!rssiHistoryRef.current[device.id]) {
      rssiHistoryRef.current[device.id] = [];
    }

    // Add new sample
    rssiHistoryRef.current[device.id].push({
      rssi: device.rssi,
      distance,
      timestamp: Date.now(),
    });

    // Keep samples from the last 3 seconds
    rssiHistoryRef.current[device.id] = rssiHistoryRef.current[device.id].filter(
      (s) => Date.now() - s.timestamp < 3000
    );

    // Optional: Add throttling or batching logic here if needed
  };

  useEffect(() => {
    const flushInterval = setInterval(() => {
      const now = Date.now();
      const WINDOW_MS = 2000;

      setBeaconList((prev) =>
        prev.map((b) => {
          const history = rssiHistoryRef.current[b.id] || [];
          const valid = history.filter((s) => now - s.timestamp < WINDOW_MS);
          if (!valid.length) return b;

          const avgDistance = valid.reduce((sum, s) => sum + s.distance, 0) / valid.length;
          return { ...b, avgDistance };
        })
      );
    }, 200);

    return () => clearInterval(flushInterval);
  }, [setBeaconList]);

  return handlePacket;
}

// Basic log-distance path loss model
function rssiToDistance(rssi: number, txPower = -59, pathLossExponent = 2): number {
  return Math.pow(10, (txPower - rssi) / (10 * pathLossExponent));
}
