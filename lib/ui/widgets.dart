import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/content_assets.dart';
import 'content_widgets.dart';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';

import '../core/content.dart';
import '../core/tx.dart';
import '../state/app_state.dart';
import 'theme.dart';

extension Ctx on BuildContext {
  AppState get app => watch<AppState>();
  AppState get appRead => read<AppState>();

  /// Inline bilingual string: both languages sit side by side in the code (NF-09).
  String t(String en, String sw) => watch<AppState>().lang == 'sw' ? sw : en;
  String tx(Tx t) => t.of(watch<AppState>().lang);
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

/// Persistent one-tap Emergency help (MA-09), shown on every health screen.
class EmergencyButton extends StatelessWidget {
  const EmergencyButton({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: FilledButton.icon(
      key: const Key('emergency'),
      style: FilledButton.styleFrom(backgroundColor: C.red, minimumSize: const Size(44, 44), padding: const EdgeInsets.symmetric(horizontal: 14)),
      onPressed: () => Navigator.of(context).pushNamed('/emergency'),
      icon: const Icon(Icons.emergency, size: 20),
      label: Text(context.t('Emergency', 'Dharura')),
    ),
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

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
    child: Row(
      children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
        ?trailing,
      ],
    ),
  );
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  final Color? border;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.onTap, this.border});
  @override
  Widget build(BuildContext context) => Card(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(R.card),
      side: BorderSide(color: border ?? C.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
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

/// Lesson illustration drawn from SVG (almost no data), with a red or amber badge for danger steps.
class Illus extends StatelessWidget {
  final String art;
  final Level? warn;
  final double height;
  final Color background;
  const Illus(this.art, {super.key, this.warn, this.height = 160, this.background = C.primarySoft});
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(16)),
    child: Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SvgPicture.asset('assets/illus/$art.svg', fit: BoxFit.contain),
          ),
        ),
        if (warn != null)
          Positioned(
            right: 10,
            top: 10,
            child: CircleAvatar(
              radius: 15,
              backgroundColor: warn == Level.red ? C.red : C.amberFill,
              child: const Icon(Icons.priority_high, color: Colors.white, size: 18),
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
  Widget build(BuildContext context) => Row(
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
  const ProgressRing({super.key, required this.value, required this.big, required this.small, this.size = 88});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.expand(
          child: CircularProgressIndicator(value: value.clamp(0, 1), strokeWidth: 8, backgroundColor: C.surface2, color: C.primary, strokeCap: StrokeCap.round),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              big,
              style: const TextStyle(fontFamily: display, fontSize: 24, fontWeight: FontWeight.w800, height: 1),
            ),
            Text(small, style: const TextStyle(fontSize: 12, color: C.ink2)),
          ],
        ),
      ],
    ),
  );
}

class EmptyNote extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyNote(this.icon, this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      children: [
        Icon(icon, color: C.ink3),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
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
        style: const TextStyle(fontSize: 10, color: C.ink3),
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
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.ink),
      );
      tp.layout();
      tp.paint(canvas, Offset(math.min(x(p.length - 1) - tp.width / 2, size.width - tp.width), y(p.last.$2) - tp.height - 8));
    }
  }

  @override
  bool shouldRepaint(_BpPainter old) => old.p != p;
}
