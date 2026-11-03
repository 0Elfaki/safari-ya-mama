import 'package:flutter/material.dart';

import '../core/content.dart';

/// Colour system. Brand palette: forest #22372D (working colour), ochre #C89720, sand #D4B59E,
/// terracotta #D27D56 and rust #8D3F2D (accents only, never as text on white except rust).
/// Red, amber and green are reserved for warning levels so they always mean the same thing.
class C {
  static const bg = Color(0xFFFBF7F3);
  static const surface = Colors.white;
  static const surface2 = Color(0xFFF4ECE5);
  static const ink = Color(0xFF1B2621);
  static const ink2 = Color(0xFF48524C);
  static const ink3 = Color(0xFF636B65);
  static const line = Color(0xFFE5D7CB);
  static const primary = Color(0xFF22372D);
  static const primarySoft = Color(0xFFE4ECE6);
  static const brand = Color(0xFF8D3F2D);
  static const gold = Color(0xFFC89720);
  static const goldSoft = Color(0xFFF8EED5);
  static const sand = Color(0xFFD4B59E);
  static const terracotta = Color(0xFFD27D56);
  static const red = Color(0xFFC62828);
  static const redSoft = Color(0xFFFDECEA);
  static const amber = Color(0xFF8A5200);
  static const amberFill = Color(0xFFF2A93B);
  static const amberSoft = Color(0xFFFFF3D6);
  static const green = Color(0xFF2E7D4F);
  static const greenSoft = Color(0xFFE6F4EA);
}

Color levelColor(Level l) => switch (l) {
  Level.red => C.red,
  Level.amber => C.amber,
  Level.green => C.green,
};
Color levelSoft(Level l) => switch (l) {
  Level.red => C.redSoft,
  Level.amber => C.amberSoft,
  Level.green => C.greenSoft,
};
IconData levelIcon(Level l) => switch (l) {
  Level.red => Icons.emergency,
  Level.amber => Icons.phone_in_talk,
  Level.green => Icons.check_circle_outline,
};

const body = 'Atkinson';
const display = 'Bricolage';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: body,
    colorScheme: ColorScheme.fromSeed(seedColor: C.primary, primary: C.primary, onPrimary: Colors.white, surface: C.surface, error: C.red),
    scaffoldBackgroundColor: C.bg,
  );
  // Four sizes, two weights (24/18/16/14 · 400/700), headings in the display face.
  final t = base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink);
  return base.copyWith(
    textTheme: t.copyWith(
      headlineSmall: const TextStyle(fontFamily: display, fontSize: 24, fontWeight: FontWeight.w700, height: 1.2, color: C.ink),
      titleLarge: const TextStyle(fontFamily: display, fontSize: 18, fontWeight: FontWeight.w700, height: 1.25, color: C.ink),
      titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.3, color: C.ink),
      bodyLarge: const TextStyle(fontSize: 16, height: 1.45, color: C.ink),
      bodyMedium: const TextStyle(fontSize: 14, height: 1.45, color: C.ink2),
      labelLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: C.bg,
      foregroundColor: C.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      titleTextStyle: TextStyle(fontFamily: display, fontSize: 18, fontWeight: FontWeight.w700, color: C.ink),
    ),
    cardTheme: CardThemeData(
      color: C.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.card),
        side: const BorderSide(color: C.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.control)),
        textStyle: const TextStyle(fontFamily: body, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        foregroundColor: C.primary,
        backgroundColor: C.surface,
        side: const BorderSide(color: C.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.control)),
        textStyle: const TextStyle(fontFamily: body, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: C.primary,
        textStyle: const TextStyle(fontFamily: body, fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(color: C.ink2),
      floatingLabelStyle: const TextStyle(color: C.primary, fontWeight: FontWeight.w700),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.control),
        borderSide: const BorderSide(color: C.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.control),
        borderSide: const BorderSide(color: C.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.control),
        borderSide: const BorderSide(color: C.primary, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: C.primarySoft,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(fontFamily: body, fontSize: 12, fontWeight: FontWeight.w700, color: s.contains(WidgetState.selected) ? C.primary : C.ink3),
      ),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? C.primary : C.ink3)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: C.surface,
      selectedColor: C.primarySoft,
      side: const BorderSide(color: C.line),
      labelStyle: const TextStyle(fontFamily: body, fontSize: 14, color: C.ink),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.chip)),
    ),
    dividerTheme: const DividerThemeData(color: C.line, space: 1),
    listTileTheme: const ListTileThemeData(iconColor: C.primary),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.control)),
    ),
  );
}

/// Corner radii: one scale for the whole app so cards, controls and chips line up.
class R {
  static const double card = 16;
  static const double control = 12;
  static const double chip = 10;
}
