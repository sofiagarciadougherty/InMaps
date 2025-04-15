// GameScreen.tsx
import React, { useEffect, useRef, useState, useMemo, useCallback } from 'react';
import { 
  View, 
  Text, 
  FlatList, 
  StyleSheet, 
  ToastAndroid, 
  Platform, 
  Dimensions, 
  Animated,
  Pressable
} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useGameProgress } from '../hooks/useGameProgress';
import { useSmoothedPosition } from '../hooks/useSmoothedPosition';
import { usePositioning } from '../contexts/PositioningContext';
import { useFocusEffect } from '@react-navigation/native';
import Svg, { Line, Circle } from 'react-native-svg';
import MapCanvas from '../components/MapCanvas';
import { findPath } from '../utils/pathfinding';

const { width } = Dimensions.get('window');

// Constants defined outside component to prevent recreation on each render
const GRID_SIZE = 24;
const CELL_SIZE = (width - 40) / GRID_SIZE;
const PROXIMITY_THRESHOLD_METERS = 1.5;

// Create walkable grid once, not on every render
const walkableGrid = Array.from({ length: GRID_SIZE }, () => Array(GRID_SIZE).fill(1));

export default function GameScreen() {
  const { gameTasks, totalPoints, completeTask, reloadTasks } = useGameProgress();
  const { beacons, metersToGridFactor } = usePositioning();
  const position = useSmoothedPosition(beacons, metersToGridFactor, 0.95) || { x: 0, y: 0 };
  const [selectedPOI, setSelectedPOI] = useState(null);
  const [activeTaskId, setActiveTaskId] = useState(null);
  const cooldownRef = useRef(false);
  const [path, setPath] = useState([]);
  
  // Animation values for reward popup
  const popupScale = useRef(new Animated.Value(0)).current;
  const popupOpacity = useRef(new Animated.Value(0)).current;
  const [rewardText, setRewardText] = useState('');
  const [showReward, setShowReward] = useState(false);

  const scale = CELL_SIZE;
  
  // Memoize the POI list to prevent recreation on every render
  const poiList = useMemo(() => gameTasks.map(task => ({
    id: task.id,
    name: task.name,
    position: { x: task.x, y: task.y },
    grid: { row: Math.floor(task.y), col: Math.floor(task.x) },
    completed: task.completed,
    // Add these properties to match what MapCanvas expects
    x: task.x,
    y: task.y
  })), [gameTasks]);

  // Create a stable version of the completeTask function
  const handleCompleteTask = useCallback((taskId) => {
    completeTask(taskId);
  }, [completeTask]);

  // Reload tasks whenever the screen comes into focus
  useFocusEffect(
    useCallback(() => {
      // Reload tasks to get latest POIs
      reloadTasks();
      return () => {};
    }, [reloadTasks])
  );

  // Update path when selected POI changes - memoize dependencies
  useEffect(() => {
    if (!selectedPOI) {
      setPath([]);
      return;
    }
    
    const startRow = Math.min(Math.max(Math.round(position.y), 0), GRID_SIZE - 1);
    const startCol = Math.min(Math.max(Math.round(position.x), 0), GRID_SIZE - 1);
    const endRow = Math.min(Math.max(Math.round(selectedPOI.y), 0), GRID_SIZE - 1);
    const endCol = Math.min(Math.max(Math.round(selectedPOI.x), 0), GRID_SIZE - 1);
    
    const start = { row: startRow, col: startCol };
    const end = { row: endRow, col: endCol };
    const computedPath = findPath(start, end, walkableGrid);
    setPath(computedPath);
  }, [position.x, position.y, selectedPOI]);

  // Check proximity to POIs with stabilized dependencies
  useEffect(() => {
    if (cooldownRef.current || !gameTasks.length || !selectedPOI) return;

    // Only check proximity for the selected POI that has an active navigation route
    const task = gameTasks.find(t => t.id === selectedPOI.id);
    
    if (task && !task.completed) {
      const distMeters = Math.sqrt(
        Math.pow(task.x - position.x, 2) + 
        Math.pow(task.y - position.y, 2)
      ) / metersToGridFactor;
      
      if (distMeters < PROXIMITY_THRESHOLD_METERS) {
        cooldownRef.current = true;
        
        // Complete the task
        handleCompleteTask(task.id);
        
        // Update UI state
        setActiveTaskId(task.id);
        setRewardText(`+${task.points} points!`);
        setShowReward(true);
        
        // Reset animation values first
        popupScale.setValue(0);
        popupOpacity.setValue(0);
        
        // Animate reward popup
        Animated.sequence([
          Animated.parallel([
            Animated.timing(popupScale, {
              toValue: 1.2,
              duration: 300,
              useNativeDriver: true
            }),
            Animated.timing(popupOpacity, {
              toValue: 1,
              duration: 300,
              useNativeDriver: true
            })
          ]),
          Animated.timing(popupScale, {
            toValue: 1,
            duration: 200,
            useNativeDriver: true
          }),
          Animated.delay(1000),
          Animated.parallel([
            Animated.timing(popupScale, {
              toValue: 0.8,
              duration: 200,
              useNativeDriver: true
            }),
            Animated.timing(popupOpacity, {
              toValue: 0,
              duration: 200,
              useNativeDriver: true
            })
          ])
        ]).start();
        
        // Use setTimeout for state updates instead of animation callback
        setTimeout(() => {
          setShowReward(false);
        }, 1700); // Total animation duration

        if (Platform.OS === 'android') {
          ToastAndroid.show(`🎉 ${task.name} completed! +${task.points} pts`, ToastAndroid.LONG);
        }
        
        // Clear selection and navigation path after completing the task
        setTimeout(() => {
          cooldownRef.current = false;
          setActiveTaskId(null);
          setSelectedPOI(null); // Clear the selection after task completion
        }, 3000);
      }
    }
  }, [position.x, position.y, metersToGridFactor, gameTasks, handleCompleteTask, selectedPOI]);

  // Memoize the rendered path to prevent recreation on each render
  const renderedPath = useMemo(() => {
    if (path.length <= 1) return [];
    
    return path.map((pt, idx) => {
      const next = path[idx + 1];
      if (!next) return null;
      return (
        <Line
          key={`path-${idx}`}
          x1={pt.col * scale + scale / 2}
          y1={pt.row * scale + scale / 2}
          x2={next.col * scale + scale / 2}
          y2={next.row * scale + scale / 2}
          stroke="#007AFF"
          strokeWidth={3}
        />
      );
    }).filter(Boolean);
  }, [path, scale]);

  const dotX = position.x * scale;
  const dotY = position.y * scale;

  // Use a stable callback for POI selection
  const handleSelectPOI = useCallback((poi) => {
    setSelectedPOI(poi);
  }, []);

  return (
    <View style={styles.container}>
      {/* Fixed header with points - always visible */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>🎮 Game Mode</Text>
        <Text style={styles.pointsDisplay}>Total Points: {totalPoints}</Text>
      </View>
      
      {/* Scrollable content */}
      <FlatList
        style={styles.scrollContent}
        ListHeaderComponent={
          <>
            {/* Map with positioning */}
            <View style={styles.mapContainer}>
              <MapCanvas
                scale={scale}
                walkableGrid={walkableGrid}
                beaconList={[]} // Don't show beacons on the game screen
                dynamicPOIs={poiList}
                renderedBeacons={[]} // Don't show beacons
                renderedCircles={[]} // Don't show signal circles
                renderedPath={renderedPath}
                dotX={dotX}
                dotY={dotY}
                mode="navigate"
                onMapPress={() => {}} // No map press action needed
                onPOIPress={handleSelectPOI}
                showCompletedPOIs={true}
              />
            </View>
            
            {/* Reset Game Button */}
            <View style={styles.resetContainer}>
              <Pressable 
                style={styles.resetButton}
                onPress={() => {
                  // Clear all completions and reset points
                  AsyncStorage.removeItem('game_progress');
                  // Clear POI selection and active state
                  setSelectedPOI(null);
                  setActiveTaskId(null);
                  // Reset points and completed tasks in the game state
                  reloadTasks();
                  // Show feedback to the user
                  Platform.OS === 'android' && 
                    ToastAndroid.show('Game progress reset!', ToastAndroid.SHORT);
                }}
              >
                <Text style={styles.resetButtonText}>Reset Game Progress</Text>
              </Pressable>
            </View>
            
            <Text style={styles.taskListHeader}>Game Tasks:</Text>
          </>
        }
        data={gameTasks}
        keyExtractor={(item) => item.id}
        renderItem={({ item }) => (
          <Pressable 
            style={[
              styles.card, 
              item.completed && styles.completedCard,
              activeTaskId === item.id && styles.activeCard,
              selectedPOI?.id === item.id && styles.selectedCard
            ]}
            onPress={() => handleSelectPOI(item)}
          >
            <Text style={styles.name}>{item.name}</Text>
            <Text>{item.category || 'Visit Location'}</Text>
            <Text>{item.completed ? '✅ Completed' : '🕓 Pending'}</Text>
            <Text>Reward: {item.points} points</Text>
          </Pressable>
        )}
        showsVerticalScrollIndicator={true}
        contentContainerStyle={{ paddingBottom: 20 }}
      />
      
      {/* Reward popup - overlay that appears regardless of scroll position */}
      {showReward && (
        <Animated.View 
          style={[
            styles.rewardPopup,
            {
              opacity: popupOpacity,
              transform: [{ scale: popupScale }]
            }
          ]}
        >
          <Text style={styles.rewardText}>{rewardText}</Text>
        </Animated.View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { 
    flex: 1, 
    padding: 16,
    backgroundColor: '#fff'
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16
  },
  headerTitle: { 
    fontSize: 22, 
    fontWeight: 'bold'
  },
  pointsDisplay: { 
    fontSize: 18, 
    fontWeight: 'bold',
    color: '#007AFF',
  },
  taskListHeader: {
    fontSize: 18,
    fontWeight: 'bold',
    marginTop: 16,
    marginBottom: 8
  },
  card: {
    padding: 12,
    borderRadius: 8,
    backgroundColor: '#f3f3f3',
    marginBottom: 12,
  },
  completedCard: {
    backgroundColor: '#e6ffe6',
    borderLeftWidth: 4,
    borderLeftColor: '#34C759',
  },
  activeCard: {
    borderWidth: 2,
    borderColor: 'gold',
    backgroundColor: '#fffaeb',
  },
  selectedCard: {
    borderWidth: 2,
    borderColor: '#007AFF',
    backgroundColor: '#f0f8ff',
  },
  name: { 
    fontSize: 18, 
    fontWeight: 'bold' 
  },
  mapContainer: {
    width: '100%',
    height: 300,
    borderRadius: 8,
    overflow: 'hidden',
    backgroundColor: '#f9f9f9',
    borderWidth: 1,
    borderColor: '#ddd'
  },
  rewardPopup: {
    position: 'absolute',
    top: '40%',
    left: '50%',
    marginLeft: -100,
    width: 200,
    backgroundColor: 'rgba(52, 199, 89, 0.95)',
    borderRadius: 16,
    padding: 16,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 8,
    zIndex: 1000,
  },
  rewardText: {
    color: 'white',
    fontSize: 24,
    fontWeight: 'bold',
    textAlign: 'center',
  },
  scrollContent: {
    flex: 1,
  },
  resetContainer: {
    marginVertical: 16,
    alignItems: 'center',
  },
  resetButton: {
    backgroundColor: '#FF3B30',
    paddingVertical: 12,
    paddingHorizontal: 24,
    borderRadius: 8,
  },
  resetButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: 'bold',
  },
});
