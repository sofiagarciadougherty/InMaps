class Position {
  final double x;
  final double y;

  Position({required this.x, required this.y});
}

class Beacon {
  final String id;
  final String? name;
  int? rssi;
  final int baseRssi; // Reference power at 1m (e.g., -59)
  Position? position;

  Beacon({
    required this.id, 
    this.name, 
    this.rssi, 
    this.baseRssi = -59,
    this.position,
  });

  // Create a copy of this beacon with updated properties
  Beacon copyWith({
    String? id,
    String? name,
    int? rssi,
    int? baseRssi,
    Position? position,
  }) {
    return Beacon(
      id: id ?? this.id,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      baseRssi: baseRssi ?? this.baseRssi,
      position: position ?? this.position,
    );
  }
}