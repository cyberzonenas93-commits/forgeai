import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'forge_palette.dart';

class ForgeAiTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .copyWith(
          headlineLarge: GoogleFonts.spaceGrotesk(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: ForgePalette.textPrimary,
            height: 1.02,
          ),
          headlineMedium: GoogleFonts.spaceGrotesk(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: ForgePalette.textPrimary,
            height: 1.05,
          ),
          titleLarge: GoogleFonts.spaceGrotesk(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: ForgePalette.textPrimary,
            height: 1.1,
          ),
          titleMedium: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: ForgePalette.textPrimary,
            height: 1.2,
          ),
          bodyLarge: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: ForgePalette.textPrimary,
            height: 1.5,
          ),
          bodyMedium: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: ForgePalette.textPrimary,
            height: 1.5,
          ),
          bodySmall: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: ForgePalette.textSecondary,
            height: 1.45,
          ),
          labelLarge: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: ForgePalette.textPrimary,
            letterSpacing: 0.1,
          ),
          labelMedium: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ForgePalette.textSecondary,
            letterSpacing: 0.2,
          ),
        );

    final colorScheme = const ColorScheme.dark(
      primary: ForgePalette.primaryAccent,
      onPrimary: Colors.white,
      primaryContainer: ForgePalette.primaryAccentSoft,
      onPrimaryContainer: Colors.white,
      secondary: ForgePalette.sparkAccent,
      onSecondary: ForgePalette.background,
      secondaryContainer: ForgePalette.glowAccentSoft,
      onSecondaryContainer: ForgePalette.textPrimary,
      tertiary: ForgePalette.surfaceElevated,
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
      dividerColor: ForgePalette.border.withValues(alpha: 0.6),
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
        backgroundColor: Colors.transparent,
        height: 74,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: ForgePalette.primaryAccentSoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.selected)
              ? ForgePalette.textPrimary
              : ForgePalette.textSecondary;
          return GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        useIndicator: true,
        indicatorColor: ForgePalette.primaryAccentSoft,
        selectedIconTheme: const IconThemeData(color: ForgePalette.textPrimary),
        unselectedIconTheme: IconThemeData(
          color: ForgePalette.textSecondary.withValues(alpha: 0.8),
        ),
        selectedLabelTextStyle: textTheme.labelMedium,
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: ForgePalette.textMuted,
        ),
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
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: ForgePalette.border.withValues(alpha: 0.8),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: ForgePalette.border.withValues(alpha: 0.8),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: ForgePalette.primaryAccent,
            width: 1.4,
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
          side: BorderSide(color: ForgePalette.border.withValues(alpha: 0.7)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ForgePalette.primaryAccent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ForgePalette.textSecondary,
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: ForgePalette.backgroundSecondary,
        modalBackgroundColor: ForgePalette.backgroundSecondary,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ForgePalette.backgroundSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return ForgePalette.primaryAccent;
          }
          return ForgePalette.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return ForgePalette.primaryAccentSoft;
          }
          return ForgePalette.surfaceTint;
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ForgePalette.surfaceElevated,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      ForgePalette.background,
      ForgePalette.backgroundSecondary,
      Color(0xFF112845),
    ],
  );
}
