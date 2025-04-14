import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import MainScreen from './screens/MainScreen';
import GameScreen from './screens/GameScreen'; // Import GameScreen
import { PositioningProvider } from './contexts/PositioningContext'; // Import the provider

const Stack = createNativeStackNavigator();

export default function App() {
  return (
    <PositioningProvider>
      <NavigationContainer>
        <Stack.Navigator initialRouteName="Main">
          <Stack.Screen name="Main" component={MainScreen} options={{ headerShown: false }} />
          <Stack.Screen name="Game" component={GameScreen} /> 
        </Stack.Navigator>
      </NavigationContainer>
    </PositioningProvider>
  );
}
