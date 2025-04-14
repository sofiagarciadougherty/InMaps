import { NativeModules, NativeEventEmitter } from 'react-native';

const { BleScanner } = NativeModules;
const BleScannerEmitter = new NativeEventEmitter(BleScanner);

export function startNativeScan(
  onResult: (device: { id: string; name: string; rssi: number; manufacturerData?: string }) => void,
  options: { 
    scanMode?: 'LOW_POWER' | 'BALANCED' | 'LOW_LATENCY',
    filterBeaconIds?: string[],
    filterManufacturerIds?: number[],  // Common beacon manufacturers: 0x004C (Apple), 0x0059 (Nordic), etc.
    scanPeriod?: number,               // Scan period in milliseconds
    scanInterval?: number,             // Wait between scans in milliseconds
    namePrefix?: string                // Filter by name prefix at the native level (e.g., "k")
  } = {}
) {
  const { 
    scanMode = 'BALANCED', 
    filterBeaconIds = [],
    filterManufacturerIds = [],
    scanPeriod = 6000,    // Default to 6 seconds scanning
    scanInterval = 1000,  // Default to 1 second between scans
    namePrefix = null     // Default to no name prefix filtering
  } = options;

  BleScannerEmitter.addListener('BleScanResult', onResult);
  BleScanner.startScan({ 
    scanMode,
    filterBeaconIds,
    filterManufacturerIds,
    scanPeriod,
    scanInterval,
    namePrefix
  });
}

export function stopNativeScan() {
  BleScanner.stopScan();
  BleScannerEmitter.removeAllListeners('BleScanResult');
}
