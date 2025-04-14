import { NativeModules, NativeEventEmitter } from 'react-native';

const { BleScanner } = NativeModules;
const BleScannerEmitter = new NativeEventEmitter(BleScanner);

export function startNativeScan(
  onResult: (device: { id: string; name: string; rssi: number }) => void,
  options: { scanMode?: 'LOW_POWER' | 'BALANCED' | 'LOW_LATENCY' } = {}
) {
  const { scanMode = 'LOW_LATENCY' } = options;

  BleScannerEmitter.addListener('BleScanResult', onResult);
  BleScanner.startScan({ scanMode }); // Pass scanMode to native module
}

export function stopNativeScan() {
  BleScanner.stopScan();
  BleScannerEmitter.removeAllListeners('BleScanResult');
}
