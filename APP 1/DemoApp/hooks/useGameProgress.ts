// useGameProgress.ts
import { useEffect, useState, useCallback, useMemo } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { GamePOI } from '../src/types';

// Use a cache for progress data to reduce AsyncStorage reads
const progressCache: Record<string, boolean> = {};
let hasLoadedInitialData = false;

export function useGameProgress() {
  const [gameTasks, setGameTasks] = useState<GamePOI[]>([]);
  const [totalPoints, setTotalPoints] = useState(0);
  const [isLoading, setIsLoading] = useState(true);

  // Load progress only once when the component mounts
  useEffect(() => {
    if (!hasLoadedInitialData) {
      loadProgress();
    }
    
    // Cleanup function to handle component unmounting
    return () => {
      // If we want to clear the cache when all components unmount,
      // we could add logic here
    };
  }, []);

  const loadProgress = useCallback(async () => {
    try {
      setIsLoading(true);
      
      const [saved, poiData] = await Promise.all([
        AsyncStorage.getItem('game_progress'),
        AsyncStorage.getItem('dynamicPOIs')
      ]);
      
      const completedMap: Record<string, boolean> = saved ? JSON.parse(saved) : {};
      const rawPOIs = poiData ? JSON.parse(poiData) : [];
      
      // Update our cache
      Object.assign(progressCache, completedMap);

      // Convert each POI into a GamePOI
      const tasks = rawPOIs.map((p: any) => ({
        id: p.id,
        name: p.name,
        x: p.position.x,
        y: p.position.y,
        isGameTask: true,
        rewardType: 'points',
        points: 20, // default, or assign based on category or name
        category: 'Visit',
        completed: progressCache[p.id] || false,
      }));
      
      const points = tasks.reduce((sum, t) => t.completed ? sum + t.points : sum, 0);
      
      setGameTasks(tasks);
      setTotalPoints(points);
      hasLoadedInitialData = true;
    } catch (error) {
      console.error('Failed to load game progress:', error);
    } finally {
      setIsLoading(false);
    }
  }, []);

  const completeTask = useCallback(async (poiId: string) => {
    // First check if task is already completed to avoid unnecessary updates
    const existingTask = gameTasks.find(task => task.id === poiId);
    if (existingTask?.completed) return;

    try {
      // Batch state updates to minimize re-renders
      const updatedTasks = gameTasks.map(task =>
        task.id === poiId ? { ...task, completed: true } : task
      );
      
      // Update the points calculation only for the affected task
      const pointsToAdd = updatedTasks.find(t => t.id === poiId)?.points || 0;
      const newTotalPoints = totalPoints + pointsToAdd;
      
      // Update the cache
      progressCache[poiId] = true;
      
      // Update state in a single batch before the async operation
      setGameTasks(updatedTasks);
      setTotalPoints(newTotalPoints);
      
      // Create updated progress map from cache
      const updatedProgress = { ...progressCache };
      
      // Perform AsyncStorage operation without blocking UI
      AsyncStorage.setItem('game_progress', JSON.stringify(updatedProgress))
        .catch(e => console.error('Failed to save game progress:', e));
        
    } catch (error) {
      console.error('Error completing task:', error);
    }
  }, [gameTasks, totalPoints]);

  // Function to manually reload tasks (useful when navigating between screens)
  const reloadTasks = useCallback(() => {
    loadProgress();
  }, [loadProgress]);

  // Use memoization to prevent unnecessary recalculations
  const pendingTasks = useMemo(() => {
    return gameTasks.filter(task => !task.completed).length;
  }, [gameTasks]);

  const gameProgress = useMemo(() => {
    if (gameTasks.length === 0) return 0;
    return ((gameTasks.length - pendingTasks) / gameTasks.length) * 100;
  }, [gameTasks, pendingTasks]);

  return {
    gameTasks,
    totalPoints,
    completeTask,
    isLoading,
    pendingTasks,
    gameProgress,
    reloadTasks, // Export the reload function
  };
}
