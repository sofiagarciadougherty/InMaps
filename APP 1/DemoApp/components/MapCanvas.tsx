import React from 'react';
import { View, ImageBackground, Pressable, StyleSheet, Dimensions } from 'react-native';
import Svg, { Rect, Circle, Line } from 'react-native-svg';
import POIMarker from './POIMarker';
import DraggableBeacon from './DraggableBeacon';
import { Beacon, POI } from '../src/types';
import { rssiToDistance } from '../utils/positioning';

interface MapCanvasProps {
  scale: number;
  walkableGrid: number[][];
  beaconList: Beacon[];
  dynamicPOIs: POI[];
  renderedCircles: JSX.Element[];
  renderedPath: JSX.Element[];
  renderedBeacons: JSX.Element[];
  dotX: number;
  dotY: number;
  mode: string;
  onMapPress: (e: GestureResponderEvent) => void;
  onPOIPress: (poi: POI) => void;
}

const { width } = Dimensions.get('window');

const MapCanvas: React.FC<MapCanvasProps> = ({
  scale,
  walkableGrid,
  beaconList,
  dynamicPOIs,
  renderedCircles,
  renderedPath,
  renderedBeacons,
  dotX,
  dotY,
  mode,
  onMapPress,
  onPOIPress,
}) => {
  return (
    <Pressable onPress={onMapPress}>
      <ImageBackground
        source={require('../assets/floorplan.jpg')}
        style={styles.map}
        resizeMode="stretch"
      >
        <Svg style={StyleSheet.absoluteFill}>
          {/* Render grid */}
          {walkableGrid.map((row, rowIndex) =>
            row.map((cell, colIndex) => (
              <Rect
                key={`cell-${rowIndex}-${colIndex}`}
                x={colIndex * scale}
                y={rowIndex * scale}
                width={scale}
                height={scale}
                stroke="rgba(0,0,0,0.1)"
                fill={cell === 0 ? 'rgba(255,0,0,0.3)' : 'transparent'}
              />
            ))
          )}
          {/* Render path and circles */}
          {renderedPath}
          {renderedCircles}
        </Svg>

        {/* Render POIs */}
        {dynamicPOIs.map((poi) => (
          <POIMarker
            key={poi.id}
            poi={poi}
            scale={scale}
            mode={mode}
            onPress={() => onPOIPress(poi)} // Ensure correct POI is passed
          />
        ))}

        {/* Render user position */}
        <View style={[styles.dot, { left: dotX - 10, top: dotY - 10 }]} />

        {/* Render draggable beacons */}
        {renderedBeacons}
      </ImageBackground>
    </Pressable>
  );
};

const styles = StyleSheet.create({
  map: {
    width: width - 40,
    height: width - 40,
    borderWidth: 1,
    borderColor: '#ccc',
    position: 'relative',
    overflow: 'hidden',
  },
  dot: {
    width: 20,
    height: 20,
    borderRadius: 10,
    backgroundColor: 'blue',
    position: 'absolute',
    zIndex: 2,
  },
});

export default MapCanvas;
