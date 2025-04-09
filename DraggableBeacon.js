// DraggableBeacon.js
import React, { useEffect, useState, useRef } from 'react';
import { Pressable, Text, PanResponder, StyleSheet } from 'react-native';

export default function DraggableBeacon({ beacon, scale, mode, isSelected, onSelect, onDragEnd }) {
  const [offset, setOffset] = useState({
    x: beacon.position.x * scale,
    y: beacon.position.y * scale,
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
      onPanResponderTerminationRequest: () => true,
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
        },
      ]}
    >
      <Text style={styles.beaconLabel}>{beacon.id}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  beacon: {
    width: 16,
    height: 16,
    borderRadius: 8,
    backgroundColor: 'red',
    position: 'absolute',
    alignItems: 'center',
    justifyContent: 'center',
  },
  beaconLabel: {
    position: 'absolute',
    top: 18,
    fontSize: 10,
    color: '#333',
  },
});
