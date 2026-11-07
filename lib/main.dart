import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'config.dart';
import 'core/content_assets.dart';
import 'data/local_store.dart';
import 'data/push.dart';
import 'data/remote.dart';
import 'state/app_state.dart';
import 'state/demo_seed.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter('safariyamama');
  await ContentAssets.load();
  final store = LocalStore();
  await store.open();

  RemoteApi? remote;
  if (AppConfig.hasBackend) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
    remote = SupabaseRemote(Supabase.instance.client);
  }
  final state = AppState(store, remote: remote);
  state.onSignedIn = () async {
    await Push.start(state);
    if (state.isCaregiver) await state.refreshCaregiver();
  };
  if (state.signedIn) unawaited(Push.start(state));
  // Offline demo only: ?demo=pregnant|baby loads made-up records; ?a11y=1 turns on the
  // semantics tree (screen readers, automated UI checks).
  final q = Uri.base.queryParameters;
  if (!AppConfig.hasBackend && const {'pregnant', 'baby', 'twins', 'caregiver'}.contains(q['demo']) && store.meta<String>('demo') != q['demo']) {
    await state.seedDemo(q['demo']!);
  }
  if (q['lang'] == 'sw' || q['lang'] == 'en') await state.setLang(q['lang']!);
  if (q['a11y'] == '1') SemanticsBinding.instance.ensureSemantics();
  if (state.hasPin) state.locked = true;

  runApp(ProviderScope(overrides: [appStateProvider.overrideWith((ref) => state)], child: const SafariYaMamaApp()));
}
