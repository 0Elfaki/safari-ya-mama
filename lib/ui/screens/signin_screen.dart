import 'package:flutter/material.dart';

import '../../core/content_assets.dart';
import '../../data/google_auth.dart';
import '../../data/remote.dart';
import '../content_widgets.dart';
import '../theme.dart';
import '../widgets.dart';

/// Sign-in (required when the app has a server, so her records are never only on one phone).
/// Three ways in, no new password to remember:
///  - her Google account (when Google sign-in is built in);
///  - her phone number and the 6-digit code sent by SMS;
///  - an 8-digit code from her clinic, when staff set up her account (no SMS needed).
/// After sign-in the router takes her on: to Home if her records are already on the server,
/// otherwise to the setup questions.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final phone = TextEditingController(), code = TextEditingController(), clinicCode = TextEditingController();
  String mode = 'sms'; // sms | clinic
  bool sent = false, busy = false;
  String? err;

  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    clinicCode.dispose();
    super.dispose();
  }

  /// Tanzanian numbers: 07xx… or 06xx… → +2557xx…
  String get e164 {
    var p = phone.text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.startsWith('0')) p = '+255${p.substring(1)}';
    if (!p.startsWith('+')) p = '+$p';
    return p;
  }

  Future<void> _run(Future<void> Function() f, {required String failEn, required String failSw, bool signsIn = true}) async {
    final sw = context.appRead.lang == 'sw';
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await f();
      // close only after she is signed in (not after "send me a code")
      if (signsIn && mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on RemoteError {
      err = sw ? failSw : failEn;
    } catch (_) {
      err = sw ? 'Imeshindikana. Kagua mtandao, kisha jaribu tena.' : 'That did not work. Check your connection, then try again.';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final tt = Theme.of(context).textTheme;
    final digits = phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    final clinicDigits = clinicCode.text.replaceAll(RegExp(r'[^0-9]'), '');
    return AppScaffold(
      title: context.t('Sign in', 'Ingia'),
      children: [
        // ONB-SIGNIN when delivered; nothing until then
        if (ContentAssets.has('ONB-SIGNIN')) ...[
          ContentPicture(
            'ONB-SIGNIN',
            height: 180,
            fallback: const SizedBox.shrink(),
            semanticLabel: context.t('A health worker helping a mother with her phone', 'Mhudumu wa afya akimsaidia mama na simu yake'),
          ),
          const Gap(Sp.md),
        ],
        AppHeader(
          context.t('Keep your records safe', 'Linda kumbukumbu zako'),
          subtitle: context.t(
            'Sign in with your phone number. Your checks, visits and vaccines are saved, so they are not lost if this phone is lost. Your clinic sees them only if you allow it.',
            'Ingia kwa namba yako ya simu. Ukaguzi, kliniki na chanjo zako zinahifadhiwa, hazipotei simu hii ikipotea. Kliniki inaziona tu ukiruhusu.',
          ),
        ),
        if (GoogleAuth.available) ...[
          OutlineButton(
            key: const Key('signin-google'),
            context.t('Continue with Google', 'Endelea na Google'),
            icon: Icons.account_circle_outlined,
            loading: busy && mode == 'google',
            onPressed: busy
                ? null
                : () async {
                    setState(() => mode = 'google');
                    await _run(
                      () => s.signInWithGoogle(GoogleAuth.idToken),
                      failEn: 'Google sign-in did not work. Try again, or use your phone number.',
                      failSw: 'Kuingia kwa Google hakukufanya kazi. Jaribu tena, au tumia namba ya simu.',
                    );
                    if (mounted && mode == 'google') setState(() => mode = 'sms');
                  },
          ),
          const Gap(Sp.md),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.smd),
                child: Text(context.t('or with your phone number', 'au kwa namba ya simu'), style: tt.bodySmall),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const Gap(Sp.md),
        ],
        SegmentedButton<String>(
          key: const Key('signin-mode'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'sms', icon: const Icon(Icons.sms_outlined), label: Text(context.t('SMS code', 'Namba kwa SMS'))),
            ButtonSegment(value: 'clinic', icon: const Icon(Icons.local_hospital_outlined), label: Text(context.t('Code from clinic', 'Namba ya kliniki'))),
          ],
          selected: {mode == 'google' ? 'sms' : mode},
          onSelectionChanged: (v) => setState(() {
            mode = v.first;
            err = null;
          }),
        ),
        const Gap(Sp.lg),
        if (mode == 'sms' && !sent) ...[
          TextField(
            key: const Key('signin-phone'),
            controller: phone,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: InputDecoration(labelText: context.t('Phone number', 'Namba ya simu'), hintText: '0712 345 678'),
          ),
          const Gap(Sp.md),
          PrimaryButton(
            key: const Key('signin-send'),
            context.t('Send me a code', 'Nitumie namba'),
            loading: busy,
            onPressed: digits.length < 9
                ? null
                : () => _run(
                    () async {
                      await s.sendCode(e164);
                      sent = true;
                    },
                    signsIn: false,
                    failEn: 'We could not send the code. Check the number and your connection, or use a code from your clinic.',
                    failSw: 'Hatukuweza kutuma namba. Kagua namba na mtandao, au tumia namba kutoka kliniki.',
                  ),
          ),
        ] else if (mode == 'sms') ...[
          Text(context.t('We sent a 6-digit code to $e164.', 'Tumetuma namba ya tarakimu 6 kwa $e164.'), style: tt.bodyLarge),
          const Gap(Sp.md),
          TextField(
            key: const Key('signin-code'),
            controller: code,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            decoration: InputDecoration(labelText: context.t('Code', 'Namba')),
          ),
          PrimaryButton(
            key: const Key('signin-verify'),
            context.t('Sign in', 'Ingia'),
            loading: busy,
            onPressed: code.text.trim().length < 6
                ? null
                : () => _run(
                    () => s.verifyCode(e164, code.text.trim()),
                    failEn: 'That code did not work. Check it, or ask for a new one.',
                    failSw: 'Namba hiyo haikufanya kazi. Ihakiki, au omba mpya.',
                  ),
          ),
          TextButton(onPressed: () => setState(() => sent = false), child: Text(context.t('Change number', 'Badilisha namba'))),
        ] else ...[
          AppCard(
            color: C.primarySoft,
            border: C.primary.withValues(alpha: .18),
            child: Text(
              context.t(
                'No SMS, or need help? Ask a health worker at your clinic. They set up your account and give you an 8-digit code.',
                'Huna SMS, au unahitaji msaada? Muulize mhudumu wa afya kliniki. Atakuandalia akaunti na kukupa namba ya tarakimu 8.',
              ),
              style: tt.bodyLarge,
            ),
          ),
          const Gap(Sp.md),
          TextField(
            key: const Key('signin-clinic-code'),
            controller: clinicCode,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            maxLength: 9,
            decoration: InputDecoration(labelText: context.t('Code from the clinic', 'Namba kutoka kliniki'), hintText: '1234 5678'),
          ),
          PrimaryButton(
            key: const Key('signin-clinic'),
            context.t('Sign in', 'Ingia'),
            loading: busy,
            onPressed: clinicDigits.length != 8
                ? null
                : () => _run(
                    () => s.redeemSetupCode(clinicDigits),
                    failEn: 'This code did not work. It may be used or older than 24 hours. Ask the clinic for a new one.',
                    failSw: 'Namba hii haikufanya kazi. Huenda imeshatumika au imepita saa 24. Omba kliniki namba mpya.',
                  ),
          ),
        ],
        if (err != null) ...[const Gap(Sp.md), ErrorState(err!)],
        const Gap(Sp.lg),
        Text(
          context.t(
            'Sign-in needs internet once. After that the app works without a signal.',
            'Kuingia kunahitaji intaneti mara moja. Baada ya hapo programu inafanya kazi bila mtandao.',
          ),
          style: tt.bodySmall,
        ),
      ],
    );
  }
}
