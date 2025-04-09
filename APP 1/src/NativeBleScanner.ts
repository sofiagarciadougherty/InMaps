import { NativeModules, NativeEventEmitter } from 'react-native';

const { BleScanner } = NativeModules;
const BleScannerEmitter = new NativeEventEmitter(BleScanner);

export function startNativeScan(onResult: (device: { id: string; name: string; rssi: number }) => void) {
  BleScannerEmitter.addListener('BleScanResult', onResult);
  BleScanner.startScan();
}

export function stopNativeScan() {
  BleScanner.stopScan();
  BleScannerEmitter.removeAllListeners('BleScanResult');
}
