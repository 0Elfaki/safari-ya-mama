// Lesson page (MA-56): key facts first, "When to get help" with the lesson's own warnings,
// sources and review status, related lessons.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safari_ya_mama/app/app.dart';
import 'package:safari_ya_mama/app/providers.dart';
import 'package:safari_ya_mama/core/lessons.g.dart';
import 'package:safari_ya_mama/data/local_store.dart';
import 'package:safari_ya_mama/state/app_state.dart';
import 'package:safari_ya_mama/ui/screens/library_screen.dart';

void main() {
  late AppState s;

  setUp(() async {
    final store = LocalStore();
    await store.open(inMemory: true);
    s = AppState(store);
    await s.completeOnboarding(name: 'Amina', stage: 'pregnant', lmp: DateTime.now().subtract(const Duration(days: 200)));
    await s.setLang('en');
  });
  tearDown(() => Hive.close());

  /// Opens the app, then the lesson [id] on top of it.
  Future<void> open(WidgetTester t, String id) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(overrides: [appStateProvider.overrideWith((ref) => s)], child: const SafariYaMamaApp()));
    await t.pumpAndSettle();
    t.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute(builder: (_) => LessonScreen(id)));
    await t.pumpAndSettle();
  }

  /// Taps "Next" until the last step page is showing.
  Future<void> toLastStep(WidgetTester t, String id) async {
    for (var i = 0; i < lessonById(id)!.steps.length - 1; i++) {
      await t.tap(find.byKey(const Key('lesson-next')));
      await t.pumpAndSettle();
    }
  }

  /// Scrolls the current step page down until [k] is built and visible.
  Future<void> reveal(WidgetTester t, String k) async {
    final f = find.byKey(Key(k));
    final page = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last;
    await t.scrollUntilVisible(f, 200, scrollable: page);
    await t.pumpAndSettle();
  }

  testWidgets('key facts are shown first, before the step pictures', (t) async {
    await open(t, 'danger-preg');
    expect(find.byKey(const Key('lesson-facts')), findsOneWidget);
    expect(find.text('Key facts'), findsOneWidget);
    for (final f in lessonById('danger-preg')!.facts) {
      expect(find.text(f.en), findsOneWidget);
    }
    // end-of-lesson sections only on the last step
    expect(find.byKey(const Key('lesson-gethelp')), findsNothing);
  });

  testWidgets('danger-preg: get-help lists the red warnings and opens Emergency help', (t) async {
    await open(t, 'danger-preg');
    final l = lessonById('danger-preg')!;
    expect(l.warnings, isNotEmpty);
    await toLastStep(t, 'danger-preg');
    await reveal(t, 'lesson-emergency');
    expect(find.byKey(const Key('lesson-gethelp')), findsOneWidget);
    expect(find.text('When to get help'), findsOneWidget);
    expect(find.byKey(const Key('lesson-gethelp-generic')), findsNothing);
    for (var k = 0; k < l.warnings.length; k++) {
      expect(find.byKey(Key('lesson-warn-$k')), findsOneWidget);
    }
    expect(find.text('Danger sign'), findsNWidgets(l.warnings.length));
    expect(find.byKey(const Key('lesson-check')), findsOneWidget);
    expect(find.textContaining('fine'), findsNothing);
    await t.tap(find.byKey(const Key('lesson-emergency')));
    await t.pumpAndSettle();
    expect(find.text('Emergency care plan'), findsOneWidget);
    expect(find.text('Need urgent help?'), findsOneWidget);
  });

  testWidgets('birth-plan: no warnings shows the one generic line and both buttons', (t) async {
    expect(lessonById('birth-plan')!.warnings, isEmpty);
    await open(t, 'birth-plan');
    await toLastStep(t, 'birth-plan');
    await reveal(t, 'lesson-check');
    expect(find.byKey(const Key('lesson-gethelp-generic')), findsOneWidget);
    expect(find.text('Notice a warning sign? Do the daily check, or open Emergency help.'), findsOneWidget);
    expect(find.byKey(const Key('lesson-emergency')), findsOneWidget);
    await t.tap(find.byKey(const Key('lesson-check')));
    await t.pumpAndSettle();
    expect(find.text("Today's check"), findsOneWidget);
  });

  testWidgets('sources box shows "Clinical review pending" and lists the sources when opened', (t) async {
    await open(t, 'danger-preg');
    await toLastStep(t, 'danger-preg');
    await reveal(t, 'lesson-sources');
    expect(find.text('Sources and review'), findsOneWidget);
    expect(find.text('Clinical review pending'), findsOneWidget);
    await t.tap(find.text('Sources and review'));
    await t.pumpAndSettle();
    await reveal(t, 'lesson-review');
    for (final x in lessonById('danger-preg')!.sources) {
      expect(find.text(x), findsOneWidget);
    }
  });

  testWidgets('Kiswahili: review pending and get-help title are translated', (t) async {
    await s.setLang('sw');
    await open(t, 'birth-plan');
    expect(find.text('Mambo muhimu'), findsOneWidget);
    await toLastStep(t, 'birth-plan');
    await reveal(t, 'lesson-sources');
    expect(find.text('Wakati wa kutafuta msaada'), findsOneWidget);
    expect(find.text('Mapitio ya kitabibu yanasubiriwa'), findsOneWidget);
  });

  testWidgets('a related lesson tile opens that lesson', (t) async {
    await open(t, 'danger-preg');
    await toLastStep(t, 'danger-preg');
    final rel = lessonById(lessonById('danger-preg')!.related.first)!;
    await reveal(t, 'lesson-${rel.id}');
    expect(find.byKey(const Key('lesson-related')), findsOneWidget);
    await t.tap(find.byKey(Key('lesson-${rel.id}')));
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, rel.title.en), findsOneWidget);
    expect(find.text(rel.steps.first.text.en), findsOneWidget);
  });
}
