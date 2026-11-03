import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../state/app_state.dart';

/// Push notifications (MA-54). Only the FCM token goes to the server (rpc register_push_token);
/// messages carry no health data: the text is a fixed template and `data` holds only the template key.
/// Without the FCM dart-defines, or on the web, this does nothing and reminders fall back to SMS
/// (when the mother turned SMS reminders on).
///
/// Size note (CLAUDE.md): firebase_core + firebase_messaging add about 1.5 MB to the Android APK.
/// Benefit: free reminders and urgent caregiver messages instead of paid SMS for app users.
class Push {
  static bool _started = false;

  static Future<void> start(AppState state) async {
    if (_started || kIsWeb || !AppConfig.hasPush || !state.hasRemote) return;
    _started = true;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AppConfig.fcmApiKey,
          appId: AppConfig.fcmAppId,
          messagingSenderId: AppConfig.fcmSenderId,
          projectId: AppConfig.fcmProjectId,
        ),
      );
      final m = FirebaseMessaging.instance;
      final perm = await m.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      // Registration tokens still work with FCM HTTP v1 `message.token` (used by send-notifications).
      // Move to register()/onRegistered once the Edge Function sends to installation IDs.
      // ignore: deprecated_member_use
      final token = await m.getToken();
      if (token != null) await state.registerPushToken(token);
      // ignore: deprecated_member_use
      m.onTokenRefresh.listen(state.registerPushToken);
    } catch (_) {
      _started = false; // no Google Play services, or offline: SMS reminders still work
    }
  }
}
