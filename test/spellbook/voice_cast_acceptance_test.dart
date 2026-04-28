import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/progress/progress_service.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/spellbook/cast_effects.dart';
import 'package:tech_world/spellbook/cast_result.dart';
import 'package:tech_world/spellbook/spellbook_service.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Phase 2 acceptance test — "speak the word, the door opens".
///
/// Exercises the full voice-cast pipeline at the seam Phase 2 actually
/// uses: a transcript (whatever produced it) plus the door's required
/// challenges plus the player's spellbook → typed [CastResult] +
/// persistent side-effects on success. The STT layer is a separate
/// concern — this test never goes through [SttService] because the
/// behaviour we care about is "what happens given a transcript", not
/// "how the transcript was obtained".
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

  group('classifyCast (pure)', () {
    test('learned word matching the door → CastPass', () {
      final result = classifyCast(
        transcript: 'ignis',
        learnedWords: {WordId.ignis},
        doorRequiredChallenges: const [PromptChallengeId.evocationFizzbuzz],
      );
      expect(result, isA<CastPass>());
      expect(
        (result as CastPass).challengeId,
        PromptChallengeId.evocationFizzbuzz,
      );
    });

    test('normalises case and surrounding whitespace', () {
      final result = classifyCast(
        transcript: '  IGNIS  ',
        learnedWords: {WordId.ignis},
        doorRequiredChallenges: const [PromptChallengeId.evocationFizzbuzz],
      );
      expect(result, isA<CastPass>());
    });

    test('unparseable transcript → CastNoMatch with original text', () {
      final result = classifyCast(
        transcript: 'blarghnonsense',
        learnedWords: const {},
        doorRequiredChallenges: const [PromptChallengeId.evocationFizzbuzz],
      );
      expect(result, isA<CastNoMatch>());
      expect((result as CastNoMatch).transcript, 'blarghnonsense');
    });

    test('null transcript (STT silent / cancelled) → CastNoMatch(null)', () {
      final result = classifyCast(
        transcript: null,
        learnedWords: const {},
        doorRequiredChallenges: const [PromptChallengeId.evocationFizzbuzz],
      );
      expect(result, isA<CastNoMatch>());
      expect((result as CastNoMatch).transcript, isNull);
    });

    test('valid word but not learned yet → CastNotLearned', () {
      final result = classifyCast(
        transcript: 'ignis',
        learnedWords: const {}, // empty spellbook
        doorRequiredChallenges: const [PromptChallengeId.evocationFizzbuzz],
      );
      expect(result, isA<CastNotLearned>());
      expect((result as CastNotLearned).wordId, WordId.ignis);
    });

    test('learned word but wrong door → CastWrongDoor', () {
      final result = classifyCast(
        transcript: 'ignis',
        learnedWords: {WordId.ignis},
        doorRequiredChallenges: const [PromptChallengeId.divinationColor],
      );
      expect(result, isA<CastWrongDoor>());
      final wrong = result as CastWrongDoor;
      expect(wrong.wordId, WordId.ignis);
      expect(
        wrong.expectedChallenges,
        const [PromptChallengeId.divinationColor],
      );
    });

    test('NotLearned takes precedence over WrongDoor', () {
      // If the player can't even cast it, "you haven't learned this" is
      // more useful feedback than "this isn't the right door".
      final result = classifyCast(
        transcript: 'ignis',
        learnedWords: const {},
        doorRequiredChallenges: const [PromptChallengeId.divinationColor],
      );
      expect(result, isA<CastNotLearned>());
    });
  });

  group('performCast (the crux — async with side effects)', () {
    test('Phase 2 acceptance: speak ignis at fire-door, door opens', () async {
      // Arrange — player has IGNIS, door requires evocationFizzbuzz.
      await spellbook.learnWord(WordId.ignis);
      const doorRequires = [PromptChallengeId.evocationFizzbuzz];

      // Act — speak the word.
      final result = await performCast(
        transcript: 'ignis',
        doorRequiredChallenges: doorRequires,
        spellbook: spellbook,
        progress: progress,
      );

      // Assert — typed result is CastPass with the right challenge.
      expect(result, isA<CastPass>());
      expect(
        (result as CastPass).challengeId,
        PromptChallengeId.evocationFizzbuzz,
      );

      // And the persistent side-effects ran (the door-unlock condition
      // is `progress.isChallengeCompleted` — same path as text-cast).
      expect(
        progress.isChallengeCompleted('evocation_fizzbuzz'),
        isTrue,
        reason: 'door-unlock predicate must be satisfied after a successful '
            'voice cast — same seam as the prompt-cast path',
      );

      // Spellbook is unchanged (the word was already learned). This
      // confirms `applyCastSuccessEffects` is idempotent on the
      // spellbook side too.
      expect(spellbook.hasWord(WordId.ignis), isTrue);
    });

    test('NotLearned does NOT mark progress — door stays locked', () async {
      // Spellbook is empty. Speaking a real word the player hasn't
      // earned must not unlock the door.
      final result = await performCast(
        transcript: 'ignis',
        doorRequiredChallenges: const [PromptChallengeId.evocationFizzbuzz],
        spellbook: spellbook,
        progress: progress,
      );

      expect(result, isA<CastNotLearned>());
      expect(progress.isChallengeCompleted('evocation_fizzbuzz'), isFalse);
      expect(spellbook.hasWord(WordId.ignis), isFalse);
    });

    test('WrongDoor does NOT mark progress', () async {
      await spellbook.learnWord(WordId.ignis);

      final result = await performCast(
        transcript: 'ignis',
        doorRequiredChallenges: const [PromptChallengeId.divinationColor],
        spellbook: spellbook,
        progress: progress,
      );

      expect(result, isA<CastWrongDoor>());
      // Crucial: speaking a word at the wrong door must not silently
      // complete the underlying challenge — that would let a player
      // bypass progression by mis-aiming.
      expect(progress.isChallengeCompleted('evocation_fizzbuzz'), isFalse);
      expect(progress.isChallengeCompleted('divination_color'), isFalse);
    });

    test('NoMatch does NOT mark progress', () async {
      await spellbook.learnWord(WordId.ignis);

      final result = await performCast(
        transcript: 'blarghnonsense',
        doorRequiredChallenges: const [PromptChallengeId.evocationFizzbuzz],
        spellbook: spellbook,
        progress: progress,
      );

      expect(result, isA<CastNoMatch>());
      expect(progress.isChallengeCompleted('evocation_fizzbuzz'), isFalse);
    });

    test('case + whitespace round-trip: "  IGNIS  " unlocks the door',
        () async {
      // STT engines vary on case and trailing whitespace. The cast
      // pipeline must normalise both — otherwise a perfect spoken word
      // fails on a presentation detail.
      await spellbook.learnWord(WordId.ignis);

      final result = await performCast(
        transcript: '  IGNIS  ',
        doorRequiredChallenges: const [PromptChallengeId.evocationFizzbuzz],
        spellbook: spellbook,
        progress: progress,
      );

      expect(result, isA<CastPass>());
      expect(progress.isChallengeCompleted('evocation_fizzbuzz'), isTrue);
    });

    test('null transcript (mic timeout / cancel) yields NoMatch + no writes',
        () async {
      await spellbook.learnWord(WordId.ignis);

      final result = await performCast(
        transcript: null,
        doorRequiredChallenges: const [PromptChallengeId.evocationFizzbuzz],
        spellbook: spellbook,
        progress: progress,
      );

      expect(result, isA<CastNoMatch>());
      expect((result as CastNoMatch).transcript, isNull);
      expect(progress.isChallengeCompleted('evocation_fizzbuzz'), isFalse);
    });

    test('multi-challenge door: speaking any one required word unlocks',
        () async {
      // A door listing two required challenges is satisfied per-cast —
      // the door tracks completion server-side via progress, not in
      // the cast pipeline. The cast pipeline only certifies that the
      // spoken word matches *one* of the door's required challenges.
      await spellbook.learnWord(WordId.lumen);

      final result = await performCast(
        transcript: 'lumen',
        doorRequiredChallenges: const [
          PromptChallengeId.evocationFizzbuzz,
          PromptChallengeId.divinationColor,
        ],
        spellbook: spellbook,
        progress: progress,
      );

      expect(result, isA<CastPass>());
      expect(
        (result as CastPass).challengeId,
        PromptChallengeId.divinationColor,
      );
      expect(progress.isChallengeCompleted('divination_color'), isTrue);
      expect(progress.isChallengeCompleted('evocation_fizzbuzz'), isFalse);
    });
  });
}
