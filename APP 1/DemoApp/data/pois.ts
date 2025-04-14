import { GamePOI } from '../src/types';

export const allPOIs: GamePOI[] = [
  {
    id: 'poi1',
    name: 'Booth A',
    x: 10,
    y: 12,
    isGameTask: true,
    rewardType: 'points',
    points: 50,
    completed: false,
    category: 'Visit',
  },
  {
    id: 'poi2',
    name: 'Booth B',
    x: 5,
    y: 8,
    isGameTask: true,
    rewardType: 'points',
    points: 30,
    completed: false,
    category: 'Scan',
  },
];
