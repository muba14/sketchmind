import 'package:flutter/material.dart';

/// Obsidian havasında koyu mor renk paleti.
class AppColors {
  static const bg = Color(0xFF1B1B22);
  static const surface = Color(0xFF23232C);
  static const card = Color(0xFF2A2A35);
  static const cardBar = Color(0xFF342B5C);
  static const border = Color(0xFF3A3A48);
  static const accent = Color(0xFF8B6CF6);
  static const accentSoft = Color(0xFFB7A4FF);
  static const text = Color(0xFFDCDDE3);
  static const muted = Color(0xFF8C8C9E);
  static const highlight = Color(0xFF6B5A14);
  static const highlightText = Color(0xFFF7E9A6);
  static const separator = Color(0xFFE5737D);
  static const code = Color(0xFF33333F);
  static const codeText = Color(0xFFF0A6CA);
  static const tag = Color(0xFF7FD1B9);
  static const done = Color(0xFF5BC97C);
  static const missingLink = Color(0xFF7C6DAF);
  static const star = Color(0xFFF5C542);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    secondary: AppColors.accentSoft,
    onSecondary: Colors.black,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.separator,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.bg,
    dividerColor: AppColors.border,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.25),
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 12, color: AppColors.text),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      showDragHandle: true,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      hintStyle: const TextStyle(color: AppColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: AppColors.surface),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.accent,
      selectionHandleColor: AppColors.accent,
    ),
  );
}

const _months = [
  'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
  'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
];

/// "17 Kas 2026" biçiminde tarih.
String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
