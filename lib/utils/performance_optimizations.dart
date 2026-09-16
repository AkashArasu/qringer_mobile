import 'package:flutter/material.dart';

/// Performance optimization utilities for the QROnly app
class PerformanceOptimizations {
  
  /// Optimized container with reduced shadow calculations
  static Widget optimizedContainer({
    required Widget child,
    Color? color,
    BorderRadius? borderRadius,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double? width,
    double? height,
    bool enableShadow = false,
  }) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        boxShadow: enableShadow ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ] : null,
      ),
      child: child,
    );
  }

  /// Fast gradient container without expensive calculations
  static Widget fastGradientContainer({
    required Widget child,
    required List<Color> colors,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    BorderRadius? borderRadius,
  }) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }

  /// Optimized button with minimal rebuilds
  static Widget fastButton({
    required VoidCallback onPressed,
    required Widget child,
    Color? backgroundColor,
    Color? foregroundColor,
    EdgeInsetsGeometry? padding,
    BorderRadius? borderRadius,
  }) {
    return Material(
      color: backgroundColor ?? Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onPressed,
        borderRadius: borderRadius,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(12),
          child: child,
        ),
      ),
    );
  }

  /// Disable animations for better performance on slower devices
  static void disableAnimationsIfNeeded() {
    // This can be called in main() to disable animations on slower devices
    // You can add device detection logic here if needed
  }

  /// Optimized list tile for better scrolling performance
  static Widget fastListTile({
    required Widget title,
    Widget? subtitle,
    Widget? leading,
    Widget? trailing,
    VoidCallback? onTap,
    EdgeInsetsGeometry? contentPadding,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: contentPadding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (leading != null) ...[
                leading,
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    title,
                    if (subtitle != null) subtitle,
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 16),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Optimized colors for better performance
class OptimizedColors {
  // Pre-calculated colors to avoid runtime calculations
  static const Color primaryGreen = Color(0xFF4CAF50);
  static const Color darkNavy = Color(0xFF0D1B2A);
  static const Color mediumNavy = Color(0xFF1B263B);
  static const Color lightGreen = Color(0xFF81C784);
  
  // Pre-calculated alpha colors
  static const Color blackOverlay20 = Color(0x33000000);
  static const Color blackOverlay40 = Color(0x66000000);
  static const Color blackOverlay60 = Color(0x99000000);
  static const Color whiteOverlay10 = Color(0x1AFFFFFF);
  static const Color whiteOverlay20 = Color(0x33FFFFFF);
  static const Color whiteOverlay30 = Color(0x4DFFFFFF);
  
  static const Color greenOverlay20 = Color(0x334CAF50);
  static const Color greenOverlay30 = Color(0x4D4CAF50);
  static const Color redOverlay20 = Color(0x33F44336);
  static const Color redOverlay90 = Color(0xE6F44336);
}