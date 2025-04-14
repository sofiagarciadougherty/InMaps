import React, { useRef, useState, useEffect } from 'react';
import { Pressable, Text, StyleSheet, PanResponder } from 'react-native';

type Props = {
  beacon: {
    id: string;
    position: { x: number; y: number };
  };
  scale: number;
  mode: string;
  isSelected: boolean;
  onSelect: (beacon: any) => void;
  onDragEnd: (beacon: any) => void;
};

function DraggableBeacon({ beacon, scale, mode, isSelected, onSelect, onDragEnd }: Props) {
  // Default position coordinates if beacon.position is undefined
  const defaultPosition = { x: 0, y: 0 };
  
  // Safe initialization of offset state with fallback to defaults
  const [offset, setOffset] = useState(() => {
    if (!beacon?.position) {
      return { x: 0, y: 0 };
    }
    return {
      x: (beacon.position.x || 0) * scale,
      y: (beacon.position.y || 0) * scale
    };
  });
  
  const initialOffset = useRef(offset);

  useEffect(() => {
    // Only update if beacon has a valid position
    if (beacon?.position) {
      const newOffset = { 
        x: (beacon.position.x || 0) * scale, 
        y: (beacon.position.y || 0) * scale 
      };
      setOffset(newOffset);
      initialOffset.current = newOffset;
    }
  }, [beacon?.position?.x, beacon?.position?.y, scale]);

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
        // Create a new beacon with valid position
        onDragEnd({ 
          ...beacon, 
          position: { x: newX, y: newY } 
        });
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
      <Text style={styles.beaconLabel}>{beacon?.id || 'Unknown'}</Text>
    </Pressable>
  );
}

export default React.memo(DraggableBeacon);

const styles = StyleSheet.create({
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
});
