import React from 'react';
import { View, Text, Pressable, FlatList, StyleSheet } from 'react-native';

interface Device {
  id: string;
  name: string | null;
  rssi: number | null;
}

interface DeviceListItemProps {
  devices: Device[];
  selectedDevice: Device | null;
  onSelectDevice: (device: Device) => void;
}

export default function DeviceListItem({ devices, selectedDevice, onSelectDevice }: DeviceListItemProps) {
  const renderDeviceItem = ({ item }: { item: Device }) => (
    <Pressable
      style={[
        styles.deviceItem,
        selectedDevice?.id === item.id && { backgroundColor: '#d3f9d8' },
      ]}
      onPress={() => onSelectDevice(item)}
    >
      <Text style={styles.deviceText}>
        Name: {item.name || 'Unnamed Device'} – ID: {item.id} (RSSI: {item.rssi})
      </Text>
    </Pressable>
  );

  return (
    <FlatList
      style={{ flex: 1 }}
      data={devices.length > 0 ? devices : [{ id: 'placeholder', name: 'No devices found', rssi: null }]}
      keyExtractor={(item) => item.id}
      renderItem={renderDeviceItem}
      ListFooterComponent={
        devices.length === 0 && <Text style={styles.noDevicesText}>No BLE devices detected.</Text>
      }
    />
  );
}

const styles = StyleSheet.create({
  deviceItem: {
    padding: 10,
    borderBottomWidth: 1,
    borderBottomColor: '#ccc',
  },
  deviceText: {
    fontSize: 16,
  },
  noDevicesText: {
    textAlign: 'center',
    marginTop: 10,
    fontSize: 14,
    color: '#888',
  },
});
