import 'package:flutter/material.dart';

/// Rafik (رفيق) — Core Design System Tokens & Themes
class AppTheme {
  // Brand Colors (Rose Gold & Obsidian Berry)
  static const Color roseGold = Color(0xFFB76E79);
  static const Color roseGoldLight = Color(0xFFE8B4B8);
  static const Color roseGoldShimmer = Color(0xFFFCE4E6);
  static const Color berryCore = Color(0xFF7A1F3D);
  static const Color berryDark = Color(0xFF4A1226);

  // Surface Colors
  static const Color darkBg = Color(0xFF12080C);
  static const Color darkCard = Color(0xFF1A0D12);
  static const Color darkBorder = Color(0xFF2C151F);

  static const Color lightBg = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFDF9FA);
  static const Color lightBorder = Color(0xFFEAC7CD);

  // Status & Safety Colors
  static const Color sageSafe = Color(0xFF3E7A54);
  static const Color alertSos = Color(0xFFC23B3B);

  // Typography Colors
  static const Color textPrimary = Color(0xFFFCE4E6);
  static const Color textSecondary = Color(0xFFB09CA3);

  /// Dark Theme Configuration (Primary Sleek Obsidian)
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      primaryColor: roseGold,
      colorScheme: const ColorScheme.dark(
        primary: roseGold,
        secondary: roseGoldLight,
        surface: darkCard,
        error: alertSos,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBg,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: roseGoldLight),
        titleTextStyle: TextStyle(
          color: Color(0xFFFCE4E6),
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkBorder),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: roseGold,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: roseGold, width: 1.5),
        ),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
      ),
    );
  }

  /// Light Theme Configuration (Crisp Pure White)
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBg,
      primaryColor: roseGold,
      colorScheme: const ColorScheme.light(
        primary: roseGold,
        secondary: berryCore,
        surface: lightCard,
        error: alertSos,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBg,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: berryCore),
        titleTextStyle: TextStyle(
          color: berryCore,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: lightBorder),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: roseGold,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: roseGold, width: 1.5),
        ),
        hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.4), fontSize: 13),
      ),
    );
  }
}
