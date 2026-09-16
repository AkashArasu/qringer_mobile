import 'package:flutter/material.dart';

/// Centralized app theme settings and gradients
class AppTheme {
  // Primary green background gradient used across screens
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF0B2E0B),
      Color(0xFF1A3A1A),
      Color(0xFF2D5A2D),
    ],
  );

  // Title text gradient
  static const LinearGradient titleGradient = LinearGradient(
    colors: [
      Colors.green,
      Colors.lightGreen,
      Colors.teal,
    ],
  );

  // Accent button gradient (e.g., primary CTAs)
  static LinearGradient accentGradient({double alpha = 0.8}) => LinearGradient(
        colors: [
          Colors.cyan.withOpacity(alpha),
          Colors.blue.withOpacity(alpha),
        ],
      );
}