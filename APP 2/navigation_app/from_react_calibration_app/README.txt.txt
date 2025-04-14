README.txt  
============

PROJECT: Game Functionality Port from React Native to Flutter  
AUTHOR: Derek Price  
DATE: April 2025  

DESCRIPTION:
------------
This folder contains the core game logic implemented in React Native, which is intended to be ported to a Flutter-based mobile application for both iOS and Android. The purpose is to enable my team to replicate the proximity-based task and reward system originally developed for our BLE indoor navigation app.

KEY COMPONENTS TO PORT:
-----------------------
1. **Positioning System**
   - React Native Logic: `useSmoothedPosition.ts`, `usePositioning.ts`
   - Flutter Equivalent:
     - Use `flutter_blue_plus` for BLE scanning
     - Rewrite signal processing and distance estimation
     - Use Provider, Riverpod, or BLoC for state management

2. **Game Mechanics**
   - React Native Logic: `useGameProgress.ts`
   - Flutter Tasks:
     - Recreate proximity detection and reward tracking
     - Maintain local state and progress tracking

3. **UI Components**
   - React Native Logic: `MapCanvas.tsx`, FlatList-based task display
   - Flutter Tasks:
     - Use `CustomPainter` for grid map and beacon visuals
     - Use `ListView.builder` for dynamic task lists
     - Draw navigation paths and visited points with Flutter’s drawing tools

MIGRATION STRATEGY:
--------------------
1. **BLE Scanning**  
   - Replace React Native BLE logic with Flutter BLE plugin (`flutter_blue_plus`)
   - Implement device discovery, RSSI filtering, and connection management

2. **State Management**  
   - Replace React `useState` and `useEffect` with Flutter’s Provider or Riverpod
   - Ensure caching and averaging logic is optimized

3. **Drawing & UI**  
   - Reimplement map and beacons using `CustomPainter`
   - Maintain grid-based positioning logic
   - Rebuild scan debug panel and task list

4. **Game Logic**  
   - Port A* pathfinding (if needed)
   - Port reward and proximity checking logic in Dart


ADDITIONAL NOTES:
------------------
- Game logic is framework-agnostic; conceptual mapping is direct, but implementation details differ significantly between React Native and Flutter.
- This code is designed to be modular and readable to make porting straightforward.
- Test on both platforms early, especially BLE behavior, which can vary between iOS and Android.

CONTACT:
--------
Derek Price  
derek.price@gatech.edu  
If any questions arise, feel free to reach out.
