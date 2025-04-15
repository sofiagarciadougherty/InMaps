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
  txPower = -50,
  pathLossExponent = 2
) {
  const rssiHistoryRef = useRef<{ [beaconId: string]: RssiSample[] }>({});

  const MAX_SAMPLES = 40; // Cap the number of samples per beacon
  const RSSI_WINDOW_MS = 7500; // Adjusted RSSI averaging window
  const FLUSH_INTERVAL_MS = 250; // Adjusted flush interval

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

    // Keep samples from the last RSSI_WINDOW_MS
    rssiHistoryRef.current[device.id] = rssiHistoryRef.current[device.id].filter(
      (s) => Date.now() - s.timestamp < RSSI_WINDOW_MS
    );

    // Enforce sample count cap
    if (rssiHistoryRef.current[device.id].length > MAX_SAMPLES) {
      rssiHistoryRef.current[device.id].shift(); // Drop oldest sample
    }
  };

  useEffect(() => {
    const flushInterval = setInterval(() => {
      const now = Date.now();

      setBeaconList((prev) =>
        prev.map((b) => {
          const history = rssiHistoryRef.current[b.id] || [];
          const valid = history.filter((s) => now - s.timestamp < RSSI_WINDOW_MS);
          if (!valid.length) return b;

          const avgDistance = valid.reduce((sum, s) => sum + s.distance, 0) / valid.length;
          return { ...b, avgDistance };
        })
      );
    }, FLUSH_INTERVAL_MS); // Adjusted flush interval

    return () => clearInterval(flushInterval);
  }, [setBeaconList]);

  return handlePacket;
}

// Basic log-distance path loss model
function rssiToDistance(rssi: number, txPower = -59, pathLossExponent = 2): number {
  return Math.pow(10, (txPower - rssi) / (10 * pathLossExponent));
}
