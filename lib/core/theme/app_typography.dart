import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Body text: Inter. Headings: Manrope.
const body = 'Inter';
const display = 'Manrope';

/// Type scale: Display 32 · H1 28 · H2 24 · H3 20 · Body large 16 · Body 14 · Caption 12.
/// Mapped onto Material roles so Theme.of(context).textTheme carries it everywhere:
///   displaySmall = Display, headlineMedium = H1, headlineSmall = H2, titleLarge = H3,
///   titleMedium = body-large emphasis, bodyLarge = Body large, bodyMedium = Body, bodySmall/labelSmall = Caption.
abstract final class AppTypography {
  static const _h = TextStyle(fontFamily: display, color: AppColors.ink, letterSpacing: -0.2);

  static final displayL = _h.copyWith(fontSize: 32, fontWeight: FontWeight.w800, height: 1.15);
  static final h1 = _h.copyWith(fontSize: 28, fontWeight: FontWeight.w800, height: 1.2);
  static final h2 = _h.copyWith(fontSize: 24, fontWeight: FontWeight.w800, height: 1.25);
  static final h3 = _h.copyWith(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3);
  static const bodyLargeStrong = TextStyle(fontFamily: body, fontSize: 16, fontWeight: FontWeight.w600, height: 1.4, color: AppColors.ink);
  static const bodyLarge = TextStyle(fontFamily: body, fontSize: 16, height: 1.5, color: AppColors.ink);
  static const bodyText = TextStyle(fontFamily: body, fontSize: 14, height: 1.5, color: AppColors.ink);
  static const caption = TextStyle(fontFamily: body, fontSize: 12, height: 1.4, color: AppColors.ink2);
  static const label = TextStyle(fontFamily: body, fontSize: 12, fontWeight: FontWeight.w600, height: 1.3, color: AppColors.ink2, letterSpacing: 0.2);
  static const button = TextStyle(fontFamily: body, fontSize: 16, fontWeight: FontWeight.w600);

  static TextTheme textTheme(TextTheme base) => base.copyWith(
    displaySmall: displayL,
    headlineMedium: h1,
    headlineSmall: h2,
    titleLarge: h3,
    titleMedium: bodyLargeStrong,
    bodyLarge: bodyLarge,
    bodyMedium: bodyText,
    bodySmall: caption,
    labelLarge: button,
    labelSmall: label,
  );
}
