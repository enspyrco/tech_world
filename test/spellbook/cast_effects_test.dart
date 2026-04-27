import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/progress/progress_service.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/spellbook/cast_effects.dart';
import 'package:tech_world/spellbook/spellbook_service.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

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
    test('passing evocationFizzbuzz grants ignis AND marks completed',
        () async {
      // The plan's #1 acceptance test: passing evocation_fizzbuzz →
      // ignis appears in spellbook.
      await applyCastSuccessEffects(
        challengeId: PromptChallengeId.evocationFizzbuzz,
        spellbook: spellbook,
        progress: progress,
      );

      expect(spellbook.hasWord(WordId.ignis), isTrue);
      expect(progress.isChallengeCompleted('evocation_fizzbuzz'), isTrue);

      // And both writes survived the Firestore round-trip — the wire
      // format is what persists on disk.
      final doc =
          await fakeFirestore.collection('users').doc('test-user').get();
      expect(doc.data()?['learnedWords'], contains('ignis'));
      expect(
        doc.data()?['completedChallenges'],
        contains('evocation_fizzbuzz'),
      );
    });

    test('every PromptChallengeId maps to a learnable word', () async {
      // Smoke-test the whole bijection — wires every challenge through
      // the actual side-effect path. The bijection is now compile-time
      // total over PromptChallengeId.values.
      for (final id in PromptChallengeId.values) {
        await applyCastSuccessEffects(
          challengeId: id,
          spellbook: spellbook,
          progress: progress,
        );
      }
      expect(spellbook.count, PromptChallengeId.values.length);
      expect(progress.completedCount, PromptChallengeId.values.length);
    });

    test('null spellbook does not block markChallengeCompleted', () async {
      // Race against sign-in: progress is registered, spellbook is not.
      await applyCastSuccessEffects(
        challengeId: PromptChallengeId.evocationFizzbuzz,
        spellbook: null,
        progress: progress,
      );
      expect(progress.isChallengeCompleted('evocation_fizzbuzz'), isTrue);
    });

    test('null progress does not block learnWord', () async {
      // Symmetric: spellbook registered, progress is not.
      await applyCastSuccessEffects(
        challengeId: PromptChallengeId.evocationFizzbuzz,
        spellbook: spellbook,
        progress: null,
      );
      expect(spellbook.hasWord(WordId.ignis), isTrue);
    });

    test('both null is a no-op (no throw)', () async {
      await applyCastSuccessEffects(
        challengeId: PromptChallengeId.evocationFizzbuzz,
        spellbook: null,
        progress: null,
      );
      // Reaches here without throwing — that's the assertion.
    });

    test('idempotent — replaying a cast does not duplicate writes',
        () async {
      await applyCastSuccessEffects(
        challengeId: PromptChallengeId.evocationFizzbuzz,
        spellbook: spellbook,
        progress: progress,
      );
      await applyCastSuccessEffects(
        challengeId: PromptChallengeId.evocationFizzbuzz,
        spellbook: spellbook,
        progress: progress,
      );
      expect(spellbook.count, 1);
      expect(progress.completedCount, 1);
    });
  });
}
