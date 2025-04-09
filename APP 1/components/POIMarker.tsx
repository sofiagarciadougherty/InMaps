import React from 'react';
import { Pressable, View, Text, StyleSheet, TouchableWithoutFeedback } from 'react-native';

type POIMarkerProps = {
  poi: {
    id: string;
    name: string;
    position: { x: number; y: number };
  };
  scale: number;
  mode: string;
  onPress?: (poi: any) => void;
};

export default function POIMarker({ poi, scale, mode, onPress }: POIMarkerProps) {
  const poiStyle = {
    left: poi.position.x * scale - 16,
    top: poi.position.y * scale - 8,
  };

  const content = (
    <View style={[styles.poi, poiStyle]}>
      <Text style={styles.poiLabel}>{poi.name}</Text>
    </View>
  );

  if (mode === 'navigate') {
    return (
      <TouchableWithoutFeedback onPress={() => onPress?.(poi)}>
        {content}
      </TouchableWithoutFeedback>
    );
  }

  return content;
}

const styles = StyleSheet.create({
  poi: {
    width: 32,
    height: 16,
    borderRadius: 8,
    backgroundColor: 'green',
    position: 'absolute',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 3,
  },
  poiLabel: {
    fontSize: 10,
    color: '#333',
    fontWeight: 'bold',
    textAlign: 'center',
  },
});
