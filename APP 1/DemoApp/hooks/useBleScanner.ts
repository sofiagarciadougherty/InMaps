import { useEffect, useRef, useState } from 'react';
import { startNativeScan, stopNativeScan } from '../src/NativeBleScanner';
import { usePositioning } from '../contexts/PositioningContext';
import { Platform, AppState } from 'react-native';

// Known manufacturer IDs for common beacon types
const BEACON_MANUFACTURER_IDS = [
  0x004C, // Apple (iBeacon)
  0x0059, // Nordic Semiconductor
  0x0499, // Ruuvi
  0x0157, // Eddystone (Google)
];

// Configuration for different environments
const ENVIRONMENT_CONFIGS = {
  normal: {
    scanMode: 'BALANCED',
    scanPeriod: 6000,
    scanInterval: 2000,
    signalThreshold: -90,
    smoothingFactor: 0.2
  },
  crowded: {
    scanMode: 'BALANCED',
    scanPeriod: 4000,
    scanInterval: 3000, 
    signalThreshold: -85,
    smoothingFactor: 0.3
  },
  highPrecision: {
    scanMode: 'LOW_LATENCY',
    scanPeriod: 8000,
    scanInterval: 1000,
    signalThreshold: -95,
    smoothingFactor: 0.2
  },
  batterySaving: {
    scanMode: 'LOW_POWER',
    scanPeriod: 3000,
    scanInterval: 5000,
    signalThreshold: -80,
    smoothingFactor: 0.4
  },
  // New wide scanning mode for maximum packet capture with minimal filtering
  wideScan: {
    scanMode: 'LOW_LATENCY',
    scanPeriod: 30000,
    scanInterval: 100, 
    signalThreshold: -100,
    smoothingFactor: 0.6 // Higher value = more responsive to new readings
  },
  // Emergency mode for when we need absolute maximum beacon reception
  emergency: {
    scanMode: 'LOW_LATENCY',
    scanPeriod: 0,        // No cycling - continuous scan
    scanInterval: 0,      // No pauses
    signalThreshold: -110, // Accept anything detectable
    smoothingFactor: 0.9  // Almost no smoothing - use raw values
  }
};

export function useBleScanner(beaconList, setBeaconList, handlePacket, environmentType = 'emergency') {
  const [availableDevices, setAvailableDevices] = useState([]);
  const { setBeacons } = usePositioning();
  const scanBufferRef = useRef({});
  const lastFlushTimeRef = useRef(Date.now());
  const appState = useRef(AppState.currentState);
  const scanStartedRef = useRef(false);
  
  // Get environment configuration - default to emergency mode for maximum reception
  const config = ENVIRONMENT_CONFIGS[environmentType] || ENVIRONMENT_CONFIGS.emergency;

  // Extract beacon IDs for filtering if they're in our list
  const knownBeaconIds = useRef(beaconList.map(beacon => beacon.id).filter(Boolean));

  // Track app state to restart scanning when app comes to foreground
  useEffect(() => {
    const subscription = AppState.addEventListener('change', nextAppState => {
      if (appState.current.match(/inactive|background/) && nextAppState === 'active') {
        // App has come to the foreground - restart scanning
        if (scanStartedRef.current) {
          stopNativeScan();
          startScan();
        }
      }
      appState.current = nextAppState;
    });

    return () => {
      subscription.remove();
    };
  }, []);

  useEffect(() => {
    // Update known beacon IDs when beacon list changes
    knownBeaconIds.current = beaconList.map(beacon => beacon.id).filter(Boolean);
  }, [beaconList]);
  
  // Function to start scanning with current configuration
  const startScan = () => {
    scanStartedRef.current = true;
    startNativeScan((device) => {
      // Check if the signal is above our minimum threshold
      if (device.rssi < config.signalThreshold) return;

      // Process every packet with minimal debouncing
      handlePacket(device);
      
      // Update scan buffer
      scanBufferRef.current[device.id] = {
        id: device.id,
        name: device.name || "Unknown",
        rssi: device.rssi,
        manufacturerData: device.manufacturerData,
        lastSeen: Date.now(),
      };
    }, {
      scanMode: config.scanMode,
      filterBeaconIds: knownBeaconIds.current,
      filterManufacturerIds: BEACON_MANUFACTURER_IDS,
      scanPeriod: config.scanPeriod,
      scanInterval: config.scanInterval,
      namePrefix: "k"  // Apply native-level filtering for device names starting with "k"
    });
  };
  
  useEffect(() => {
    // Start the scan
    startScan();

    // Clean up when component unmounts or environment changes
    return () => {
      scanStartedRef.current = false;
      stopNativeScan();
    };
  }, [environmentType, config]);

  useEffect(() => {
    // Use more frequent updates for UI refresh - 100ms in emergency mode
    const flushInterval = setInterval(() => {
      const buffer = scanBufferRef.current;
      const now = Date.now();
      const flushedDevices = Object.values(buffer);

      if (flushedDevices.length > 0) {
        // Process for UI display
        setAvailableDevices((prevDevices) => {
          const updated = [...prevDevices];
          flushedDevices.forEach((d) => {
            const index = updated.findIndex(dev => dev.id === d.id);
            if (index !== -1) {
              // Apply configured smoothing
              updated[index] = {
                ...updated[index],
                rssi: config.smoothingFactor * d.rssi + (1-config.smoothingFactor) * updated[index].rssi,
                lastSeen: now
              };
            } else {
              updated.push(d);
            }
          });
          return updated;
        });

        // Update beacon data for positioning with minimal processing
        setBeaconList((prevBeacons) => {
          const updatedBeacons = prevBeacons.map(b => {
            if (buffer[b.id]) {
              const newRssi = buffer[b.id].rssi;
              const oldRssi = b.rssi || b.baseRssi || -70;
              
              // Use high smoothing factor in emergency mode for near-raw readings
              return { 
                ...b, 
                rssi: config.smoothingFactor * newRssi + (1-config.smoothingFactor) * oldRssi,
                lastSeen: now
              };
            }
            return b;
          });
          
          // Update the global context
          setBeacons(updatedBeacons);
          
          return updatedBeacons;
        });

        // Only clear processed devices from buffer
        const processedIds = Object.keys(buffer);
        processedIds.forEach(id => {
          delete scanBufferRef.current[id];
        });
        
        lastFlushTimeRef.current = now;
      }
    }, environmentType === 'emergency' ? 100 : 150);

    return () => clearInterval(flushInterval);
  }, [setBeacons, setBeaconList, environmentType, config]);

  return [availableDevices || [], setAvailableDevices];
}
