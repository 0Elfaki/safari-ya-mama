import 'package:flutter/material.dart';

import '../../data/remote.dart';
import '../theme.dart';
import '../widgets.dart';

/// Phone number + one-time code (SP-01). No password to forget.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final phone = TextEditingController(), code = TextEditingController();
  bool sent = false, busy = false;
  String? err;

  /// Tanzanian numbers: 07xx… or 06xx… → +2557xx…
  String get e164 {
    var p = phone.text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.startsWith('0')) p = '+255${p.substring(1)}';
    if (!p.startsWith('+')) p = '+$p';
    return p;
  }

  Future<void> _run(Future<void> Function() f) async {
    final sw = context.appRead.lang == 'sw';
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await f();
    } on RemoteError catch (e) {
      debugPrint('sign-in: ${e.message}');
      err = sw ? 'Imeshindikana. Kagua namba na mtandao, kisha jaribu tena.' : 'That did not work. Check the number and your connection, then try again.';
    } catch (e) {
      debugPrint('sign-in: $e');
      err = sw ? 'Imeshindikana. Jaribu tena.' : 'That did not work. Try again.';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Connect to my clinic', 'Unganisha na kliniki yangu'))),
      body: Pad(
        children: [
          Text(
            context.t(
              'Your records are backed up and can follow you to a new phone. Your clinic sees them only if you turn sharing on.',
              'Kumbukumbu zako zinahifadhiwa na zinaweza kukufuata kwenye simu mpya. Kliniki inaziona tu ukiwasha kushiriki.',
            ),
          ),
          const Gap(16),
          if (!sent) ...[
            TextField(
              controller: phone,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: context.t('Phone number', 'Namba ya simu'), hintText: '0712 345 678'),
            ),
            const Gap(16),
            FilledButton(
              onPressed: busy || phone.text.replaceAll(RegExp(r'[^0-9]'), '').length < 9
                  ? null
                  : () => _run(() async {
                      await s.sendCode(e164);
                      sent = true;
                    }),
              child: Text(context.t('Send me a code', 'Nitumie namba ya siri')),
            ),
          ] else ...[
            Text(context.t('We sent a 6-digit code to $e164.', 'Tumetuma namba ya tarakimu 6 kwa $e164.')),
            const Gap(12),
            TextField(
              controller: code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(labelText: context.t('Code', 'Namba ya siri')),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () => _run(() async {
                      await s.verifyCode(e164, code.text.trim());
                      if (context.mounted) Navigator.pop(context);
                    }),
              child: Text(context.t('Connect', 'Unganisha')),
            ),
            TextButton(onPressed: () => setState(() => sent = false), child: Text(context.t('Change number', 'Badilisha namba'))),
          ],
          if (busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (err != null) Text(err!, style: const TextStyle(color: C.red)),
        ],
      ),
    );
  }
}
