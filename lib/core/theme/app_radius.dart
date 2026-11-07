/// Corner radii, one rule for the whole app:
/// small 8 (tags, small icons) · medium 12 (buttons, inputs, icon tiles) · large 16 (cards) ·
/// extra large 20 (hero cards, sheets) · pill (chips, badges, the emergency shortcut).
abstract final class AppRadius {
  static const double small = 8, medium = 12, large = 16, xlarge = 20, pill = 999;

  // Roles
  static const double card = large;
  static const double control = medium;
  static const double input = medium;
  static const double chip = pill;
}

typedef R = AppRadius;
