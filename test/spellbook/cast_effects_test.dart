import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/progress/progress_service.dart';
import 'package:tech_world/spellbook/cast_effects.dart';
import 'package:tech_world/spellbook/spellbook_service.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late SpellbookService spellbook;
  late ProgressService progress;

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
    spellbook = SpellbookService(
      uid: 'test-user',
      collection: fakeFirestore.collection('users'),
    );
    progress = ProgressService(
      uid: 'test-user',
      collection: fakeFirestore.collection('users'),
    );
    await spellbook.loadSpellbook();
    await progress.loadProgress();
  });

  tearDown(() {
    spellbook.dispose();
    progress.dispose();
  });

  group('applyCastSuccessEffects', () {
    test('passing evocation_fizzbuzz grants ignis AND marks completed',
        () async {
      // The plan's #1 acceptance test: passing evocation_fizzbuzz →
      // ignis appears in spellbook.
      await applyCastSuccessEffects(
        challengeId: 'evocation_fizzbuzz',
        spellbook: spellbook,
        progress: progress,
      );

      expect(spellbook.hasWord('ignis'), isTrue);
      expect(progress.isChallengeCompleted('evocation_fizzbuzz'), isTrue);

      // And both writes survived the Firestore round-trip.
      final doc =
          await fakeFirestore.collection('users').doc('test-user').get();
      expect(doc.data()?['learnedWords'], contains('ignis'));
      expect(
        doc.data()?['completedChallenges'],
        contains('evocation_fizzbuzz'),
      );
    });

    test('every challenge id maps to a learnable word', () async {
      // Smoke-test the whole bijection — wires every challenge.id
      // through the actual side-effect path.
      const allChallengeIds = [
        'evocation_fizzbuzz',
        'evocation_countdown',
        'evocation_diamond',
        'divination_color',
        'divination_extract',
        'divination_pattern',
        'transmutation_bullets',
        'transmutation_table',
        'transmutation_json',
        'illusion_pirate',
        'illusion_child',
        'illusion_dual',
        'enchantment_brevity',
        'enchantment_formal',
        'enchantment_contradict',
        'conjuration_glorp',
        'conjuration_pattern',
        'conjuration_language',
      ];
      for (final id in allChallengeIds) {
        await applyCastSuccessEffects(
          challengeId: id,
          spellbook: spellbook,
          progress: progress,
        );
      }
      expect(spellbook.count, 18);
      expect(progress.completedCount, 18);
    });

    test('null spellbook does not block markChallengeCompleted', () async {
      // Race against sign-in: progress is registered, spellbook is not.
      await applyCastSuccessEffects(
        challengeId: 'evocation_fizzbuzz',
        spellbook: null,
        progress: progress,
      );
      expect(progress.isChallengeCompleted('evocation_fizzbuzz'), isTrue);
    });

    test('null progress does not block learnWord', () async {
      // Symmetric: spellbook registered, progress is not.
      await applyCastSuccessEffects(
        challengeId: 'evocation_fizzbuzz',
        spellbook: spellbook,
        progress: null,
      );
      expect(spellbook.hasWord('ignis'), isTrue);
    });

    test('both null is a no-op (no throw)', () async {
      await applyCastSuccessEffects(
        challengeId: 'evocation_fizzbuzz',
        spellbook: null,
        progress: null,
      );
      // Reaches here without throwing — that's the assertion.
    });

    test('unknown challenge id skips word grant but still marks completed',
        () async {
      // A future challenge whose word mapping hasn't been added yet
      // shouldn't break completion tracking.
      await applyCastSuccessEffects(
        challengeId: 'future_challenge_xyz',
        spellbook: spellbook,
        progress: progress,
      );
      expect(spellbook.count, 0);
      expect(progress.isChallengeCompleted('future_challenge_xyz'), isTrue);
    });

    test('idempotent — replaying a cast does not duplicate writes',
        () async {
      await applyCastSuccessEffects(
        challengeId: 'evocation_fizzbuzz',
        spellbook: spellbook,
        progress: progress,
      );
      await applyCastSuccessEffects(
        challengeId: 'evocation_fizzbuzz',
        spellbook: spellbook,
        progress: progress,
      );
      expect(spellbook.count, 1);
      expect(progress.completedCount, 1);
    });
  });
}
