import { useEffect, useRef, useState } from 'react';
import { startNativeScan, stopNativeScan } from '../src/NativeBleScanner';

export function useBleScanner(beaconList, setBeaconList, handlePacket) {
  const [availableDevices, setAvailableDevices] = useState([]);
  const scanBufferRef = useRef({});
  const lastFlushTimeRef = useRef(Date.now());

  useEffect(() => {
    startNativeScan((device) => {
      // Check if the device name starts with "k"
      if (!device.name || !device.name.toLowerCase().startsWith("k")) return;

      // Ignore devices seen within the last 300ms
      if (Date.now() - (scanBufferRef.current[device.id]?.lastSeen || 0) < 300) return;

      handlePacket(device);
      scanBufferRef.current[device.id] = {
        id: device.id,
        name: device.name,
        rssi: device.rssi,
        lastSeen: Date.now(),
      };
    });

    return () => stopNativeScan();
  }, [handlePacket]);

  useEffect(() => {
    const flushInterval = setInterval(() => {
      const buffer = scanBufferRef.current;
      const now = Date.now();
      const flushedDevices = Object.values(buffer);

      if (flushedDevices.length > 0) {
        setAvailableDevices((prevDevices) => {
          const updated = [...prevDevices];
          flushedDevices.forEach((d) => {
            const index = updated.findIndex(dev => dev.id === d.id);
            if (index !== -1) {
              updated[index] = d;
            } else {
              updated.push(d);
            }
          });
          return updated;
        });

        setBeaconList((prevBeacons) => {
          return prevBeacons.map(b =>
            buffer[b.id] ? { ...b, rssi: buffer[b.id].rssi } : b
          );
        });

        scanBufferRef.current = {};
        lastFlushTimeRef.current = now;
      }
    }, 300);

    return () => clearInterval(flushInterval);
  }, []);

  return availableDevices;
}
