import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// 4-digit app PIN for shared phones (MA-04). Emergency help stays reachable without the PIN.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String pin = '';
  bool wrong = false;

  void _tap(String d) {
    if (pin.length >= 4) return;
    setState(() {
      pin += d;
      wrong = false;
    });
    if (pin.length == 4) {
      final ok = context.appRead.unlock(pin);
      if (!ok) {
        setState(() {
          pin = '';
          wrong = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(actions: const [EmergencyButton()]),
      body: SafeArea(
        child: Column(
          children: [
            const Gap(24),
            Image.asset('assets/brand/mark.png', width: 64, height: 64),
            const Gap(16),
            Text(context.t('Enter your PIN', 'Weka PIN yako'), style: Theme.of(context).textTheme.headlineSmall),
            const Gap(16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    margin: const EdgeInsets.all(8),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < pin.length ? C.primary : C.surface2,
                      border: Border.all(color: C.line),
                    ),
                  ),
              ],
            ),
            if (wrong) Text(context.t('That PIN is not right. Try again.', 'PIN si sahihi. Jaribu tena.'), style: const TextStyle(color: C.red)),
            const Spacer(),
            PinPad(onDigit: _tap, onBack: () => setState(() => pin = pin.isEmpty ? '' : pin.substring(0, pin.length - 1))),
            const Gap(24),
          ],
        ),
      ),
    );
  }
}

class PinPad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBack;
  const PinPad({super.key, required this.onDigit, required this.onBack});
  @override
  Widget build(BuildContext context) {
    Widget key(String d) => SizedBox(
      width: 88,
      height: 64,
      child: TextButton(
        key: Key('pin-$d'),
        onPressed: () => onDigit(d),
        child: Text(
          d,
          style: const TextStyle(fontFamily: display, fontSize: 24, fontWeight: FontWeight.w700, color: C.ink),
        ),
      ),
    );
    return Column(
      children: [
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(mainAxisAlignment: MainAxisAlignment.center, children: row.map(key).toList()),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 88),
            key('0'),
            SizedBox(
              width: 88,
              height: 64,
              child: IconButton(onPressed: onBack, icon: const Icon(Icons.backspace_outlined), tooltip: context.t('Delete', 'Futa')),
            ),
          ],
        ),
      ],
    );
  }
}
