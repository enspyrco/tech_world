import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/prompt/spell_school.dart';
import 'package:tech_world/spellbook/spellbook_service.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
  });

  SpellbookService createService({String uid = 'test-user'}) {
    return SpellbookService(
      uid: uid,
      collection: fakeFirestore.collection('users'),
    );
  }

  group('SpellbookService', () {
    test('loads empty spellbook when no Firestore document exists', () async {
      final service = createService();
      await service.loadSpellbook();

      expect(service.hasWord('ignis'), isFalse);
      expect(service.count, 0);
      expect(service.learnedWordIds, isEmpty);
    });

    test('loads existing learned words from Firestore', () async {
      await fakeFirestore.collection('users').doc('test-user').set({
        'learnedWords': ['ignis', 'lumen'],
      });

      final service = createService();
      await service.loadSpellbook();

      expect(service.hasWord('ignis'), isTrue);
      expect(service.hasWord('lumen'), isTrue);
      expect(service.hasWord('forma'), isFalse);
      expect(service.count, 2);
    });

    test('learnWord persists to Firestore and updates local cache', () async {
      final service = createService();
      await service.loadSpellbook();

      await service.learnWord('ignis');

      expect(service.hasWord('ignis'), isTrue);
      expect(service.count, 1);

      final doc =
          await fakeFirestore.collection('users').doc('test-user').get();
      expect(doc.data()?['learnedWords'], contains('ignis'));
    });

    test('learnWord is idempotent', () async {
      final service = createService();
      await service.loadSpellbook();

      await service.learnWord('ignis');
      await service.learnWord('ignis');

      expect(service.count, 1);

      final doc =
          await fakeFirestore.collection('users').doc('test-user').get();
      final words = List<String>.from(doc.data()?['learnedWords'] ?? []);
      expect(words.where((w) => w == 'ignis').length, 1);
    });

    test('learnWord rejects unknown word ids', () async {
      final service = createService();
      await service.loadSpellbook();

      expect(
        () => service.learnWord('not-a-real-word'),
        throwsA(isA<ArgumentError>()),
      );
      expect(service.count, 0);
    });

    test('learnedWords stream emits on changes', () async {
      final service = createService();
      await service.loadSpellbook();

      final events = <Set<String>>[];
      service.learnedWords.listen(events.add);

      await service.learnWord('ignis');
      await service.learnWord('lumen');

      expect(events.length, 2);
      expect(events[0], {'ignis'});
      expect(events[1], {'ignis', 'lumen'});
    });

    test('wordsBySchool groups learned words correctly', () async {
      await fakeFirestore.collection('users').doc('test-user').set({
        // 2 evocation, 1 divination
        'learnedWords': ['ignis', 'tempus', 'lumen'],
      });

      final service = createService();
      await service.loadSpellbook();

      final groups = service.wordsBySchool;
      expect(groups[SpellSchool.evocation]!.length, 2);
      expect(groups[SpellSchool.divination]!.length, 1);
      expect(groups[SpellSchool.transmutation], isEmpty);
    });

    test('wordsBySchool covers every school even when none learned', () async {
      final service = createService();
      await service.loadSpellbook();

      final groups = service.wordsBySchool;
      for (final school in SpellSchool.values) {
        expect(groups.containsKey(school), isTrue);
        expect(groups[school], isEmpty);
      }
    });

    test('learned words persist across service instances', () async {
      // Round-trip: learn, dispose, reload.
      final first = createService();
      await first.loadSpellbook();
      await first.learnWord('ignis');
      first.dispose();

      final second = createService();
      await second.loadSpellbook();

      expect(second.hasWord('ignis'), isTrue);
      expect(second.count, 1);
      second.dispose();
    });

    test('separate users have independent spellbooks', () async {
      await fakeFirestore.collection('users').doc('user-a').set({
        'learnedWords': ['ignis'],
      });

      final serviceA = SpellbookService(
        uid: 'user-a',
        collection: fakeFirestore.collection('users'),
      );
      final serviceB = SpellbookService(
        uid: 'user-b',
        collection: fakeFirestore.collection('users'),
      );

      await serviceA.loadSpellbook();
      await serviceB.loadSpellbook();

      expect(serviceA.hasWord('ignis'), isTrue);
      expect(serviceB.hasWord('ignis'), isFalse);

      serviceA.dispose();
      serviceB.dispose();
    });

    test('dispose closes the stream', () async {
      final service = createService();
      await service.loadSpellbook();

      service.dispose();

      expect(service.learnedWords, emitsDone);
    });
  });
}
