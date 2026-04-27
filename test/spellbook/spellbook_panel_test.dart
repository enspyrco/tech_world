import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/prompt/spell_school.dart';
import 'package:tech_world/spellbook/spellbook_panel.dart';
import 'package:tech_world/spellbook/spellbook_service.dart';

void main() {
  Future<void> pumpPanel(
    WidgetTester tester,
    SpellbookService service,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpellbookPanel(service: service, onClose: () {}),
        ),
      ),
    );
    // First pump renders initialData; second flushes any stream emission.
    await tester.pump();
  }

  group('SpellbookPanel', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    SpellbookService createService(List<String> learned) {
      // Pre-populate so loadSpellbook picks up the words.
      fakeFirestore.collection('users').doc('test-user').set({
        'learnedWords': learned,
      });
      return SpellbookService(
        uid: 'test-user',
        collection: fakeFirestore.collection('users'),
      );
    }

    testWidgets('shows 0 / 18 counter and "No words yet" for every school '
        'when nothing learned', (tester) async {
      final service = createService(const []);
      await service.loadSpellbook();

      await pumpPanel(tester, service);

      expect(find.text('0 / 18 words known'), findsOneWidget);
      // Every school header is present, with a 0/3 count.
      for (final school in SpellSchool.values) {
        expect(find.text(school.label), findsOneWidget);
      }
      expect(find.textContaining('· 0/3'), findsNWidgets(SpellSchool.values.length));
      // Empty-state hint appears once per school.
      expect(
        find.text('No words yet — complete a challenge to learn one.'),
        findsNWidgets(SpellSchool.values.length),
      );

      service.dispose();
    });

    testWidgets('shows learned words grouped by school with correct counts',
        (tester) async {
      // 2 evocation, 1 divination — the rest empty.
      final service = createService(['ignis', 'tempus', 'lumen']);
      await service.loadSpellbook();

      await pumpPanel(tester, service);

      // Total counter.
      expect(find.text('3 / 18 words known'), findsOneWidget);

      // Word chips render with display name.
      expect(find.text('IGNIS'), findsOneWidget);
      expect(find.text('TEMPUS'), findsOneWidget);
      expect(find.text('LUMEN'), findsOneWidget);

      // Counts on the school headers.
      expect(find.textContaining('· 2/3'), findsOneWidget);   // evocation
      expect(find.textContaining('· 1/3'), findsOneWidget);   // divination
      expect(find.textContaining('· 0/3'), findsNWidgets(4)); // others

      // Schools with words don't show the empty-state hint.
      expect(
        find.text('No words yet — complete a challenge to learn one.'),
        findsNWidgets(4),
      );

      service.dispose();
    });

    testWidgets('panel rebuilds when service emits a new word',
        (tester) async {
      final service = createService(const []);
      await service.loadSpellbook();

      await pumpPanel(tester, service);
      expect(find.text('0 / 18 words known'), findsOneWidget);
      expect(find.text('IGNIS'), findsNothing);

      await service.learnWord('ignis');
      await tester.pump();

      expect(find.text('1 / 18 words known'), findsOneWidget);
      expect(find.text('IGNIS'), findsOneWidget);

      service.dispose();
    });

    testWidgets('close button invokes onClose', (tester) async {
      final service = createService(const []);
      await service.loadSpellbook();
      var closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpellbookPanel(
              service: service,
              onClose: () => closed = true,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Close spellbook'));
      expect(closed, isTrue);

      service.dispose();
    });
  });
}
