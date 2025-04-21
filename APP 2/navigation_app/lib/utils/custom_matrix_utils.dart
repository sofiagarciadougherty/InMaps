import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

class CustomMatrixUtils {
  static Offset transformPoint(Matrix4 transform, Offset point) {
    final Vector3 position = Vector3(point.dx, point.dy, 0.0);
    final Vector3 transformed = transform.perspectiveTransform(position);
    return Offset(transformed.x, transformed.y);
  }
} 