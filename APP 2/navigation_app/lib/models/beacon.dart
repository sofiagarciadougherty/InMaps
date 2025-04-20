import 'dart:math';
import '../utils/vector2d.dart';

class Position {
  final double x;
  final double y;

  Position({required this.x, required this.y});

  static double distance(Position a, Position b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
  }
}

class Beacon {
  final String id;
  final String? name;
  final int? rssi;
  final int baseRssi;
  final Vector2D? position;

  Beacon({
    required this.id,
    this.name,
    this.rssi,
    required this.baseRssi,
    required this.position,
  });
}