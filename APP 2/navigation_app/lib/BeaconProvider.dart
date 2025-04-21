import 'package:flutter/material.dart';
import './models/beacon.dart';

class BeaconProvider extends ChangeNotifier {
  List<Beacon> _beacons = [];
  List<Beacon> get beacons => _beacons;

  void updateBeacons(List<Beacon> newBeacons) {
    _beacons = newBeacons;
    notifyListeners();
  }
}
