import { Beacon } from '../screens/types';

export function placeNewBeacon({
  x,
  y,
  selectedBeaconRef,
  setBeaconList,
  beaconList,
  setSelectedAvailableBeacon,
}: {
  x: number;
  y: number;
  selectedBeaconRef: React.MutableRefObject<any>;
  setBeaconList: (b: Beacon[]) => void;
  beaconList: Beacon[];
  setSelectedAvailableBeacon: (b: any) => void;
}) {
  if (!selectedBeaconRef.current) return;

  const beacon = selectedBeaconRef.current;
  const newBeacon: Beacon = {
    id: beacon.id,
    name: beacon.name,
    rssi: beacon.rssi,
    position: { x, y },
    baseRssi: -59,
  };

  setBeaconList([...beaconList, newBeacon]);
  selectedBeaconRef.current = null;
  setSelectedAvailableBeacon(null);
}
