// Mothers' circle: the content check (same cases as the server) and the screens.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:safari_ya_mama/app/app.dart';
import 'package:safari_ya_mama/app/providers.dart';
import 'package:safari_ya_mama/features/community/domain/community_check.dart';
import 'package:safari_ya_mama/core/dates.dart';
import 'package:safari_ya_mama/data/local_store.dart';
import 'package:safari_ya_mama/data/remote.dart';
import 'package:safari_ya_mama/state/app_state.dart';

import 'fakes.dart';

void main() {
  group('content check', () {
    final rules = CommunityRules.parse(File('assets/content/community_rules.json').readAsStringSync());

    test('the app has the same rules file as the server', () {
      expect(File('assets/content/community_rules.json').readAsStringSync(), File('supabase/functions/community/rules.json').readAsStringSync());
    });

    test('every shared case gives the same verdict and reasons as the server', () {
      final cases = jsonDecode(File('test/fixtures/community_cases.json').readAsStringSync()) as List;
      for (final c in cases.cast<Map<String, dynamic>>()) {
        final r = checkText(c['text'] as String, rules);
        expect(r.verdict.name, c['verdict'], reason: c['text'] as String);
        expect([...r.reasons]..sort(), [...(c['reasons'] as List).cast<String>()]..sort(), reason: c['text'] as String);
        if (c['urgent'] != null) expect(r.urgent, c['urgent'], reason: c['text'] as String);
        if (c['medical'] != null) expect(r.medical, c['medical'], reason: c['text'] as String);
      }
    });

    test('community names: same rule answers as the server', () {
      final cases = jsonDecode(File('test/fixtures/handle_cases.json').readAsStringSync()) as List;
      for (final c in cases.cast<Map<String, dynamic>>()) {
        expect(checkHandle(c['handle'] as String, rules.handle)?.name, c['problem'], reason: c['handle'] as String);
      }
      expect(handleKey('Mama_Amina'), handleKey('mama.amina'));
      expect(handleKey('mamaam1na'), handleKey('MamaAmina'), reason: 'look-alikes count as the same name');
      expect(handleKey('zawad1'), handleKey('zawadi'));
    });

    test('every myth has a fact in both languages', () {
      for (final m in rules.myths) {
        expect(m.fact.en.length, greaterThan(40), reason: m.id);
        expect(m.fact.sw.length, greaterThan(40), reason: m.id);
      }
    });
  });

  group('screens', () {
    late LocalStore store;
    late FakeRemote remote;
    setUp(() async {
      store = LocalStore();
      await store.open(inMemory: true);
      remote = FakeRemote();
      await CommunityRules.load();
    });
    tearDown(() => Hive.close());

    final now = DateTime.now().toUtc();
    Map<String, dynamic> post(String id, String body, {String status = 'published', List<String> facts = const [], bool mine = false, String? note}) => {
      'id': id,
      'parent_id': null,
      'topic': 'pregnancy',
      'body': body,
      'anonymous': !mine,
      'author_name': mine ? 'MamaJasiri' : null,
      'stage_kind': 'pregnant',
      'stage_value': 28,
      'status': status,
      'facts': facts,
      'staff_post': false,
      'health_note': note,
      'checked': note != null,
      'helpful_count': 2,
      'reply_count': 1,
      'created_at': now.subtract(const Duration(hours: 2)).toIso8601String(),
      'mine': mine,
      'helped': false,
    };

    Future<AppState> pump(WidgetTester t) async {
      final s = AppState(store, remote: remote);
      await s.setLang('en');
      await s.completeOnboarding(name: 'Amina', stage: 'pregnant', lmp: addDays(sod(DateTime.now()), -200));
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 2.75;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(overrides: [appStateProvider.overrideWith((ref) => s)], child: const SafariYaMamaApp()));
      await t.pumpAndSettle();
      return s;
    }

    Future<void> tap(WidgetTester t, String key) async {
      await t.ensureVisible(find.byKey(Key(key)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(Key(key)));
      await t.pumpAndSettle();
    }

    testWidgets('feed: checked fact under a myth question, health worker note, own post waiting', (t) async {
      remote.rpcResults['community_feed'] = [
        post('p1', 'Is it true I should stop the iron tablets in the last month?', facts: ['stop-iron']),
        post('p2', 'Walking in the evening helped my back.', note: 'Good advice. Walk on flat ground.'),
        post('p3', 'My first post', status: 'review', mine: true),
      ];
      await pump(t);
      await tap(t, 'tab-community');
      expect(find.text("Mothers' circle"), findsOneWidget);
      expect(find.text('Checked fact'), findsOneWidget);
      expect(find.textContaining('Take one every day'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Health worker note'), 300, scrollable: find.descendant(of: find.byKey(const Key('community-feed')), matching: find.byType(Scrollable)).first);
      expect(find.text('Health worker note'), findsOneWidget);
      expect(find.text('Checked by a health worker'), findsOneWidget);
      await t.scrollUntilVisible(find.textContaining('Waiting for a health worker'), 300, scrollable: find.descendant(of: find.byKey(const Key('community-feed')), matching: find.byType(Scrollable)).first);
      expect(find.textContaining('Waiting for a health worker'), findsOneWidget);
      expect(find.text('Anonymous mother · 28 weeks pregnant'), findsWidgets);
      expect(find.text('@MamaJasiri · 28 weeks pregnant'), findsOneWidget, reason: 'her own post, with her community name');
    });

    testWidgets('no internet: posts saved on the phone are shown', (t) async {
      remote.rpcResults['community_feed'] = [post('p1', 'Saved post from before')];
      final s = await pump(t);
      await s.community.feed();
      remote.failNext = RemoteError('offline');
      remote.failTimes = 2; // her community profile, then the feed
      await tap(t, 'tab-community');
      expect(find.textContaining('Showing posts saved on this phone'), findsOneWidget);
      expect(find.text('Saved post from before'), findsOneWidget);
    });

    testWidgets('sharing: a phone number must come out; a myth shows the fact and a health-worker check', (t) async {
      remote.rpcResults['community_feed'] = [];
      remote.invokeHandlers['community'] = (b) => {'id': 'new', 'status': 'review', 'urgent': false, 'facts': ['water-early'], 'reasons': []};
      await pump(t);
      await tap(t, 'tab-community');
      await tap(t, 'community-share');
      await t.enterText(find.byKey(const Key('compose-body')), 'Call me on 0712 345 678');
      await t.pumpAndSettle();
      expect(find.textContaining('remove phone numbers'), findsOneWidget);
      expect(t.widget<FilledButton>(find.descendant(of: find.byKey(const Key('compose-send')), matching: find.byType(FilledButton))).onPressed, isNull);

      await t.enterText(find.byKey(const Key('compose-body')), 'I give my baby water since 2 months, it is fine.');
      await t.pumpAndSettle();
      expect(find.textContaining('A health worker will check this'), findsOneWidget);
      expect(find.textContaining('only breast milk'), findsOneWidget);
      await tap(t, 'compose-send');
      expect(remote.calls, contains('invoke community'));
      final sent = remote.invokeBodies.last;
      expect(sent['anonymous'], isTrue, reason: 'anonymous unless she chooses a name');
      expect(sent['stage'], {'kind': 'pregnant', 'value': 28});
      expect(sent['topic'], 'pregnancy');
      expect(find.textContaining('Until then only you can see it'), findsOneWidget);
    });

    testWidgets('a danger sign in a post sends her to Emergency help straight away', (t) async {
      remote.rpcResults['community_feed'] = [];
      await pump(t);
      await tap(t, 'tab-community');
      await tap(t, 'community-share');
      await t.enterText(find.byKey(const Key('compose-body')), 'I have heavy bleeding since this morning');
      await t.pumpAndSettle();
      expect(find.textContaining('This sounds like a danger sign'), findsOneWidget);
      await tap(t, 'compose-emergency');
      expect(find.text('Need urgent help?'), findsOneWidget);
    });

    testWidgets('report a post', (t) async {
      remote.rpcResults['community_feed'] = [post('p1', 'Some advice')];
      await pump(t);
      await tap(t, 'tab-community');
      await tap(t, 'post-menu-p1');
      await t.tap(find.text('Report'));
      await t.pumpAndSettle();
      await tap(t, 'report-wrong');
      expect(remote.calls, contains('rpc report_community_post'));
      expect(find.textContaining('A health worker will look at it'), findsOneWidget);
    });

    testWidgets('community name: rules and taken names are explained; then she posts with her name', (t) async {
      remote.rpcResults['community_feed'] = [];
      remote.invokeHandlers['community'] = (b) => switch (b['action']) {
        'handle_check' => b['handle'] == 'Neema' ? {'ok': false, 'problem': 'taken'} : {'ok': true},
        'handle' => {'handle': b['handle']},
        _ => {'id': 'new', 'status': 'published', 'urgent': false, 'facts': [], 'reasons': []},
      };
      final s = await pump(t);
      await tap(t, 'tab-community');
      await tap(t, 'community-share');
      expect(t.widget<Text>(find.text('Anonymous mother')).data, 'Anonymous mother', reason: 'anonymous is the default');
      await tap(t, 'post-as-name');
      expect(find.text('Choose your community name'), findsOneWidget);

      await t.enterText(find.byKey(const Key('handle-field')), 'DrAmina');
      await t.pumpAndSettle();
      expect(find.textContaining('looks like a health worker'), findsOneWidget);
      await t.enterText(find.byKey(const Key('handle-field')), 'amina0712345');
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('handle-problem'))).data, contains('phone number'));
      await t.enterText(find.byKey(const Key('handle-field')), 'Neema');
      await t.pump(const Duration(milliseconds: 600));
      await t.pumpAndSettle();
      expect(find.textContaining('Someone already has this name'), findsOneWidget);
      await t.enterText(find.byKey(const Key('handle-field')), 'MamaJasiri');
      await t.pump(const Duration(milliseconds: 600));
      await t.pumpAndSettle();
      expect(find.text('This name is free.'), findsOneWidget);
      await tap(t, 'handle-save');
      expect(s.community.handle, 'MamaJasiri');
      expect(find.text('@MamaJasiri'), findsOneWidget, reason: 'back on the post, with her name chosen');

      await t.enterText(find.byKey(const Key('compose-body')), 'Walking after supper helps my back.');
      await t.pumpAndSettle();
      await tap(t, 'compose-send');
      expect(remote.invokeBodies.last['anonymous'], isFalse);
      expect(s.store.meta<bool>('community_anonymous'), isFalse, reason: 'her choice is remembered');
    });

    testWidgets('strikes: paused posting is explained on the tab and when she tries to post', (t) async {
      final until = DateTime.now().add(const Duration(days: 20)).toUtc().toIso8601String();
      remote.rpcResults['community_feed'] = [];
      remote.rpcResults['my_community_profile'] = {'handle': null, 'strikes': 4, 'muted_until': until};
      remote.invokeHandlers['community'] = (_) => throw RemoteError('function 403', status: 403, details: {'error': 'muted', 'until': until});
      await pump(t);
      await tap(t, 'tab-community');
      expect(find.byKey(const Key('community-standing')), findsOneWidget);
      expect(find.textContaining('you cannot post until'), findsOneWidget);
      await tap(t, 'community-share');
      await t.enterText(find.byKey(const Key('compose-body')), 'Hello mothers');
      await t.pumpAndSettle();
      await tap(t, 'compose-send');
      expect(find.textContaining('You cannot post right now'), findsOneWidget);
    });
  });
}
