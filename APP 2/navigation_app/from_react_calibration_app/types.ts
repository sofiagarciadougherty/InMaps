export interface Beacon {
  id: string;
  name?: string;
  rssi?: number;
  baseRssi?: number;
  position: {
    x: number;
    y: number;
  };
}

export interface POI {
  id: string;
  name: string;
  position: {
    x: number;
    y: number;
  };
  grid: {
    row: number;
    col: number;
  };
}

export interface GamePOI {
  id: string;
  name: string;
  x: number;
  y: number;
  isGameTask: true;
  rewardType: 'points' | 'badge';
  points: number;
  completed: boolean;
  category?: string;
}
