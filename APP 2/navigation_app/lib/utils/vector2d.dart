import 'dart:math';

/// 2D Vector representation for positioning and calculations
class Vector2D {
  final double x;
  final double y;
  
  /// Create a vector with x,y coordinates
  const Vector2D(this.x, this.y);
  
  /// Create a vector from angle (degrees) and magnitude
  factory Vector2D.fromAngle(double angleDegrees, double magnitude) {
    final angleRadians = angleDegrees * pi / 180.0;
    return Vector2D(
      magnitude * cos(angleRadians),
      magnitude * sin(angleRadians),
    );
  }
  
  /// Creates a vector from an angle (in degrees) and magnitude
  static Vector2D fromPolar(double angleDegrees, double magnitude) {
    final angleRadians = angleDegrees * (3.1415926535 / 180.0);
    return Vector2D(
      magnitude * cos(angleRadians),
      magnitude * sin(angleRadians),
    );
  }
  
  /// Create a vector from a Map with 'x' and 'y' keys
  factory Vector2D.fromMap(Map<String, dynamic> map) {
    return Vector2D(
      map['x']?.toDouble() ?? 0.0,
      map['y']?.toDouble() ?? 0.0,
    );
  }
  
  /// Make a copy of this vector
  Vector2D copy() {
    return Vector2D(x, y);
  }
  
  /// Convert to Map representation
  Map<String, double> toMap() {
    return {'x': x, 'y': y};
  }
  
  /// Return the magnitude (length) of the vector
  double get magnitude => sqrt(x * x + y * y);
  
  /// Return the angle in degrees (0-360)
  double get angleDegrees {
    final angle = atan2(y, x) * 180.0 / pi;
    return angle < 0 ? angle + 360.0 : angle;
  }
  
  /// Return a normalized vector (length of 1)
  Vector2D get normalized {
    final len = magnitude;
    if (len > 0) {
      return Vector2D(x / len, y / len);
    }
    return const Vector2D(0, 0);
  }
  
  /// Add two vectors
  Vector2D operator +(Vector2D other) {
    return Vector2D(x + other.x, y + other.y);
  }
  
  /// Subtract a vector
  Vector2D operator -(Vector2D other) {
    return Vector2D(x - other.x, y - other.y);
  }
  
  /// Scale vector by a factor
  Vector2D operator *(double factor) {
    return Vector2D(x * factor, y * factor);
  }
  
  /// Divide vector by a factor
  Vector2D operator /(double divisor) {
    if (divisor == 0) {
      throw ArgumentError('Cannot divide by zero');
    }
    return Vector2D(x / divisor, y / divisor);
  }
  
  /// Calculate the dot product of two vectors
  double dot(Vector2D other) {
    return x * other.x + y * other.y;
  }
  
  /// Calculate distance between two points
  static double distance(Vector2D a, Vector2D b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
  }
  
  /// Linearly interpolate between two vectors
  static Vector2D lerp(Vector2D a, Vector2D b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    
    return Vector2D(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
    );
  }
  
  /// Return the string representation of this vector
  @override
  String toString() => 'Vector2D(x: $x, y: $y)';
  
  /// Equality operator
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Vector2D && 
           other.x == x && 
           other.y == y;
  }
  
  @override
  int get hashCode => Object.hash(x, y);
}