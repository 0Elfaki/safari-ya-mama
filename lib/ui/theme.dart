import 'package:flutter/material.dart';

import '../core/content.dart';
import '../core/theme/app_colors.dart';

export '../core/theme/app_colors.dart';
export '../core/theme/app_radius.dart';
export '../core/theme/app_spacing.dart';
export '../core/theme/app_theme.dart';
export '../core/theme/app_typography.dart';

/// Warning-level colours, always paired with [levelIcon] and words.
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
