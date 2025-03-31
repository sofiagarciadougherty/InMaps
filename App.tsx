import React, { useEffect, useState, useRef } from 'react';
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
import { BleManager } from 'react-native-ble-plx';
 
// Initialize the BLE manager
// This will handle Bluetooth Low Energy (BLE) scanning and device management
const bleManager = new BleManager();

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

// Convert RSSI to distance using a simple path-loss model
// txPower is the RSSI at 1 meter distance, pathLossExponent determines how fast the signal decays
// Default txPower is -59 dBm (common for many beacons)
// pathLossExponent is typically between 2 (free space) and 4 (indoor with obstacles)
// A lower pathLossExponent (e.g., 2) means the signal decays slower, resulting in larger distances
// A higher pathLossExponent (e.g., 4) means the signal decays faster, resulting in shorter distances
// The function returns the estimated distance in meters based on the RSSI value
// Note: This is a simplified model and may not be accurate in real-world scenarios
function rssiToDistance(rssi, txPower = -59, pathLossExponent = 2) {
  return Math.pow(10, (txPower - rssi) / (10 * pathLossExponent));
}

// ...existing code...
function getCircleIntersections(x1, y1, r1, x2, y2, r2) {
  const d = Math.hypot(x2 - x1, y1 - y2);
  if (d > r1 + r2 || d < Math.abs(r1 - r2)) {
    const closestX1 = x1 + (r1 * (x2 - x1)) / d;
    const closestY1 = y1 + (r1 * (y2 - y1)) / d;
    const closestX2 = x2 - (r2 * (x2 - x1)) / d;
    const closestY2 = y2 - (r2 * (y2 - y1)) / d;
    return [ { x: (closestX1 + closestX2) / 2, y: (closestY1 + closestY2) / 2 } ];
  }

  const a = (r1 ** 2 - r2 ** 2 + d ** 2) / (2 * d);
  const h = Math.sqrt(r1 ** 2 - a ** 2);
  const xm = x1 + (a * (x2 - x1)) / d;
  const ym = y1 + (a * (y2 - y1)) / d;

  return [
    {
      x: xm + (h * (y2 - y1)) / d,
      y: ym - (h * (x2 - x1)) / d,
    },
    {
      x: xm - (h * (y2 - y1)) / d,
      y: ym + (h * (x2 - x1)) / d,
    },
  ];
}

function trilaterateByIntersections(beacons, metersToGridFactor) {
  const intersections = [];

  for (let i = 0; i < beacons.length; i++) {
    for (let j = i + 1; j < beacons.length; j++) {
      const b1 = beacons[i];
      const b2 = beacons[j];
      const r1 = rssiToDistance(b1.rssi ?? b1.baseRssi) * metersToGridFactor;
      const r2 = rssiToDistance(b2.rssi ?? b2.baseRssi) * metersToGridFactor;

      intersections.push(...getCircleIntersections(
        b1.position.x, b1.position.y, r1,
        b2.position.x, b2.position.y, r2
      ));
    }
  }

  if (intersections.length < 3) {
    // Still try to return a position using whatever intersections you have
    const avg = intersections.reduce((acc, pt) => {
      acc.x += pt.x;
      acc.y += pt.y;
      return acc;
    }, { x: 0, y: 0 });
    return { x: avg.x / intersections.length, y: avg.y / intersections.length };
  }

  // Calculate center of mass for clamping
  const centerOfMass = beacons.reduce((acc, b) => {
    acc.x += b.position.x;
    acc.y += b.position.y;
    return acc;
  }, { x: 0, y: 0 });
  centerOfMass.x /= beacons.length;
  centerOfMass.y /= beacons.length;

  let bestTriplet = null;
  let bestTightness = Infinity;

  for (let i = 0; i < intersections.length - 2; i++) {
    for (let j = i + 1; j < intersections.length - 1; j++) {
      for (let k = j + 1; k < intersections.length; k++) {
        const pts = [intersections[i], intersections[j], intersections[k]];
        const tightness =
          Math.hypot(pts[0].x - pts[1].x, pts[0].y - pts[1].y) +
          Math.hypot(pts[0].x - pts[2].x, pts[0].y - pts[2].y) +
          Math.hypot(pts[1].x - pts[2].x, pts[1].y - pts[2].y);

        // Clamp to focus on triplets near the center of mass
        const avgX = (pts[0].x + pts[1].x + pts[2].x) / 3;
        const avgY = (pts[0].y + pts[1].y + pts[2].y) / 3;
        const distToCenter = Math.hypot(avgX - centerOfMass.x, avgY - centerOfMass.y);

        if (tightness < bestTightness && distToCenter < MAX_DISTANCE) {
          bestTightness = tightness;
          bestTriplet = pts;
        }
      }
    }
  }

  const avg = bestTriplet.reduce((acc, pt) => {
    acc.x += pt.x;
    acc.y += pt.y;
    return acc;
  }, { x: 0, y: 0 });

  return { x: avg.x / 3, y: avg.y / 3 };
}

function multilaterate(beacons, metersToGridFactor) {
  if (beacons.length === 0) return { x: 0, y: 0 };

  if (beacons.length < 3) {
    let best = beacons[0];
    let bestDist = rssiToDistance(best.rssi ?? best.baseRssi);
    beacons.forEach(b => {
      const d = rssiToDistance(b.rssi ?? b.baseRssi);
      if (d < bestDist) {
        best = b;
        bestDist = d;
      }
    });
    return best.position;
  }

  if (beacons.length >= 3) {
    const trilaterated = trilaterateByIntersections(beacons, metersToGridFactor);
    if (trilaterated) return trilaterated;
  }

  // Fallback: Least Squares for 6+ beacons
  const sorted = [...beacons].sort(
    (a, b) =>
      rssiToDistance(a.rssi ?? a.baseRssi) * metersToGridFactor -
      rssiToDistance(b.rssi ?? b.baseRssi) * metersToGridFactor
  );
  const ref = sorted[0];
  const dRef = rssiToDistance(ref.rssi ?? ref.baseRssi) * metersToGridFactor;

  const A = [], B = [];
  for (let i = 1; i < sorted.length; i++) {
    const b = sorted[i];
    const d = rssiToDistance(b.rssi ?? b.baseRssi) * metersToGridFactor;
    A.push([
      2 * (b.position.x - ref.position.x),
      2 * (b.position.y - ref.position.y)
    ]);
    B.push(
      d * d - dRef * dRef -
      (b.position.x * b.position.x - ref.position.x * ref.position.x) -
      (b.position.y * b.position.y - ref.position.y * ref.position.y)
    );
  }

  let sumA00 = 0, sumA01 = 0, sumA11 = 0;
  for (let i = 0; i < A.length; i++) {
    sumA00 += A[i][0] * A[i][0];
    sumA01 += A[i][0] * A[i][1];
    sumA11 += A[i][1] * A[i][1];
  }
  const det = sumA00 * sumA11 - sumA01 * sumA01;
  if (det === 0) return ref.position;

  let sumATB0 = 0, sumATB1 = 0;
  for (let i = 0; i < A.length; i++) {
    sumATB0 += A[i][0] * B[i];
    sumATB1 += A[i][1] * B[i];
  }
  const deltaX = (sumA11 * sumATB0 - sumA01 * sumATB1) / det;
  const deltaY = (-sumA01 * sumATB0 + sumA00 * sumATB1) / det;

  return { x: ref.position.x + deltaX, y: ref.position.y + deltaY };
}

// Draggable beacon component (for moving beacons in EDIT mode)
const DraggableBeacon = React.memo(function DraggableBeacon({ beacon, scale, mode, isSelected, onSelect, onDragEnd }) {
  const [offset, setOffset] = useState({
    x: beacon.position.x * scale,
    y: beacon.position.y * scale
  });
  const initialOffset = useRef(offset);

  useEffect(() => {
    const newOffset = { x: beacon.position.x * scale, y: beacon.position.y * scale };
    setOffset(newOffset);
    initialOffset.current = newOffset;
  }, [beacon.position.x, beacon.position.y, scale]);

  const panResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => mode === 'edit',
      onPanResponderGrant: () => {
        initialOffset.current = { ...offset };
      },
      onPanResponderMove: (evt, gestureState) => {
        const newX = initialOffset.current.x + gestureState.dx;
        const newY = initialOffset.current.y + gestureState.dy;
        setOffset({ x: newX, y: newY });
      },
      onPanResponderRelease: () => {
        const newX = offset.x / scale;
        const newY = offset.y / scale;
        onDragEnd({ ...beacon, position: { x: newX, y: newY } });
      },
      onPanResponderTerminationRequest: () => true
    })
  ).current;

  return (
    <Pressable
      {...(mode === 'edit' ? panResponder.panHandlers : {})}
      onPress={() => {
        if (mode === 'edit') onSelect(beacon);
      }}
      style={[
        styles.beacon,
        {
          left: offset.x - 8,
          top: offset.y - 8,
          borderWidth: isSelected ? 2 : 0,
          borderColor: 'yellow',
        }
      ]}
    >
      <Text style={styles.beaconLabel}>{beacon.id}</Text>
    </Pressable>
  );
});

// ---------------- A* PATHFINDING WITH 8-DIRECTION SUPPORT ---------------- //
function findPath(start, end, grid) {
  const numRows = grid.length;
  const numCols = grid[0].length;

  // 8 directions (including diagonals)
  const directions = [
    [-1, 0], [1, 0], [0, -1], [0, 1],
    [-1, -1], [-1, 1], [1, -1], [1, 1],
  ];

  // Movement cost: diagonal is sqrt(2), straight is 1
  function moveCost(dr, dc) {
    return (dr !== 0 && dc !== 0) ? Math.sqrt(2) : 1;
  }

  // Walkable cell check
  function isWalkable(r, c) {
    return (
      r >= 0 && r < numRows &&
      c >= 0 && c < numCols &&
      grid[r][c] === 1
    );
  }

  // Octile distance heuristic
  function heuristic(r1, c1, r2, c2) {
    const dr = Math.abs(r1 - r2);
    const dc = Math.abs(c1 - c2);
    const D = 1;
    const D2 = Math.sqrt(2);
    return D * (dr + dc) + (D2 - 2 * D) * Math.min(dr, dc);
  }

  // Priority queue can be replaced by a simple array + sort for demonstration
  const openList = [];
  const cameFrom = {};
  const gScore = Array.from({ length: numRows }, () => Array(numCols).fill(Infinity));

  gScore[start.row][start.col] = 0;
  openList.push({
    row: start.row,
    col: start.col,
    f: heuristic(start.row, start.col, end.row, end.col),
  });

  while (openList.length > 0) {
    // Sort to pick the cell with the lowest f
    openList.sort((a, b) => a.f - b.f);
    const current = openList.shift();
    if (!current) break;

    const { row, col } = current;
    if (row === end.row && col === end.col) {
      return reconstructPath(cameFrom, end);
    }

    for (let [dr, dc] of directions) {
      const nr = row + dr;
      const nc = col + dc;
      if (!isWalkable(nr, nc)) continue;

      const step = moveCost(dr, dc);
      const tentativeG = gScore[row][col] + step;
      if (tentativeG < gScore[nr][nc]) {
        cameFrom[`${nr},${nc}`] = { row, col };
        gScore[nr][nc] = tentativeG;
        const fVal = tentativeG + heuristic(nr, nc, end.row, end.col);
        const existing = openList.find(n => n.row === nr && n.col === nc);
        if (existing) {
          existing.f = fVal;
        } else {
          openList.push({ row: nr, col: nc, f: fVal });
        }
      }
    }
  }
  return [];

  function reconstructPath(came, goal) {
    const path = [];
    let curr = goal;
    while (came[`${curr.row},${curr.col}`]) {
      path.push({ x: curr.col, y: curr.row });
      curr = came[`${curr.row},${curr.col}`];
    }
    path.push({ x: curr.col, y: curr.row });
    return path.reverse();
  }
}
// ------------------------------------------------------------------------ //

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
  const [availableDevices, setAvailableDevices] = useState([]);
  const [selectedAvailableBeacon, setSelectedAvailableBeacon] = useState(null); // Track selected detected beacon
  const [conversionFactor, setConversionFactor] = useState(CELL_SIZE);
  const [calibrationInput, setCalibrationInput] = useState('');
  const [metersToGridFactor, setMetersToGridFactor] = useState(1);
  const scale = conversionFactor;
  // User position (x,y in grid units)
  const [position, setPosition] = useState({ x: 0, y: 0 });
  const lastPosition = useRef({ x: 0, y: 0 });

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
  useEffect(() => {
    const startScanning = () => {
      bleManager.startDeviceScan(null, null, (error, device) => {
        if (error) {
          console.log('BLE Scan error:', error);
          return;
        }
  
        if (device && device.id && device.rssi !== null) {
          const now = Date.now();
  
          // Update availableDevices
          setAvailableDevices((prevDevices) => {
            const exists = prevDevices.some(d => d.id === device.id);
            if (exists) {
              return prevDevices.map(d =>
                d.id === device.id
                  ? { ...d, rssi: device.rssi, lastSeen: now }
                  : d
              );
            } else {
              return [...prevDevices, {
                id: device.id, name: device.name, rssi: device.rssi, lastSeen: now
              }];
            }
          });
  
          // Update beaconList
          setBeaconList((prevBeacons) =>
            prevBeacons.map(b =>
              b.id === device.id ? { ...b, rssi: device.rssi } : b
            )
          );
        }
      });
    };
  
    const subscription = bleManager.onStateChange((state) => {
      if (state === 'PoweredOn') {
        startScanning();
      }
    }, true);
  
    startScanning(); // Start scanning immediately if BLE is already powered on
  
    return () => {
      bleManager.stopDeviceScan();
      subscription.remove();
    };
  }, []);
  
  useEffect(() => {
    const STALE_TIMEOUT = 15000; // Increased from 10000 to 15000
    const cleanupInterval = setInterval(() => {
      const now = Date.now();
  
      // Mark stale devices in availableDevices
      setAvailableDevices((prevDevices) =>
        prevDevices.filter(device => now - device.lastSeen < STALE_TIMEOUT)
      );
  
      // Mark stale devices in beaconList
      setBeaconList((prevBeacons) =>
        prevBeacons.map(b => {
          const matchingDevice = availableDevices.find(d => d.id === b.id);
          const isStale = !matchingDevice || now - matchingDevice.lastSeen > STALE_TIMEOUT;
          return {
            ...b,
            rssi: isStale
              ? b.rssi ?? b.baseRssi // Keep last known or base RSSI
              : matchingDevice?.rssi,
          };
        })
      );
    }, 3000); // Check every 3 seconds
  
    return () => clearInterval(cleanupInterval);
  }, [availableDevices]);
  // ----------------------------------------------------------------

  // Compute user position based on beaconList values updated from BLE scanning
  useEffect(() => {
    const interval = setInterval(() => {
      const connected = beaconList.filter(b => b.rssi !== undefined);

      let newPos;
      if (connected.length >= 3) {
        newPos = multilaterate(connected, metersToGridFactor);
      } else if (connected.length > 0) {
        const sorted = connected.sort((a, b) => {
          const da = rssiToDistance(a.rssi !== undefined ? a.rssi : a.baseRssi);
          const db = rssiToDistance(b.rssi !== undefined ? b.rssi : b.baseRssi);
          return da - db;
        });
        newPos = sorted[0].position;
      } else {
        newPos = lastPosition.current;
      }

      const smoothed = {
        x: lastPosition.current.x * (1 - ALPHA) + newPos.x * ALPHA,
        y: lastPosition.current.y * (1 - ALPHA) + newPos.y * ALPHA,
      };
      lastPosition.current = smoothed;
      setPosition(smoothed);
    }, 250); // Update 4x per second for real-time feedback

    return () => clearInterval(interval);
  }, [beaconList]);

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
  function handleMapPress(e) {
    const x = Math.floor(e.nativeEvent.locationX / scale);
    const y = Math.floor(e.nativeEvent.locationY / scale);

    if (mode === 'edit') {
      const tappedPOIIndex = dynamicPOIs.findIndex(p => p.grid.row === y && p.grid.col === x);
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
      if (selectedAvailableBeacon) {
        const newBeacon = {
          id: selectedAvailableBeacon.id,
          name: selectedAvailableBeacon.name,
          rssi: selectedAvailableBeacon.rssi,
          position: { x, y },
          baseRssi: -59, // Default value for RSSI
        };
        setBeaconList([...beaconList, newBeacon]);
        setSelectedAvailableBeacon(null);
        setAvailableDevices((prev) => prev.filter((d) => d.id !== selectedAvailableBeacon.id));
      } else {
        // Optionally, prompt the user to select a beacon first
        console.log('Please select a beacon from the list before placing it on the grid.');
      }
    }
  }

  const dotX = position.x * scale;
  const dotY = position.y * scale;

  const handleAddBeacon = (device) => {
    setBeaconList((prevBeacons) => [
      ...prevBeacons,
      { id: device.id, name: device.name, rssi: device.rssi, position: { x: 0, y: 0 } },
    ]);
  };

  const filteredAvailableDevices = availableDevices.filter(
    (device) => !beaconList.some((beacon) => beacon.id === device.id)
  );

  const sortedFilteredDevices = [...filteredAvailableDevices].sort((a, b) => b.rssi - a.rssi);

  const restartScan = () => {
    bleManager.stopDeviceScan();
    // Restart scanning with the same parameters as before
    bleManager.startDeviceScan(null, null, (error, device) => {
      if (error) {
        console.log('BLE Scan error:', error);
        return;
      }
      if (device && device.id && device.rssi !== null) {
        const now = Date.now();
        setAvailableDevices((prevDevices) => {
          const exists = prevDevices.some(d => d.id === device.id);
          if (exists) {
            return prevDevices.map(d =>
              d.id === device.id ? { ...d, rssi: device.rssi, lastSeen: now } : d
            );
          } else {
            return [...prevDevices, { id: device.id, name: device.name, rssi: device.rssi, lastSeen: now }];
          }
        });
      }
    });
  };

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
              keyboardShouldPersistTaps="handled"
              nestedScrollEnabled={true}
              renderItem={({ item }) => (
                <Pressable
                  style={[
                    styles.deviceItem,
                    selectedAvailableBeacon?.id === item.id && { backgroundColor: '#d3f9d8' },
                  ]}
                  onPress={() => setSelectedAvailableBeacon(item)}
                >
                  <Text style={styles.deviceText}>
                    Name: {item.name || 'Unnamed Device'} – ID: {item.id} (RSSI: {item.rssi})
                  </Text>
                </Pressable>
              )}
              ListFooterComponent={
                filteredAvailableDevices.length === 0 && <Text>No BLE devices detected.</Text>
              }
            />
          </>
        )}

        <Text style={styles.title}>User Movement with Real BLE Data</Text>
        <ImageBackground
          source={require('./assets/floorplan.png')}
          style={styles.map}
          resizeMode="stretch"
        >
          <View style={[styles.dot, { left: dotX - 10, top: dotY - 10 }]} />
          {beaconList.map(b => (
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
                  setEditedBeaconRssi(
                    selected.baseRssi !== undefined
                      ? selected.baseRssi.toString()
                      : '-59' // Default if missing
                  );
                  setEditedBeaconX(selected.position.x?.toString() || '0');
                  setEditedBeaconY(selected.position.y?.toString() || '0');
                }
              }}
              onDragEnd={(updatedB) => {
                setBeaconList(beaconList.map(bc => (bc.id === updatedB.id ? updatedB : bc)));
              }}
            />
          ))}

          {[...pois, ...dynamicPOIs].map((poi) => (
            <Pressable
              key={poi.id}
              onPress={() => setSelectedPOI(poi)}
              style={[
                styles.poi,
                {
                  left: poi.position.x * scale - 8,
                  top: poi.position.y * scale - 8
                }
              ]}
            >
              <Text style={styles.poiLabel}>{poi.name || poi.id}</Text>
            </Pressable>
          ))}

          <Pressable style={StyleSheet.absoluteFill} onPress={handleMapPress}>
            <Svg style={StyleSheet.absoluteFill}>
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
              {path.length > 1 && path.map((pt, i) => {
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
              })}
              {beaconList.map((b, i) => {
                const rssi = b.rssi ?? b.baseRssi ?? -59;
                const distMeters = rssiToDistance(rssi);
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
              })}
            </Svg>
          </Pressable>
        </ImageBackground>

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
                setAvailableDevices((prev) => [
                  ...prev,
                  {
                    id: selectedBeacon.id,
                    name: selectedBeacon.name,
                    rssi: selectedBeacon.rssi,
                  },
                ]); // Re-add deleted beacon to availableDevices
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
              const distance = rssiToDistance(rssi).toFixed(2);
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
