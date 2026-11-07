import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/content_assets.dart';
import 'content_widgets.dart';

import 'package:flutter_tts/flutter_tts.dart';

import '../core/content.dart';
import '../core/tx.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/status_badge.dart';
import 'theme.dart';

export '../core/widgets/app_button.dart';
export '../core/widgets/app_card.dart';
export '../core/widgets/app_header.dart';
export '../core/widgets/app_scaffold.dart';
export '../core/widgets/app_text_field.dart';
export '../core/widgets/emergency_shortcut.dart';
export '../core/widgets/offline_indicator.dart';
export '../core/widgets/state_views.dart';
export '../core/widgets/status_badge.dart';

extension Ctx on BuildContext {
  AppState get app => AppScope.of(this);
  AppState get appRead => AppScope.read(this);

  /// Inline bilingual string: both languages sit side by side in the code (NF-09).
  String t(String en, String sw) => AppScope.of(this).lang == 'sw' ? sw : en;
  String tx(Tx t) => t.of(AppScope.of(this).lang);
}

/// Read-aloud with the phone's own voice (works offline once the voice is installed).
class Speaker {
  static final _tts = FlutterTts();
  static Future<void> say(String text, String lang) async {
    try {
      await _tts.stop();
      await _tts.setLanguage(lang == 'sw' ? 'sw-KE' : 'en-GB');
      await _tts.setSpeechRate(0.45);
      await _tts.speak(text);
    } catch (_) {
      // no voice on this phone: reading still works
    }
  }

  static Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

class ListenButton extends StatelessWidget {
  final String text;
  const ListenButton(this.text, {super.key});
  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: context.t('Listen', 'Sikiliza'),
    onPressed: () => Speaker.say(text, context.appRead.lang),
    icon: const Icon(Icons.volume_up_rounded),
  );
}

class Pad extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  const Pad({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 32)});
  @override
  Widget build(BuildContext context) => ListView(padding: padding, children: children);
}

class Gap extends StatelessWidget {
  final double h;
  const Gap([this.h = 16, Key? key]) : super(key: key);
  @override
  Widget build(BuildContext context) => SizedBox(height: h);
}

/// A row in a list: leading icon tile, title, subtitle, trailing.
class Row2 extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color tint;
  const Row2({super.key, required this.icon, required this.title, this.sub, this.trailing, this.onTap, this.tint = C.primary});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: tint.withValues(alpha: .10), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: tint, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (sub != null) Text(sub!, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            ?trailing,
            if (trailing == null && onTap != null) const Icon(Icons.chevron_right, color: C.ink3),
          ],
        ),
      ),
    ),
  );
}

/// Placeholder for a lesson picture that has not been delivered yet: one icon from the app's
/// icon set on a soft tile (the old drawings were removed). Danger steps carry a red or amber badge.
class Illus extends StatelessWidget {
  final String art;
  final Level? warn;
  final double height;
  final Color background;
  const Illus(this.art, {super.key, this.warn, this.height = 160, this.background = C.primarySoft});

  static IconData iconFor(String art) => switch (art) {
    'alert' => Icons.warning_amber_rounded,
    'headache' => Icons.sick_outlined,
    'clinic' => Icons.local_hospital_outlined,
    'phone' => Icons.call_outlined,
    'bus' => Icons.directions_bus_outlined,
    'talk' => Icons.forum_outlined,
    'bag' => Icons.luggage_outlined,
    'mother_belly' => Icons.pregnant_woman,
    'lie_left' => Icons.hotel_outlined,
    'calendar' => Icons.calendar_month_outlined,
    'clock' => Icons.schedule,
    'plate' || 'greens' || 'fish' || 'fruit' => Icons.restaurant,
    'bowl' => Icons.rice_bowl_outlined,
    'pill' => Icons.medication_outlined,
    'glass' => Icons.local_drink_outlined,
    'cloud' => Icons.cloud_outlined,
    'mother_baby' || 'baby_hat' || 'baby_back' => Icons.child_care,
    'breastfeed' || 'latch' => Icons.favorite_border,
    'thermo' => Icons.thermostat,
    'hands' => Icons.clean_hands_outlined,
    'cord' => Icons.healing_outlined,
    'net' => Icons.bed_outlined,
    _ => Icons.menu_book_outlined,
  };

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(R.medium)),
    child: Stack(
      children: [
        Center(
          child: Icon(iconFor(art), size: (height * .42).clamp(24, 64).toDouble(), color: C.primary.withValues(alpha: .75)),
        ),
        if (warn != null)
          Positioned(
            right: 8,
            top: 8,
            child: CircleAvatar(
              radius: 13,
              backgroundColor: warn == Level.red ? C.red : C.amberFill,
              child: const Icon(Icons.priority_high, color: Colors.white, size: 16),
            ),
          ),
      ],
    ),
  );
}

/// Big result banner. Green never says "you are fine" (guardrail 1).
class LevelBanner extends StatelessWidget {
  final Level level;
  final List<String> reasons;
  const LevelBanner(this.level, {super.key, this.reasons = const []});

  static Tx title(Level l) => switch (l) {
    Level.red => const Tx('Go to a health facility now', 'Nenda kituo cha afya sasa'),
    Level.amber => const Tx('Contact a health worker within 24 hours', 'Wasiliana na mhudumu wa afya ndani ya saa 24'),
    Level.green => const Tx('No warning signs reported today', 'Hakuna dalili za hatari zilizoripotiwa leo'),
  };

  /// Short status names shown as a pill above the action (MamaBot triage states).
  static Tx status(Level l) => switch (l) {
    Level.red => const Tx('Emergency', 'Dharura'),
    Level.amber => const Tx('Prompt clinical review', 'Uchunguzi wa haraka unahitajika'),
    Level.green => const Tx('No urgent warning identified', 'Hakuna dalili ya hatari iliyoonekana'),
  };

  static Tx sub(Level l) => switch (l) {
    Level.red => const Tx('These are danger signs. Do not wait. Ask someone to go with you.', 'Hizi ni dalili za hatari. Usisubiri. Muombe mtu akusindikize.'),
    Level.amber => const Tx(
      'Something needs a closer look today. Call your clinic or community health worker.',
      'Kuna jambo linalohitaji kuangaliwa leo. Piga simu kliniki au kwa mhudumu wa afya ya jamii.',
    ),
    Level.green => const Tx(
      'This check cannot rule out every problem. If you are worried, contact a health worker. You do not need a warning sign to ask for help.',
      'Ukaguzi huu hauwezi kuondoa kila tatizo. Ukiwa na wasiwasi, wasiliana na mhudumu wa afya. Huhitaji dalili ya hatari ili kuomba msaada.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final c = levelColor(level);
    return Container(
      key: Key('level-${level.name}'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: levelSoft(level),
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: c.withValues(alpha: .45), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusPill(context.tx(status(level)), color: c, icon: levelIcon(level)),
          const Gap(12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                child: Icon(levelIcon(level), color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    context.tx(title(level)),
                    style: TextStyle(fontFamily: display, fontSize: 20, fontWeight: FontWeight.w700, height: 1.25, color: c),
                  ),
                ),
              ),
              ListenButton('${context.tx(title(level))}. ${context.tx(sub(level))}'),
            ],
          ),
          const Gap(12),
          Text(context.tx(sub(level)), style: Theme.of(context).textTheme.bodyLarge),
          if (reasons.isNotEmpty) ...[
            const Gap(12),
            Text(context.t('Because you reported:', 'Kwa sababu umeripoti:'), style: Theme.of(context).textTheme.titleMedium),
            const Gap(4),
            for (final r in reasons)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Icon(Icons.circle, size: 8, color: c),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(r, style: Theme.of(context).textTheme.bodyLarge)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Big tappable tile for a warning sign (icon + words, ≥ 44 px, selected state clear without colour alone).
class SignTile extends StatelessWidget {
  final Sign sign;
  final bool selected;
  final VoidCallback onTap;

  /// Distinguishes the tiles of a second or third baby (twins) in tests and accessibility tools.
  final String keySuffix;

  /// The colour step the tile sits in, when it differs from the sign's own level
  /// (baby fever is red under 60 days).
  final Level? shownAs;
  const SignTile(this.sign, {super.key, required this.selected, required this.onTap, this.keySuffix = '', this.shownAs});
  @override
  Widget build(BuildContext context) {
    final lv = shownAs ?? sign.level;
    final c = levelColor(lv);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: Key('sign-${sign.key}$keySuffix'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? levelSoft(lv) : C.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? c : C.line, width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              ContentIcon(signIconAsset[sign.key], sign.icon, color: selected ? c : C.ink2, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(context.tx(sign.label), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25)),
              ),
              Icon(selected ? Icons.check_box : Icons.check_box_outline_blank, color: selected ? c : C.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

/// One-of-several choice with icons (selection over typing).
class Choice<T> extends StatelessWidget {
  final List<(T, IconData, String)> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String keyPrefix;
  const Choice({super.key, required this.options, required this.value, required this.onChanged, this.keyPrefix = 'opt'});
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (v, icon, label) in options)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                key: Key('$keyPrefix-$v'),
                onTap: () => onChanged(v),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                  decoration: BoxDecoration(
                    color: value == v ? C.primarySoft : C.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: value == v ? C.primary : C.line, width: value == v ? 2 : 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 30, color: value == v ? C.primary : C.ink2),
                      const Gap(6),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Labels features that are not backed by a validated service (guardrail: simulated means labelled).
class SimulatedBadge extends StatelessWidget {
  final String? text;
  const SimulatedBadge({super.key, this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: C.surface2,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: C.line),
    ),
    child: Text(
      text ?? context.t('Simulated · not a diagnosis', 'Mfano · si utambuzi'),
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.ink2),
    ),
  );
}

class ProgressRing extends StatelessWidget {
  final double value;
  final String big, small;
  final double size;

  /// White ring and text, for the green hero card.
  final bool onDark;
  const ProgressRing({super.key, required this.value, required this.big, required this.small, this.size = 88, this.onDark = false});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: value.clamp(0, 1),
            strokeWidth: 8,
            backgroundColor: onDark ? Colors.white.withValues(alpha: .18) : C.surface2,
            color: onDark ? Colors.white : C.primary,
            strokeCap: StrokeCap.round,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              big,
              style: TextStyle(fontFamily: display, fontSize: 24, fontWeight: FontWeight.w800, height: 1, color: onDark ? Colors.white : C.ink),
            ),
            Text(small, style: TextStyle(fontSize: 12, color: onDark ? C.onPrimaryMuted : C.ink2)),
          ],
        ),
      ],
    ),
  );
}

/// Blood pressure trend with the 140/90 limit (MA-12). Accessible: a text summary is announced.
class BpChart extends StatelessWidget {
  final List<(DateTime, int, int)> points;
  const BpChart(this.points, {super.key});
  @override
  Widget build(BuildContext context) {
    final last = points.isEmpty ? null : points.last;
    return Semantics(
      label: last == null ? '' : context.t('Blood pressure, latest ${last.$2} over ${last.$3}', 'Shinikizo la damu, cha mwisho ${last.$2} kwa ${last.$3}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 180,
            width: double.infinity,
            child: CustomPaint(painter: _BpPainter(points)),
          ),
          const Gap(8),
          Wrap(
            spacing: 16,
            children: [
              _key(C.primary, context.t('Top number', 'Namba ya juu')),
              _key(C.brand, context.t('Bottom number', 'Namba ya chini')),
              _key(C.red, context.t('140/90 limit', 'Kikomo 140/90'), dashed: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _key(Color c, String l, {bool dashed = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 16, height: dashed ? 2 : 4, color: c),
      const SizedBox(width: 6),
      Text(l, style: const TextStyle(fontSize: 12, color: C.ink2)),
    ],
  );
}

class _BpPainter extends CustomPainter {
  final List<(DateTime, int, int)> p;
  _BpPainter(this.p);
  @override
  void paint(Canvas canvas, Size size) {
    const lo = 50.0, hi = 180.0, l = 32.0, r = 12.0, t = 8.0, b = 20.0;
    double y(num v) => t + (hi - v) / (hi - lo) * (size.height - t - b);
    final w = size.width - l - r;
    double x(int i) => l + (p.length < 2 ? w / 2 : i * w / (p.length - 1));
    final grid = Paint()
      ..color = C.line
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final v in [60, 90, 120, 140, 160]) {
      canvas.drawLine(Offset(l, y(v)), Offset(size.width - r, y(v)), grid);
      tp.text = TextSpan(
        text: '$v',
        style: const TextStyle(fontFamily: body, fontSize: 10, color: C.ink3),
      );
      tp.layout();
      tp.paint(canvas, Offset(l - tp.width - 6, y(v) - tp.height / 2));
    }
    final limit = Paint()
      ..color = C.red
      ..strokeWidth = 1.5;
    for (final v in [140, 90]) {
      for (var xx = l; xx < size.width - r; xx += 8) {
        canvas.drawLine(Offset(xx, y(v)), Offset(math.min(xx + 4, size.width - r), y(v)), limit);
      }
    }
    void series(int Function((DateTime, int, int)) f, Color c) {
      if (p.isEmpty) return;
      final path = Path()..moveTo(x(0), y(f(p[0])));
      for (var i = 1; i < p.length; i++) {
        path.lineTo(x(i), y(f(p[i])));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = c
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
      for (var i = 0; i < p.length; i++) {
        canvas.drawCircle(Offset(x(i), y(f(p[i]))), 4.5, Paint()..color = c);
        canvas.drawCircle(Offset(x(i), y(f(p[i]))), 2, Paint()..color = Colors.white);
      }
    }

    series((e) => e.$2, C.primary);
    series((e) => e.$3, C.brand);
    if (p.isNotEmpty) {
      tp.text = TextSpan(
        text: '${p.last.$2}/${p.last.$3}',
        style: const TextStyle(fontFamily: body, fontSize: 12, fontWeight: FontWeight.w700, color: C.ink),
      );
      tp.layout();
      tp.paint(canvas, Offset(math.min(x(p.length - 1) - tp.width / 2, size.width - tp.width), y(p.last.$2) - tp.height - 8));
    }
  }

  @override
  bool shouldRepaint(_BpPainter old) => old.p != p;
}

/// "Step 2 of 5" with a thin progress bar (onboarding and other multi-step flows).
class StepProgress extends StatelessWidget {
  final int step, total;
  const StepProgress({super.key, required this.step, required this.total});
  @override
  Widget build(BuildContext context) => Semantics(
    label: context.t('Step ${step + 1} of $total', 'Hatua ${step + 1} kati ya $total'),
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('Step ${step + 1} of $total', 'Hatua ${step + 1} kati ya $total'), style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Sp.sm),
          Row(
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0) const SizedBox(width: Sp.xs),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    height: 4,
                    decoration: BoxDecoration(color: i <= step ? C.primary : C.line, borderRadius: BorderRadius.circular(R.chip)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

/// Square-ish action tile used in grids (Home quick actions, Journey tools).
class ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback onTap;
  final Color tint;
  const ActionTile({super.key, required this.icon, required this.label, required this.onTap, this.sub, this.tint = C.primary});
  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    padding: const EdgeInsets.all(Sp.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: tint.withValues(alpha: .10), borderRadius: BorderRadius.circular(R.input)),
          child: Icon(icon, color: tint, size: 24),
        ),
        const SizedBox(height: Sp.md),
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
        if (sub != null) Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

/// A big tile with a picture on top (from the content kit; an icon until the picture arrives).
/// Home's "How can we help?" grid: one tap, one clear need.
class PictureTile extends StatelessWidget {
  final String picture, label;
  final String? sub;
  final IconData icon;
  final VoidCallback onTap;
  const PictureTile({super.key, required this.picture, required this.icon, required this.label, required this.onTap, this.sub});
  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    padding: const EdgeInsets.all(Sp.smd),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ContentPicture(
          picture,
          height: 92,
          radius: R.medium,
          fallback: Container(
            height: 92,
            decoration: BoxDecoration(color: C.primarySoft, borderRadius: BorderRadius.circular(R.medium)),
            child: Center(child: Icon(icon, color: C.primary, size: 40)),
          ),
        ),
        const SizedBox(height: Sp.smd),
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
        if (sub != null) Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

/// Two tiles per row.
class TileGrid extends StatelessWidget {
  final List<Widget> children;
  const TileGrid({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < children.length; i += 2) ...[
        if (i > 0) const SizedBox(height: Sp.md - 4),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              const SizedBox(width: Sp.md - 4),
              Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
            ],
          ),
        ),
      ],
    ],
  );
}
