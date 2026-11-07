// "Continue with Google": Google confirms who she is on the phone (native account picker),
// then Supabase signs her in with that ID token (auth.signInWithIdToken). The app never sees
// a Google password. Shown only when the Google client IDs are built in (see AppConfig).
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';

class GoogleAuth {
  static bool _ready = false;

  /// True on Android/iOS builds made with GOOGLE_WEB_CLIENT_ID (and, for iOS, GOOGLE_IOS_CLIENT_ID).
  static bool get available {
    if (kIsWeb || AppConfig.googleWebClientId.isEmpty) return false;
    if (defaultTargetPlatform == TargetPlatform.android) return true;
    return defaultTargetPlatform == TargetPlatform.iOS && AppConfig.googleIosClientId.isNotEmpty;
  }

  /// Opens Google's account picker. Returns the ID token, or null when she cancels.
  static Future<String?> idToken() async {
    if (!_ready) {
      await GoogleSignIn.instance.initialize(
        serverClientId: AppConfig.googleWebClientId,
        clientId: AppConfig.googleIosClientId.isEmpty ? null : AppConfig.googleIosClientId,
      );
      _ready = true;
    }
    try {
      final account = await GoogleSignIn.instance.authenticate(scopeHint: const ['email']);
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  /// Forgets the Google account on this phone (sign-out, shared phones).
  static Future<void> signOut() async {
    if (!_ready) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}
