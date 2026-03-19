import 'package:flutter/material.dart';

class ForgePalette {
  static const background = Color(0xFF0B0B0B);
  static const backgroundSecondary = Color(0xFF111827);
  static const surface = Color(0xFF1F2937);
  static const surfaceElevated = Color(0xFF0F172A);
  static const border = Color(0xFF2A2A2A);
  static const primaryAccent = Color(0xFF3B82F6);
  static const glowAccent = Color(0xFF60A5FA);
  static const primaryAccentSoft = Color(0x33256DDF);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9CA3AF);
  static const textMuted = Color(0xFF6B7280);
  static const success = Color(0xFF22C55E);
  static const error = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);

  static const backgroundGlow = RadialGradient(
    center: Alignment.topCenter,
    radius: 1.3,
    colors: [Color(0x221E40AF), Color(0x000B0B0B)],
  );

  static const buttonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryAccent, glowAccent],
  );
}
