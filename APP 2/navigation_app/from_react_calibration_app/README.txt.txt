README.txt  
============

PROJECT: BLE-Enabled Game Functionality Handoff for Flutter Development  
AUTHOR: Derek Price  
DATE: April 2025  

DESCRIPTION:
------------
This package contains the essential files and logic from the React Native app that implements BLE-based positioning and gamified task completion. This functionality is to be ported to Flutter for iOS and Android support. The key features include Bluetooth Low Energy (BLE) scanning, real-time user positioning on a grid map, and proximity-triggered task and reward logic.

This document outlines the architecture, lists all critical files for migration, and provides guidance for replicating the system using Flutter's libraries and paradigms.

-----------------------------------------------
CORE COMPONENTS TO PORT TO FLUTTER:
-----------------------------------------------

1. **Bluetooth (BLE) Scanning**
   - **React Native Module**: `NativeBleScanner.ts`
   - **Flutter Equivalent**: Use `flutter_blue_plus` or `flutter_reactive_ble`
   - **Role**: Manages device scanning, RSSI extraction, and BLE advertisement filtering
   - **Note**: You’ll need to replicate native bridging functionality from scratch in Flutter using available packages.

2. **Data Types and Models**
   - **File**: `types.ts`
   - **Key Interfaces**: `Beacon`, `Coordinate`, `ScanResult`
   - These types will help standardize BLE and positional data in Flutter.

3. **Positioning System**
   - **Key Files**:
     - `useSmoothedPosition.ts`: Converts filtered beacon signals to X,Y coordinates via trilateration
     - `usePositioning.ts` (within `PositioningContext.tsx`): Central manager for live positioning updates
     - `positioning.ts` (in `utils/`): Houses core distance and trilateration math
   - **Core Concepts to Implement in Flutter**:
     - Trilateration with 3+ beacons
     - Real-world distance conversion via RSSI
     - Scaled grid positioning and UI consumption

4. **Signal Processing**
   - **File**: `useDistanceAveraging.ts`
   - **Function**: Applies exponential smoothing to RSSI signals
   - **Flutter Equivalent**: Reimplement smoothing algorithm using Dart timers and state providers

5. **Game Logic**
   - **File**: `useGameProgress.ts`
   - **Role**: Tracks when users approach target POIs and awards them accordingly
   - **Flutter Consideration**: Maintain proximity tracking and task state in a shared provider or bloc

6. **UI Components**
   - **Component**: `MapCanvas.tsx`
   - **Flutter Equivalent**: Use `CustomPainter` to draw beacons, user position, and navigation paths
   - **Task UI**: Recreate list of tasks using `ListView.builder`

-----------------------------------------------
WHAT TO INCLUDE IN THE HANDOFF:
-----------------------------------------------

✅ **Key Files to Share**
- `NativeBleScanner.ts`
- `positioning.ts`
- `useSmoothedPosition.ts`
- `useDistanceAveraging.ts`
- `usePositioning.tsx` (and `PositioningContext.tsx`)
- `useGameProgress.ts`
- `types.ts`

✅ **Algorithm Documentation**
Create a `PositioningAlgorithm.md` file that explains:
- How RSSI values are smoothed (exponential average)
- How distances are derived from RSSI (log-distance path loss model)
- How trilateration is used to find X,Y
- How fallback strategies work (e.g., <3 beacons)

✅ **Architecture Diagram**
Include a diagram showing:
- How BLE signals are scanned
- How they are processed
- How position is calculated
- How UI responds to updates

✅ **Positioning Example Output**
- Annotated screenshot or diagram of a positioning scenario (3 beacons, resulting X/Y)
- Example of raw RSSI values → smoothed RSSI → calculated distances → resolved position

-----------------------------------------------
TECH STACK CONSIDERATIONS FOR FLUTTER TEAM:
-----------------------------------------------
- Use `flutter_blue_plus` or `flutter_reactive_ble` for BLE
- Use `Riverpod`, `Provider`, or `BLoC` for state management
- Replace `Animated` with Flutter’s built-in animation framework
- Replace FlatList with ListView.builder