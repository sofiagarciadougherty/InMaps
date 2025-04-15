import React, { createContext, useContext, useState } from 'react';
import { Beacon } from '../types/Beacon'; // Ensure this type exists or create it
import { GamePOI } from '../types'; // Ensure this type exists

type PositioningContextType = {
  beacons: Beacon[];
  setBeacons: (b: Beacon[]) => void;
  metersToGridFactor: number;
  setMetersToGridFactor: (m: number) => void;
  gameTasks: GamePOI[];
  totalPoints: number;
  completeTask: (poiId: string) => void;
};

const PositioningContext = createContext<PositioningContextType | undefined>(undefined);

export const PositioningProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [beacons, setBeacons] = useState<Beacon[]>([]);
  const [metersToGridFactor, setMetersToGridFactor] = useState<number>(1);
  const [gameTasks, setGameTasks] = useState<GamePOI[]>([]);
  const [totalPoints, setTotalPoints] = useState(0);

  const completeTask = (poiId: string) => {
    setGameTasks((prevTasks) => {
      const updatedTasks = prevTasks.map((task) =>
        task.id === poiId ? { ...task, completed: true } : task
      );
      const newPoints = updatedTasks.reduce((sum, t) => (t.completed ? sum + t.points : sum), 0);
      setTotalPoints(newPoints);
      return updatedTasks;
    });
  };

  React.useEffect(() => {
    const PROXIMITY_THRESHOLD_METERS = 1.0;

    const checkProximity = () => {
      beacons.forEach((beacon) => {
        // Skip beacons with no valid position
        if (!beacon || !beacon.position) return;
        
        gameTasks.forEach((task) => {
          if (!task.completed && task.x !== undefined && task.y !== undefined) {
            const distMeters = Math.sqrt(
              (task.x - beacon.position.x) ** 2 + (task.y - beacon.position.y) ** 2
            ) / metersToGridFactor;

            if (distMeters < PROXIMITY_THRESHOLD_METERS) {
              completeTask(task.id);
            }
          }
        });
      });
    };

    const interval = setInterval(checkProximity, 1000); // Check every second
    return () => clearInterval(interval);
  }, [beacons, gameTasks, metersToGridFactor]);

  return (
    <PositioningContext.Provider
      value={{
        beacons,
        setBeacons,
        metersToGridFactor,
        setMetersToGridFactor,
        gameTasks,
        totalPoints,
        completeTask,
      }}
    >
      {children}
    </PositioningContext.Provider>
  );
};

export const usePositioning = () => {
  const context = useContext(PositioningContext);
  if (!context) throw new Error('usePositioning must be used within a PositioningProvider');
  return context;
};
