class Position {
  final double x;
  final double y;

  Position({required this.x, required this.y});
}

class Beacon {
  final String id;
  final String name;
  final int? rssi;
  final int baseRssi;
  final Position? position;
  final int lastUpdated;  // Timestamp in milliseconds
  final bool isActive;    // Whether this beacon should be used for positioning

  Beacon({
    required this.id,
    required this.name,
    this.rssi,
    this.baseRssi = -59,
    this.position,
    int? lastUpdated,
    this.isActive = true,
  }) : this.lastUpdated = lastUpdated ?? DateTime.now().millisecondsSinceEpoch;

  // Create a copy with updated properties
  Beacon copyWith({
    String? id,
    String? name,
    int? rssi,
    int? baseRssi,
    Position? position,
    int? lastUpdated,
    bool? isActive,
  }) {
    return Beacon(
      id: id ?? this.id,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      baseRssi: baseRssi ?? this.baseRssi,
      position: position ?? this.position,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isActive: isActive ?? this.isActive,
    );
  }

  // Check if beacon data is stale (older than threshold)
  bool isStale(int staleThresholdMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - lastUpdated > staleThresholdMs;
  }

  // Calculate age in milliseconds
  int getAgeMs() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - lastUpdated;
  }

  @override
  String toString() {
    return 'Beacon{id: $id, rssi: $rssi, pos: (${position?.x}, ${position?.y})}';
  }
}