import 'package:flutter/material.dart';

/// Safari ya Mama colour tokens. The only place a colour is defined.
/// One accent: Forest Green carries every primary action, active state and progress.
/// Terracotta is decoration only (illustration fields, chart lines), never a button.
/// Success / warning / emergency are reserved for warning levels, and a level is never
/// shown by colour alone (icon + words every time).
abstract final class AppColors {
  static const primary = Color(0xFF174D3A); // Primary Forest Green
  static const secondary = Color(0xFF72947A); // Secondary Sage
  static const primarySoft = Color(0xFFEAF1E9); // Light Sage
  static const primaryDeep = Color(0xFF0E3226); // hero cards: same green, deeper
  static const onPrimaryMuted = Color(0xCCFFFFFF); // secondary text on green (80% white)
  static const bg = Color(0xFFF4F0E6); // Warm Ivory
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF7F4ED);
  static const accent = Color(0xFFD98B68); // Terracotta
  static const accentSoft = Color(0xFFF8E7DE);
  static const ink = Color(0xFF202C25); // Primary text
  static const ink2 = Color(0xFF58655D); // Secondary text (5.4:1 on the background, 6.1:1 on white)
  static const ink3 = Color(0xFF5E6B63); // Tertiary text / icons (4.9:1 on the background and soft green)
  static const line = Color(0xFFE4E5DC); // Border
  static const disabled = Color(0xFFA9B0AA);
  static const green = Color(0xFF287347); // Success
  static const greenSoft = Color(0xFFE8F2E9);
  static const amber = Color(0xFFA36B18); // Warning
  static const amberSoft = Color(0xFFFFF1D7);
  static const red = Color(0xFFAD3831); // Emergency
  static const redSoft = Color(0xFFFBE9E7);

  // Aliases kept for older call sites.
  static const brand = accent;
  static const amberFill = amber;
}

/// Short name used across the screens.
typedef C = AppColors;
