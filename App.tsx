import React, { useEffect, useState, useRef, useMemo, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Dimensions,
  Pressable,
  ImageBackground,
  TextInput,
  PanResponder,
  FlatList,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
} from 'react-native';
import Svg, { Line, Rect, Circle } from 'react-native-svg';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { startNativeScan, stopNativeScan } from './src/NativeBleScanner';
import { useDistanceAveraging } from './useDistanceAveraging';
import { useBleScanner } from './hooks/useBleScanner';
import {
  rssiToDistance,
  getCircleIntersections,
  trilaterateByIntersections,
  multilaterate,
} from './utils/positioning';
import { useSmoothedPosition } from './hooks/useSmoothedPosition';
import { findPath } from './utils/pathfinding';
import DraggableBeacon from './components/DraggableBeacon';
import POIMarker from './components/POIMarker';

const { width } = Dimensions.get('window');

// Create a grid representing walkable areas (cells with value 0 are non-walkable)
const walkableGrid = Array.from({ length: 24 }, (_, row) =>
  Array.from({ length: 24 }, (_, col) =>
    (col >= 2 && col <= 7 && row >= 3 && row <= 6) ? 0 : 1
  )
);
const GRID_SIZE = walkableGrid.length;
const CELL_SIZE = (width - 40) / GRID_SIZE;

// Initial beacons – can be edited, added, deleted
const baseBeacons = []; // Start with an empty array

// Some predefined POIs that always appear on the map
const pois = [
  { id: 'Stage', name: 'Stage', position: { x: 20, y: 20 }, grid: { row: 20, col: 20 } },
  { id: 'Exit', name: 'Exit', position: { x: 23, y: 23 }, grid: { row: 23, col: 23 } },
];

const ALPHA = 0.95;
const MAX_DISTANCE = 15; // Only beacons with computed distance <= this are used in trilateration

export default function App() {
  // The app can be in "navigate", "edit", or "addBeacon" mode
  const [mode, setMode] = useState('navigate');
  // POI-related state
  const [poiNameInput, setPoiNameInput] = useState('');
  const [dynamicPOIs, setDynamicPOIs] = useState([]);
  const [poiCounter, setPoiCounter] = useState(0);
  // Beacon-related state
  const [beaconList, setBeaconList] = useState([]); // Initialize with an empty array
  const [selectedBeacon, setSelectedBeacon] = useState(null);
  const [editedBeaconName, setEditedBeaconName] = useState('');
  const [editedBeaconRssi, setEditedBeaconRssi] = useState('');
  const [editedBeaconX, setEditedBeaconX] = useState('');
  const [editedBeaconY, setEditedBeaconY] = useState('');
  const [newBeaconName, setNewBeaconName] = useState('');
  const [selectedAvailableBeacon, setSelectedAvailableBeacon] = useState(null); // Track selected detected beacon
  const [conversionFactor, setConversionFactor] = useState(CELL_SIZE);
  const [calibrationInput, setCalibrationInput] = useState('');
  const [metersToGridFactor, setMetersToGridFactor] = useState(1);
  const scale = conversionFactor;
  // User position (x,y in grid units)
  const position = useSmoothedPosition(beaconList, metersToGridFactor, ALPHA);
  const lastPosition = useRef<{ x: number; y: number }>({ x: 0, y: 0 }); // Ensure proper initialization

  const selectedBeaconRef = useRef(null); // ✅ Add useRef lock for selected beacon
  const scanBufferRef = useRef({});

  // Ensure useDistanceAveraging is called unconditionally at the top level
  const handlePacket = useDistanceAveraging(beaconList, setBeaconList);

  // Selected POI for pathfinding
  const [selectedPOI, setSelectedPOI] = useState(null);
  const [path, setPath] = useState([]);

  // Load dynamic POIs from storage
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

  // Save dynamic POIs
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

  // --- NEW: Real BLE scanning effect replacing simulation ---
  // Ensure useDistanceAveraging is called unconditionally
  const availableDevices = useBleScanner(beaconList, setBeaconList, handlePacket);
  
  // Whenever a POI is selected, find a path from user position to POI using A*
  useEffect(() => {
    if (selectedPOI) {
      const startRow = Math.min(Math.max(Math.round(position.y), 0), GRID_SIZE - 1);
      const startCol = Math.min(Math.max(Math.round(position.x), 0), GRID_SIZE - 1);
      const endRow = Math.min(Math.max(selectedPOI.grid.row, 0), GRID_SIZE - 1);
      const endCol = Math.min(Math.max(selectedPOI.grid.col, 0), GRID_SIZE - 1);
      const start = { row: startRow, col: startCol };
      const end = { row: endRow, col: endCol };
      const computedPath = findPath(start, end, walkableGrid);
      setPath(computedPath);
    }
  }, [position, selectedPOI]);

  // Tap handler for the map overlay
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
          grid: { row: y, col: x }
        };
        setPoiCounter(poiCounter + 1);
        setDynamicPOIs([...dynamicPOIs, newPOI]);
        setPoiNameInput('');
      }
    } else if (mode === 'addBeacon') {
      if (selectedBeaconRef.current) { // ✅ Use the ref lock
        const beacon = selectedBeaconRef.current;
        const newBeacon = {
          id: beacon.id,
          name: beacon.name,
          rssi: beacon.rssi,
          position: { x, y },
          baseRssi: -59, // Default value for RSSI
        };
        setBeaconList([...beaconList, newBeacon]);
        selectedBeaconRef.current = null; // ✅ Clear the ref lock
        setSelectedAvailableBeacon(null);
      }
    }
  }, [mode, scale, dynamicPOIs, poiCounter, poiNameInput, beaconList]);

  const dotX = position.x * scale;
  const dotY = position.y * scale;

  const handleAddBeacon = (device) => {
    setBeaconList((prevBeacons) => [
      ...prevBeacons,
      { id: device.id, name: device.name, rssi: device.rssi, position: { x: 0, y: 0 } },
    ]);
  };

  const filteredAvailableDevices = availableDevices.filter(
    (device) =>
      !beaconList.some((beacon) => beacon.id === device.id) &&
      device.name?.toLowerCase().startsWith('k') // Filter for names starting with 'k'
  );

  const sortedFilteredDevices = useMemo(() => [...filteredAvailableDevices].sort((a, b) => b.rssi - a.rssi), [filteredAvailableDevices]);

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

  // Precompute handlers for beacons to avoid dynamic hook calls inside .map()
  const beaconHandlers = useMemo(() => {
    return beaconList.reduce((acc, b) => {
      acc[b.id] = {
        onSelect: (selected) => {
          if (mode === 'edit') {
            setSelectedBeacon(selected);
            setEditedBeaconName(selected.id);
            setEditedBeaconRssi(
              selected.baseRssi !== undefined
                ? selected.baseRssi.toString()
                : '-59' // Default if missing
            );
            setEditedBeaconX(selected.position.x?.toString() || '0');
            setEditedBeaconY(selected.position.y?.toString() || '0');
          }
        },
        onDragEnd: (updatedB) => {
          setBeaconList(beaconList.map(bc => (bc.id === updatedB.id ? updatedB : bc)));
        },
      };
      return acc;
    }, {});
  }, [beaconList, mode]);

  const renderedBeacons = useMemo(() => (
    beaconList.map(b => (
      <DraggableBeacon
        key={b.id}
        beacon={b}
        scale={scale}
        mode={mode}
        isSelected={selectedBeacon?.id === b.id}
        onSelect={beaconHandlers[b.id]?.onSelect}
        onDragEnd={beaconHandlers[b.id]?.onDragEnd}
      />
    ))
  ), [beaconList, mode, selectedBeacon, scale, beaconHandlers]);

  const renderDeviceItem = useCallback(({ item }) => (
    <Pressable
      style={[
        styles.deviceItem,
        selectedAvailableBeacon?.id === item.id && { backgroundColor: '#d3f9d8' },
      ]}
      onPress={() => {
        setSelectedAvailableBeacon(item);
        selectedBeaconRef.current = item; // ✅ Lock the selected beacon
      }}
    >
      <Text style={styles.deviceText}>
        Name: {item.name || 'Unnamed Device'} – ID: {item.id} (RSSI: {item.rssi})
      </Text>
    </Pressable>
  ), [selectedAvailableBeacon]);

  const renderedCircles = useMemo(() => (
    beaconList.map((b, i) => {
      const rssi = b.rssi ?? b.baseRssi ?? -59;
      const distMeters = rssiToDistance(rssi, b.baseRssi);
      const distInGrid = distMeters * metersToGridFactor;
      const radiusPixels = distInGrid * scale;

      return (
        <Circle
          key={`radius-${i}`}
          cx={b.position.x * scale}
          cy={b.position.y * scale}
          r={radiusPixels}
          stroke="rgba(0,0,255,0.3)"
          strokeWidth={1}
          fill="rgba(0,0,255,0.1)"
        />
      );
    })
  ), [beaconList, metersToGridFactor, scale]);

  const renderedPath = useMemo(() => (
    path.length > 1 && path.map((pt, i) => {
      if (i === 0) return null;
      const prev = path[i - 1];
      return (
        <Line
          key={`step-${i}`}
          x1={prev.x * scale + CELL_SIZE / 2}
          y1={prev.y * scale + CELL_SIZE / 2}
          x2={pt.x * scale + CELL_SIZE / 2}
          y2={pt.y * scale + CELL_SIZE / 2}
          stroke="black"
          strokeWidth="2"
        />
      );
    })
  ), [path, scale]);

  return (
    <KeyboardAvoidingView
      style={{ flex: 1 }}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      <View style={styles.container}>
        <Text style={styles.modeIndicator}>Current Mode: {mode.toUpperCase()}</Text>
        <View style={styles.toolbar}>
          <Pressable
            style={[styles.button, mode === 'navigate' && styles.activeButton]}
            onPress={() => setMode('navigate')}
          >
            <Text style={styles.buttonText}>Navigate</Text>
          </Pressable>
          <Pressable
            style={[styles.button, mode === 'edit' && styles.activeButton]}
            onPress={() => setMode('edit')}
          >
            <Text style={styles.buttonText}>Edit</Text>
          </Pressable>
          <Pressable
            style={[styles.button, mode === 'addBeacon' && styles.activeButton]}
            onPress={() => setMode('addBeacon')}
          >
            <Text style={styles.buttonText}>Add Beacon</Text>
          </Pressable>
          <Pressable
            style={styles.button}
            onPress={() => setDynamicPOIs([])}
          >
            <Text style={styles.buttonText}>Clear POIs</Text>
          </Pressable>
        </View>

        {mode === 'edit' && (
          <TextInput
            style={styles.input}
            placeholder="Enter POI name"
            value={poiNameInput}
            onChangeText={setPoiNameInput}
          />
        )}
        {mode === 'addBeacon' && (
          <>
            {beaconList.length === 2 && (
              <View style={styles.calibrationPanel}>
                <Text style={styles.calibrationText}>
                  Enter known distance (meters) between Beacon 1 and Beacon 2:
                </Text>
                <TextInput
                  style={styles.input}
                  placeholder="Distance in meters"
                  value={calibrationInput}
                  onChangeText={setCalibrationInput}
                  keyboardType="numeric"
                />
                <Pressable
                  style={styles.button}
                  onPress={() => {
                    if (beaconList.length < 2) return; // Guard clause to ensure two beacons exist
                    const b1 = beaconList[0].position;
                    const b2 = beaconList[1].position;
                    const dx = b2.x - b1.x;
                    const dy = b2.y - b1.y;
                    const gridDistance = Math.sqrt(dx * dx + dy * dy); // Distance in grid units
                    const knownDistance = parseFloat(calibrationInput);
                    if (knownDistance > 0) {
                      const newMetersToGrid = gridDistance / knownDistance; // Grid units per meter
                      setMetersToGridFactor(newMetersToGrid); // ✅ Correct way
                    }
                  }}
                >
                  <Text style={styles.buttonText}>Calibrate Conversion</Text>
                </Pressable>
              </View>
            )}
            <FlatList
              style={{ flex: 1 }}
              data={
                sortedFilteredDevices.length > 0
                  ? sortedFilteredDevices
                  : [{ id: 'placeholder', name: 'No devices found', rssi: null }]
              }
              keyExtractor={(item) => item.id}
              extraData={selectedAvailableBeacon} // Add extraData to track changes in selectedAvailableBeacon
              keyboardShouldPersistTaps="handled"
              nestedScrollEnabled={true}
              renderItem={renderDeviceItem}
              ListFooterComponent={
                filteredAvailableDevices.length === 0 && <Text>No BLE devices detected.</Text>
              }
            />
          </>
        )}

        <Text style={styles.title}>User Movement with Real BLE Data</Text>
        <Pressable onPress={handleMapPress}>
          <ImageBackground
            source={require('./assets/floorplan.png')}
            style={styles.map}
            resizeMode="stretch"
          >
            <Svg style={StyleSheet.absoluteFill}>
              {/* Render grid and path first */}
              {walkableGrid.map((row, rowIndex) =>
                row.map((cell, colIndex) => (
                  <Rect
                    key={`cell-${rowIndex}-${colIndex}`}
                    x={colIndex * CELL_SIZE}
                    y={rowIndex * CELL_SIZE}
                    width={CELL_SIZE}
                    height={CELL_SIZE}
                    stroke="rgba(0,0,0,0.1)"
                    fill={cell === 0 ? 'rgba(255,0,0,0.3)' : 'transparent'}
                  />
                ))
              )}
              {renderedPath}
              {renderedCircles}
            </Svg>

            {/* Render POIs after SVG so they're on top */}
            {dynamicPOIs.map((poi) => (
              <POIMarker
                key={poi.id}
                poi={poi}
                scale={scale}
                mode={mode}
                onPress={setSelectedPOI}
              />
            ))}
            <View style={[styles.dot, { left: dotX - 10, top: dotY - 10 }]} />
            {renderedBeacons}
          </ImageBackground>
        </Pressable>

        {mode === 'edit' && selectedBeacon && (
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
                setSelectedBeacon(null);
              }}
            >
              <Text style={styles.buttonText}>Delete Beacon</Text>
            </Pressable>
          </View>
        )}

        <Pressable style={styles.button} onPress={restartScan}>
          <Text style={styles.buttonText}>Restart Scanning</Text>
        </Pressable>
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
        {mode === 'edit' && (
          <Pressable style={styles.button} onPress={() => setBeaconList([])}>
            <Text style={styles.buttonText}>Clear Beacons</Text>
          </Pressable>
        )}
      </View>
    </KeyboardAvoidingView>
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
  toolbar: {
    flexDirection: 'row',
    justifyContent: 'center',
    marginBottom: 10
  },
  button: {
    backgroundColor: '#007AFF',
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 8,
    margin: 4
  },
  activeButton: {
    backgroundColor: '#34C759'
  },
  buttonText: {
    color: 'white',
    fontWeight: 'bold'
  },
  input: {
    height: 40,
    borderColor: '#ccc',
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 10,
    marginBottom: 10,
    width: width - 40
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 20
  },
  map: {
    width: width - 40,
    height: width - 40,
    borderWidth: 1,
    borderColor: '#ccc',
    position: 'relative',
    overflow: 'hidden'
  },
  dot: {
    width: 20,
    height: 20,
    borderRadius: 10,
    backgroundColor: 'blue',
    position: 'absolute',
    zIndex: 2
  },
  beacon: {
    width: 16,
    height: 16,
    borderRadius: 8,
    backgroundColor: 'red',
    position: 'absolute',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 2
  },
  beaconLabel: {
    position: 'absolute',
    top: 18,
    fontSize: 10,
    color: '#333'
  },
  poi: {
    width: 32,
    height: 16,
    borderRadius: 8,
    backgroundColor: 'green',
    position: 'absolute',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 3
  },
  poiLabel: {
    position: 'absolute',
    top: 18,
    fontSize: 10,
    color: '#333',
    fontWeight: 'bold',
    flexShrink: 1,
    width: '100%',
    textAlign: 'center'
  },
  editPanel: {
    position: 'absolute',
    bottom: 20,
    left: 20,
    right: 20,
    backgroundColor: '#fff',
    padding: 10,
    borderRadius: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    elevation: 5
  },
  editPanelTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 10
  },
  deviceItem: { padding: 10, borderBottomWidth: 1, borderBottomColor: '#ccc' },
  deviceText: { fontSize: 16 },
  calibrationPanel: {
    padding: 10,
    marginVertical: 10,
    alignItems: 'center',
    width: width - 40,
    backgroundColor: '#f0f0f0',
    borderRadius: 8,
  },
  calibrationText: {
    fontSize: 16,
    marginBottom: 5,
    color: '#333',
  },
});
