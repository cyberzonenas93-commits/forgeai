import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'forge_palette.dart';

class ForgeAiTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      headlineLarge: GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: ForgePalette.textPrimary,
        height: 1.1,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: ForgePalette.textPrimary,
        height: 1.1,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: ForgePalette.textPrimary,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ForgePalette.textPrimary,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: ForgePalette.textPrimary,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: ForgePalette.textPrimary,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: ForgePalette.textSecondary,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: ForgePalette.textPrimary,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: ForgePalette.textSecondary,
      ),
    );

    final colorScheme = const ColorScheme.dark(
      primary: ForgePalette.primaryAccent,
      onPrimary: Colors.white,
      primaryContainer: ForgePalette.primaryAccentSoft,
      onPrimaryContainer: Colors.white,
      secondary: ForgePalette.glowAccent,
      onSecondary: Colors.white,
      secondaryContainer: ForgePalette.backgroundSecondary,
      onSecondaryContainer: ForgePalette.textPrimary,
      tertiary: ForgePalette.surface,
      onTertiary: ForgePalette.textPrimary,
      error: ForgePalette.error,
      onError: Colors.white,
      surface: ForgePalette.surface,
      onSurface: ForgePalette.textPrimary,
      surfaceContainerHighest: ForgePalette.surfaceElevated,
      onSurfaceVariant: ForgePalette.textSecondary,
      outline: ForgePalette.border,
      outlineVariant: ForgePalette.border,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    return base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ForgePalette.background,
      colorScheme: colorScheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      cardColor: ForgePalette.surface,
      dividerColor: ForgePalette.border,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: const IconThemeData(color: ForgePalette.textPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ForgePalette.background.withValues(alpha: 0.94),
        height: 74,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.selected)
              ? ForgePalette.textPrimary
              : ForgePalette.textSecondary;
          return GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ForgePalette.surfaceElevated,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: ForgePalette.textMuted,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: ForgePalette.textSecondary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ForgePalette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ForgePalette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: ForgePalette.primaryAccent,
            width: 1.2,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: ForgePalette.surfaceElevated,
        selectedColor: ForgePalette.primaryAccentSoft,
        disabledColor: ForgePalette.surface,
        secondarySelectedColor: ForgePalette.primaryAccentSoft,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: textTheme.labelMedium!,
        secondaryLabelStyle: textTheme.labelMedium!.copyWith(
          color: ForgePalette.textPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: ForgePalette.border),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: ForgePalette.backgroundSecondary,
        modalBackgroundColor: ForgePalette.backgroundSecondary,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ForgePalette.backgroundSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    );
  }

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      ForgePalette.background,
      ForgePalette.backgroundSecondary,
      Color(0xFF0A1120),
    ],
  );
}
