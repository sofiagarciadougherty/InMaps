import React from 'react';
import { View, Pressable, Text, StyleSheet } from 'react-native';

interface ToolbarProps {
  mode: string;
  setMode: (mode: string) => void;
  onClearPOIs: () => void;
}

export default function Toolbar({ mode, setMode, onClearPOIs }: ToolbarProps) {
  return (
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
      <Pressable style={styles.button} onPress={onClearPOIs}>
        <Text style={styles.buttonText}>Clear POIs</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  toolbar: {
    flexDirection: 'row',
    justifyContent: 'center',
    marginBottom: 10,
  },
  button: {
    backgroundColor: '#007AFF',
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 8,
    margin: 4,
  },
  activeButton: {
    backgroundColor: '#34C759',
  },
  buttonText: {
    color: 'white',
    fontWeight: 'bold',
  },
});
