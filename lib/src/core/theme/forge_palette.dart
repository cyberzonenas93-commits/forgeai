import 'package:flutter/material.dart';

class ForgePalette {
  static const background = Color(0xFF06101C);
  static const backgroundSecondary = Color(0xFF0B1728);
  static const shell = Color(0xFF081322);
  static const surface = Color(0xFF122238);
  static const surfaceElevated = Color(0xFF182B45);
  static const surfaceTint = Color(0xFF223858);
  static const border = Color(0xFF284766);
  static const primaryAccent = Color(0xFF38BDF8);
  static const glowAccent = Color(0xFF7DD3FC);
  static const sparkAccent = Color(0xFFF59E0B);
  static const emberAccent = Color(0xFFF97316);
  static const mintAccent = Color(0xFF34D399);
  static const primaryAccentSoft = Color(0x2238BDF8);
  static const glowAccentSoft = Color(0x227DD3FC);
  static const textPrimary = Color(0xFFF7FAFC);
  static const textSecondary = Color(0xFFBCD0E5);
  static const textMuted = Color(0xFF7A90AA);
  static const success = mintAccent;
  static const error = Color(0xFFF87171);
  static const warning = sparkAccent;

  static const backgroundGlow = RadialGradient(
    center: Alignment(-0.15, -0.9),
    radius: 1.4,
    colors: [Color(0x3338BDF8), Color(0x0006101C)],
  );

  static const buttonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryAccent, Color(0xFF0EA5E9)],
  );

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF102641), Color(0xFF1A2F49), Color(0xFF0D1828)],
  );

  static const warmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [sparkAccent, emberAccent],
  );

  static const surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xF0152841), Color(0xE6102033)],
  );
}
