import 'package:flutter/material.dart';
import './sensor_simulator.dart';
import './beacon_simulator.dart';
import './vector2d.dart';

/// A control panel widget for simulator controls in emulator testing
class SimulatorControlPanel extends StatefulWidget {
  final bool showAdvanced;
  
  const SimulatorControlPanel({
    Key? key, 
    this.showAdvanced = false,
  }) : super(key: key);

  @override
  State<SimulatorControlPanel> createState() => _SimulatorControlPanelState();
}

class _SimulatorControlPanelState extends State<SimulatorControlPanel> {
  // Simulators
  final _sensorSim = SensorSimulator();
  final _beaconSim = BeaconSimulator();
  
  // Control state
  bool _continuousSteps = false;
  double _heading = 0;
  
  @override
  void initState() {
    super.initState();
    
    // Set up simulators
    _sensorSim.start();
    _beaconSim.setupDefaultBeacons();
    _beaconSim.start();
  }
  
  @override
  void dispose() {
    _sensorSim.stop();
    _beaconSim.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.all(8),
        color: Colors.black.withOpacity(0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with expand/collapse button
            Row(
              children: [
                const Text(
                  'Simulator Controls',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                  iconSize: 18,
                ),
              ],
            ),
            
            // Basic controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Heading indicator and controls
                Column(
                  children: [
                    Text(
                      'Heading: ${_heading.toStringAsFixed(0)}°',
                      style: const TextStyle(color: Colors.white),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.rotate_left, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _heading = (_heading - 45) % 360;
                              _sensorSim.setHeading(_heading);
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.rotate_right, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _heading = (_heading + 45) % 360;
                              _sensorSim.setHeading(_heading);
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                
                // Continuous mode toggle
                Column(
                  children: [
                    const Text(
                      'Continuous Steps',
                      style: TextStyle(color: Colors.white),
                    ),
                    Switch(
                      value: _continuousSteps,
                      onChanged: (value) {
                        setState(() {
                          _continuousSteps = value;
                          if (_continuousSteps) {
                            _sensorSim.startSteps();
                          } else {
                            _sensorSim.stopSteps();
                          }
                        });
                      },
                      activeColor: Colors.tealAccent,
                    ),
                  ],
                ),
                
                // Step button
                ElevatedButton(
                  onPressed: () {
                    _sensorSim.takeStep();
                    _beaconSim.moveUserInDirection(_heading, 0.7);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                  ),
                  child: const Text('Step'),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Direction controls (D-pad style)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Up button
                _directionButton(
                  Icons.arrow_upward,
                  () {
                    _sensorSim.move(Direction.forward);
                    _beaconSim.moveUserInDirection(_heading, 0.7);
                  },
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Left button
                _directionButton(
                  Icons.arrow_back,
                  () {
                    _sensorSim.move(Direction.left);
                    _beaconSim.moveUserInDirection((_heading - 90) % 360, 0.7);
                  },
                ),
                const SizedBox(width: 50), // Space between buttons
                // Right button
                _directionButton(
                  Icons.arrow_forward,
                  () {
                    _sensorSim.move(Direction.right);
                    _beaconSim.moveUserInDirection((_heading + 90) % 360, 0.7);
                  },
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Down button
                _directionButton(
                  Icons.arrow_downward,
                  () {
                    _sensorSim.move(Direction.backward);
                    _beaconSim.moveUserInDirection((_heading + 180) % 360, 0.7);
                  },
                ),
              ],
            ),
            
            // Advanced controls (if enabled)
            if (widget.showAdvanced) ...[
              const Divider(color: Colors.white30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      _beaconSim.setupDefaultBeacons();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                    ),
                    child: const Text('Reset Beacons'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      // Move to origin
                      _beaconSim.setUserPosition(Vector2D(200, 200));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                    ),
                    child: const Text('Reset Position'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  /// Create a direction control button with specified icon and action
  Widget _directionButton(IconData icon, VoidCallback onPressed) {
    return SizedBox(
      width: 50,
      height: 50,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: Colors.teal.withOpacity(0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}