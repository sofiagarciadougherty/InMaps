import React from 'react';
import { View, Text, TextInput, Pressable, StyleSheet } from 'react-native';
import { Beacon } from '../src/types';

interface BeaconEditorPanelProps {
  selectedBeacon: Beacon | null;
  setSelectedBeacon: (beacon: BeaconEditorPanelProps['selectedBeacon']) => void;
  beaconList: Beacon[];
  setBeaconList: (list: Beacon[]) => void;
  editedName: string;
  setEditedName: (val: string) => void;
  editedRssi: string;
  setEditedRssi: (val: string) => void;
  editedX: string;
  setEditedX: (val: string) => void;
  editedY: string;
  setEditedY: (val: string) => void;
}

export default function BeaconEditorPanel({
  selectedBeacon,
  setSelectedBeacon,
  beaconList,
  setBeaconList,
  editedName,
  setEditedName,
  editedRssi,
  setEditedRssi,
  editedX,
  setEditedX,
  editedY,
  setEditedY,
}: BeaconEditorPanelProps) {
  if (!selectedBeacon) return null;

  return (
    <View style={styles.editPanel}>
      <Text style={styles.editPanelTitle}>Edit Beacon</Text>
      <TextInput
        style={styles.input}
        value={editedName}
        onChangeText={setEditedName}
        placeholder="Beacon Name"
      />
      <TextInput
        style={styles.input}
        value={editedRssi}
        onChangeText={setEditedRssi}
        placeholder="Base RSSI"
        keyboardType="numeric"
      />
      <TextInput
        style={styles.input}
        value={editedX}
        onChangeText={setEditedX}
        placeholder="Beacon X"
        keyboardType="numeric"
      />
      <TextInput
        style={styles.input}
        value={editedY}
        onChangeText={setEditedY}
        placeholder="Beacon Y"
        keyboardType="numeric"
      />
      <Pressable
        style={styles.button}
        onPress={() => {
          setBeaconList(
            beaconList.map((b) =>
              b.id === selectedBeacon.id
                ? {
                    ...b,
                    id: editedName,
                    baseRssi: isNaN(parseFloat(editedRssi))
                      ? b.baseRssi
                      : parseFloat(editedRssi),
                    position: {
                      x: isNaN(parseFloat(editedX)) ? b.position.x : parseFloat(editedX),
                      y: isNaN(parseFloat(editedY)) ? b.position.y : parseFloat(editedY),
                    },
                  }
                : b
            )
          );
          setSelectedBeacon(null);
        }}
      >
        <Text style={styles.buttonText}>Save Changes</Text>
      </Pressable>
      <Pressable
        style={[styles.button, { backgroundColor: 'red' }]}
        onPress={() => {
          setBeaconList(beaconList.filter((b) => b.id !== selectedBeacon.id));
          setSelectedBeacon(null);
        }}
      >
        <Text style={styles.buttonText}>Delete Beacon</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
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
    elevation: 5,
  },
  editPanelTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 10,
  },
  input: {
    height: 40,
    borderColor: '#ccc',
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 10,
    marginBottom: 10,
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
});
