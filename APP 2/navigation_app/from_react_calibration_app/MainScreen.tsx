import React, { useEffect, useState, useRef, useMemo, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Dimensions,
  Pressable,
  TextInput,
  Platform,
  FlatList, // Import FlatList
} from 'react-native';
import Svg, { Line, Circle } from 'react-native-svg';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { startNativeScan, stopNativeScan } from '../src/NativeBleScanner';
import { useDistanceAveraging } from '../useDistanceAveraging';
import { useBleScanner } from '../hooks/useBleScanner';
import {
  rssiToDistance,
} from '../utils/positioning';
import { findPath } from '../utils/pathfinding';
import { useSmoothedPosition } from '../hooks/useSmoothedPosition';
import DraggableBeacon from '../components/DraggableBeacon';
import Toolbar from '../components/Toolbar';
import DeviceListItem from '../components/DeviceListItem';
import CalibrationPanel from '../components/CalibrationPanel';
import BeaconEditorPanel from '../components/BeaconEditorPanel';
import MapCanvas from '../components/MapCanvas';
import { Beacon, POI } from '../src/types';
import { placeNewBeacon } from '../utils/beaconHelpers';
import { useNavigation } from '@react-navigation/native'; // Import useNavigation
import { usePositioning } from '../contexts/PositioningContext'; // Add this import

const { width } = Dimensions.get('window');

// Define walkableGrid above the component
const walkableGrid = Array.from({ length: 24 }, (_, row) =>
  Array.from({ length: 24 }, (_, col) =>
    col >= 2 && col <= 7 && row >= 3 && row <= 6 ? 0 : 1
  )
);

export default function MainScreen() {
  const GRID_SIZE = 24;
  const CELL_SIZE = (width - 40) / GRID_SIZE;

  const [mode, setMode] = useState('navigate');
  const [poiNameInput, setPoiNameInput] = useState('');
  const [dynamicPOIs, setDynamicPOIs] = useState([]);
  const [poiCounter, setPoiCounter] = useState(0);
  
  // Get these from the global context instead of local state
  const { beacons: beaconList, setBeacons: setBeaconList, metersToGridFactor, setMetersToGridFactor } = usePositioning();
  
  const [selectedBeacon, setSelectedBeacon] = useState(null);
  const [editedBeaconName, setEditedBeaconName] = useState('');
  const [editedBeaconRssi, setEditedBeaconRssi] = useState('');
  const [editedBeaconX, setEditedBeaconX] = useState('');
  const [editedBeaconY, setEditedBeaconY] = useState('');
  const [newBeaconName, setNewBeaconName] = useState('');
  const [selectedAvailableBeacon, setSelectedAvailableBeacon] = useState(null);
  const [conversionFactor, setConversionFactor] = useState(CELL_SIZE);
  const [calibrationInput, setCalibrationInput] = useState('');
  const scale = conversionFactor;

  // Initialize default position value with x and y coordinates
  const defaultPosition = { x: 0, y: 0 };
  const position = useSmoothedPosition(beaconList, metersToGridFactor, 0.95) || defaultPosition;
  
  // Use a safer reference to last position
  const lastPosition = useRef(defaultPosition);
  const selectedBeaconRef = useRef(null);
  const scanBufferRef = useRef({});
  const handlePacket = useDistanceAveraging(beaconList, setBeaconList);
  const [selectedPOI, setSelectedPOI] = useState(null);
  const [path, setPath] = useState([]);

  const navigation = useNavigation(); // Initialize navigation

  const restartScan = () => {
    stopNativeScan();
    startNativeScan((device) => {
      scanBufferRef.current[device.id] = {
        id: device.id,
        name: device.name,
        rssi: device.rssi,
        lastSeen: Date.now(),
      };
    });
  };

  useEffect(() => {
    const loadData = async () => {
      try {
        const savedPOIs = await AsyncStorage.getItem('dynamicPOIs');
        const savedCounter = await AsyncStorage.getItem('poiCounter');
        if (savedPOIs) setDynamicPOIs(JSON.parse(savedPOIs));
        if (savedCounter) setPoiCounter(parseInt(savedCounter, 10));
      } catch (err) {
        console.error('Failed to load POIs:', err);
      }
    };
    loadData();
  }, []);

  useEffect(() => {
    const saveData = async () => {
      try {
        await AsyncStorage.setItem('dynamicPOIs', JSON.stringify(dynamicPOIs));
        await AsyncStorage.setItem('poiCounter', poiCounter.toString());
      } catch (err) {
        console.error('Failed to save POIs:', err);
      }
    };
    saveData();
  }, [dynamicPOIs, poiCounter]);

  const availableDevices = useBleScanner(beaconList, setBeaconList, handlePacket);

  useEffect(() => {
    if (selectedPOI) {
      const startRow = Math.min(Math.max(Math.round(position.y), 0), GRID_SIZE - 1);
      const startCol = Math.min(Math.max(Math.round(position.x), 0), GRID_SIZE - 1);
      const endRow = Math.min(Math.max(selectedPOI.grid.row, 0), GRID_SIZE - 1);
      const endCol = Math.min(Math.max(selectedPOI.grid.col, 0), GRID_SIZE - 1);
      const start = { row: startRow, col: startCol };
      const end = { row: endRow, col: endCol };
      const computedPath = findPath(start, end, walkableGrid); // Use walkableGrid here
      setPath(computedPath);
    }
  }, [position, selectedPOI]);

  const handleMapPress = useCallback((e) => {
    const x = Math.floor(e.nativeEvent.locationX / scale);
    const y = Math.floor(e.nativeEvent.locationY / scale);

    if (mode === 'edit') {
      const tappedPOIIndex = dynamicPOIs.findIndex(p =>
        Math.abs(p.grid.row - y) < 1 && Math.abs(p.grid.col - x) < 1
      );
      if (tappedPOIIndex !== -1) {
        const updated = [...dynamicPOIs];
        updated.splice(tappedPOIIndex, 1);
        setDynamicPOIs(updated);
      } else {
        const newPOI = {
          id: `POI-${poiCounter}`,
          name: poiNameInput || `POI ${poiCounter}`,
          position: { x, y },
          grid: { row: y, col: x },
          // Ensure compatibility with useGameProgress
          isGameTask: true,
          rewardType: 'points',
          points: 20, // default points
          category: 'Visit',
          completed: false,
        };
        setPoiCounter(poiCounter + 1);
        setDynamicPOIs([...dynamicPOIs, newPOI]);
        setPoiNameInput('');
      }
    } else if (mode === 'addBeacon') {
      placeNewBeacon({
        x,
        y,
        selectedBeaconRef,
        setBeaconList,
        beaconList,
        setSelectedAvailableBeacon,
      });
    }
  }, [mode, scale, dynamicPOIs, poiCounter, poiNameInput, beaconList, selectedBeaconRef, setBeaconList, setSelectedAvailableBeacon]);

  const renderedBeacons = useMemo(() => (
    beaconList.map(b => (
      <DraggableBeacon
        key={b.id}
        beacon={b}
        scale={scale}
        mode={mode}
        isSelected={selectedBeacon?.id === b.id}
        onSelect={(selected) => {
          if (mode === 'edit') {
            setSelectedBeacon(selected);
            setEditedBeaconName(selected.id);
            setEditedBeaconRssi((selected.baseRssi ?? -59).toString());
            setEditedBeaconX(selected.position.x.toString());
            setEditedBeaconY(selected.position.y.toString());
          }
        }}
        onDragEnd={(updatedB) => {
          setBeaconList(beaconList.map(bc => (bc.id === updatedB.id ? updatedB : bc)));
        }}
      />
    ))
  ), [beaconList, mode, selectedBeacon, scale]);

  const renderedCircles = useMemo(() => {
    const radiusData = beaconList.map((b) => {
      const rssi = b.rssi ?? b.baseRssi ?? -59;
      const distMeters = rssiToDistance(rssi, b.baseRssi);
      const distInGrid = distMeters * metersToGridFactor;
      if (!b.position || b.position.x === undefined || b.position.y === undefined) {
        return null;
      }
      return {
        id: b.id,
        cx: b.position.x * scale,
        cy: b.position.y * scale,
        radiusPixels: distInGrid * scale,
      };
    });

    // Visualizing beacon signal range with a semi-transparent blue circle
    return radiusData
      .filter((data) => data && data.cx !== undefined && data.cy !== undefined && data.radiusPixels !== undefined)
      .map((data, i) => (
      <Circle
        key={`radius-${i}`}
        cx={data.cx}
        cy={data.cy}
        r={data.radiusPixels}
        stroke="rgba(0,0,255,0.3)" // Outer border of the signal range
        strokeWidth={1}
        fill="rgba(0,0,255,0.1)" // Inner fill representing the signal area
      />
      ));
  }, [beaconList, metersToGridFactor, scale]);

  const renderedPath = useMemo(() => (
    path.length > 1
      ? path.map((pt, idx) => {
          const next = path[idx + 1];
          if (!next) return null;
          return (
            <Line
              key={`path-${idx}`}
              x1={pt.col * scale + scale / 2}
              y1={pt.row * scale + scale / 2}
              x2={next.col * scale + scale / 2}
              y2={next.row * scale + scale / 2}
              stroke="black"
              strokeWidth={3}
            />
          );
        })
      : []
  ), [path, scale]);

  const dotX = position.x * scale;
  const dotY = position.y * scale;

  return (
    <FlatList
      style={{ flex: 1, paddingTop: 15 }}
      ListHeaderComponent={
        <>
          <Text style={styles.modeIndicator}>Current Mode: {mode.toUpperCase()}</Text>
          <Toolbar 
            mode={mode} 
            setMode={setMode} 
            onClearPOIs={() => setDynamicPOIs([])} 
          />
          <MapCanvas
            scale={scale}
            walkableGrid={walkableGrid}
            beaconList={beaconList}
            dynamicPOIs={dynamicPOIs}
            renderedBeacons={renderedBeacons}
            renderedCircles={renderedCircles}
            renderedPath={renderedPath}
            dotX={dotX}
            dotY={dotY}
            mode={mode}
            onMapPress={handleMapPress}
            onPOIPress={setSelectedPOI}
          />
          {mode === 'addBeacon' && beaconList.length === 2 && (
            <CalibrationPanel
              beaconList={beaconList}
              calibrationInput={calibrationInput}
              setCalibrationInput={setCalibrationInput}
              onCalibrate={(meters) => {
                if (beaconList.length < 2) return;
                
                // Verify that both beacons have valid position data
                const b1 = beaconList[0];
                const b2 = beaconList[1];
                
                if (!b1?.position || !b2?.position) {
                  console.warn('Cannot calibrate: One or both beacons have undefined positions');
                  return;
                }
                
                if (typeof b1.position.x !== 'number' || typeof b1.position.y !== 'number' || 
                    typeof b2.position.x !== 'number' || typeof b2.position.y !== 'number') {
                  console.warn('Cannot calibrate: One or both beacons have invalid position coordinates');
                  return;
                }
                
                const dx = b2.position.x - b1.position.x;
                const dy = b2.position.y - b1.position.y;
                const gridDistance = Math.sqrt(dx * dx + dy * dy);
                
                // Prevent division by zero
                if (meters <= 0) {
                  console.warn('Cannot calibrate: Distance in meters must be greater than zero');
                  return;
                }
                
                const newMetersToGrid = gridDistance / meters;
                setMetersToGridFactor(newMetersToGrid);
              }}
            />
          )}
          {mode === 'navigate' && (
            <View style={{ marginTop: 10, padding: 10 }}>
              <Text style={{ fontWeight: 'bold' }}>Live Beacons:</Text>
              {beaconList.map((b) => {
                const rssi = b.rssi ?? b.baseRssi ?? 'N/A';
                const lastSeen = availableDevices.find(d => d.id === b.id)?.lastSeen;
                const stale = lastSeen && (Date.now() - lastSeen > 10000); // 10 seconds stale timeout
                return (
                  <Text key={b.id}>
                    {b.name || b.id} – RSSI: {rssi} dBm – {stale ? '❌ Stale' : '✅ Active'}
                  </Text>
                );
              })}
            </View>
          )}
          {mode === 'navigate' && (
            <View style={{ marginTop: 10, padding: 10, width: '100%' }}>
              <Text style={{ fontWeight: 'bold', marginBottom: 5 }}>Beacon Signal Info:</Text>
              {beaconList.map((b) => {
                const rssi = b.rssi ?? b.baseRssi ?? -59;
                const distance = rssiToDistance(rssi, b.baseRssi).toFixed(2);
                return (
                  <Text key={b.id}>
                    {b.name || b.id}: RSSI = {rssi} dBm, Est. Distance = {distance} m
                  </Text>
                );
              })}
            </View>
          )}
          
          {/* Beacon Edit Panel */}
          {mode === 'edit' && selectedBeacon && (
            <View style={styles.overlay}>
              <View style={styles.editPanel}>
                <Text style={styles.editPanelTitle}>Edit Beacon</Text>
                <TextInput
                  style={styles.input}
                  value={editedBeaconName}
                  onChangeText={setEditedBeaconName}
                  placeholder="Beacon Name"
                />
                <TextInput
                  style={styles.input}
                  value={editedBeaconRssi}
                  onChangeText={setEditedBeaconRssi}
                  placeholder="Base RSSI"
                  keyboardType="numeric"
                />
                <TextInput
                  style={styles.input}
                  value={editedBeaconX}
                  onChangeText={setEditedBeaconX}
                  placeholder="Beacon X"
                  keyboardType="numeric"
                />
                <TextInput
                  style={styles.input}
                  value={editedBeaconY}
                  onChangeText={setEditedBeaconY}
                  placeholder="Beacon Y"
                  keyboardType="numeric"
                />
                <Pressable
                  style={styles.button}
                  onPress={() => {
                    setBeaconList(beaconList.map(b =>
                      b.id === selectedBeacon.id
                        ? {
                            ...b,
                            id: editedBeaconName,
                            baseRssi: isNaN(parseFloat(editedBeaconRssi))
                              ? b.baseRssi
                              : parseFloat(editedBeaconRssi),
                            position: {
                              x: isNaN(parseFloat(editedBeaconX))
                                ? b.position.x
                                : parseFloat(editedBeaconX),
                              y: isNaN(parseFloat(editedBeaconY))
                                ? b.position.y
                                : parseFloat(editedBeaconY),
                            },
                          }
                        : b
                    ));
                    setSelectedBeacon(null);
                  }}
                >
                  <Text style={styles.buttonText}>Save Changes</Text>
                </Pressable>
                <Pressable
                  style={[styles.button, { backgroundColor: 'red' }]}
                  onPress={() => {
                    setBeaconList(beaconList.filter(b => b.id !== selectedBeacon.id));
                    setAvailableDevices((prev) => {
                      const withoutDuplicate = prev.filter((d) => d.id !== selectedBeacon.id);
                      return [
                        ...withoutDuplicate,
                        {
                          id: selectedBeacon.id,
                          name: selectedBeacon.name,
                          rssi: selectedBeacon.rssi,
                        },
                      ];
                    });
                    setSelectedBeacon(null);
                  }}
                >
                  <Text style={styles.buttonText}>Delete Beacon</Text>
                </Pressable>
              </View>
            </View>
          )}
        </>
      }
      data={mode === 'addBeacon' ? availableDevices.filter(
        (device) =>
          !beaconList.some((b) => b.id === device.id) &&
          device.name?.toLowerCase().startsWith('k')
      ) : []}
      keyExtractor={(item) => item.id}
      renderItem={({ item }) => (
        <DeviceListItem
          devices={[item]}
          selectedDevice={selectedAvailableBeacon}
          onSelectDevice={(device) => {
            setSelectedAvailableBeacon(device);
            selectedBeaconRef.current = device;
          }}
        />
      )}
      ListFooterComponent={
        <>
          {mode === 'navigate' && (
            <>
              <Pressable style={styles.button} onPress={restartScan}>
                <Text style={styles.buttonText}>Restart Scanning</Text>
              </Pressable>
              <Pressable style={styles.button} onPress={() => navigation.navigate('Game')}>
                <Text style={styles.buttonText}>Go to Game</Text>
              </Pressable>
            </>
          )}
          {mode === 'edit' && (
            <>
              <View style={{ margin: 10, width: '90%' }}>
                <Text style={{ fontWeight: 'bold', marginBottom: 5 }}>Enter POI Name:</Text>
                <TextInput
                  style={styles.input}
                  placeholder="Enter POI name"
                  value={poiNameInput}
                  onChangeText={setPoiNameInput}
                />
              </View>
              <View style={{ alignItems: 'center', marginTop: 10 }}>
                <Pressable 
                  style={[styles.button, { backgroundColor: '#FF3B30' }]} 
                  onPress={() => {
                    // Clear all beacons from the map
                    setBeaconList([]);
                    // Also clear any selected beacon
                    setSelectedBeacon(null);
                  }}
                >
                  <Text style={styles.buttonText}>Clear All Beacons</Text>
                </Pressable>
              </View>
            </>
          )}
        </>
      }
    />
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    backgroundColor: '#fff',
    paddingTop: 50
  },
  modeIndicator: {
    fontSize: 16,
    marginBottom: 5,
    fontWeight: '600',
    color: '#555'
  },
  button: {
    backgroundColor: '#007AFF',
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 8,
    margin: 4,
  },
  buttonText: {
    color: 'white',
    fontWeight: 'bold',
  },
  input: {
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 5,
    padding: 8,
    backgroundColor: '#f9f9f9',
    marginBottom: 5,
  },
  overlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  editPanel: {
    backgroundColor: '#fff',
    padding: 20,
    borderRadius: 10,
    width: '80%',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 4,
    elevation: 5,
  },
  closeButton: {
    position: 'absolute',
    top: 10,
    right: 10,
    backgroundColor: 'red',
    borderRadius: 15,
    width: 30,
    height: 30,
    justifyContent: 'center',
    alignItems: 'center',
  },
  closeButtonText: {
    color: 'white',
    fontWeight: 'bold',
  },
  editPanelTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 10,
  },
});
