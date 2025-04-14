import React from 'react';
import { View, Text, TextInput, Pressable, StyleSheet } from 'react-native';
import { Beacon } from '../src/types';
import { usePositioning } from '../contexts/PositioningContext'; // Import context

interface CalibrationPanelProps {
  beaconList: Beacon[];
  calibrationInput: string;
  setCalibrationInput: (val: string) => void;
  onCalibrate: (meters: number) => void;
}

const CalibrationPanel: React.FC<CalibrationPanelProps> = ({
  beaconList,
  calibrationInput,
  setCalibrationInput,
  onCalibrate,
}) => {
  const { setMetersToGridFactor } = usePositioning(); // Access setter

  return (
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
          if (beaconList.length < 2) return;
          const knownDistance = parseFloat(calibrationInput);
          const measuredRSSIValue = 1; // Replace with actual measured RSSI value
          const factor = knownDistance / measuredRSSIValue; // Compute factor
          setMetersToGridFactor(factor); // Store globally
          onCalibrate(knownDistance);
        }}
      >
        <Text style={styles.buttonText}>Calibrate Conversion</Text>
      </Pressable>
    </View>
  );
};

const styles = StyleSheet.create({
  calibrationPanel: {
    padding: 10,
    marginVertical: 10,
    alignItems: 'center',
    backgroundColor: '#f0f0f0',
    borderRadius: 8,
  },
  calibrationText: {
    fontSize: 16,
    marginBottom: 5,
    color: '#333',
  },
  input: {
    height: 40,
    borderColor: '#ccc',
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 10,
    marginBottom: 10,
    width: '100%',
  },
  button: {
    backgroundColor: '#007AFF',
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 8,
  },
  buttonText: {
    color: 'white',
    fontWeight: 'bold',
  },
});

export default CalibrationPanel;
