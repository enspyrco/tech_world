import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/progress/progress_service.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/spellbook/cast_effects.dart';
import 'package:tech_world/spellbook/door_cast_result.dart';
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
    clearSinks();
  });

  group('castSuccessEvents (pure)', () {
    test('returns WordLearned + ChallengeCompleted for a mapped challenge',
        () {
      final events = castSuccessEvents(PromptChallengeId.evocationFizzbuzz);

      expect(events, hasLength(2));
      expect(events[0], isA<WordLearned>()
          .having((e) => e.wordId, 'wordId', WordId.ignis)
          .having((e) => e.challengeId, 'challengeId',
              PromptChallengeId.evocationFizzbuzz));
      expect(events[1], isA<ChallengeCompleted>()
          .having((e) => e.challengeId, 'challengeId',
              'evocation_fizzbuzz'));
    });

    test('every PromptChallengeId produces exactly 2 events', () {
      for (final id in PromptChallengeId.values) {
        final events = castSuccessEvents(id);
        expect(events, hasLength(2),
            reason: '${id.name} should produce WordLearned + '
                'ChallengeCompleted');
        expect(events[0], isA<WordLearned>());
        expect(events[1], isA<ChallengeCompleted>());
      }
    });

    test('is pure — same input produces equivalent events', () {
      final a = castSuccessEvents(PromptChallengeId.evocationFizzbuzz);
      final b = castSuccessEvents(PromptChallengeId.evocationFizzbuzz);

      expect(a.length, b.length);
      final wa = a[0] as WordLearned;
      final wb = b[0] as WordLearned;
      expect(wa.wordId, wb.wordId);
      expect(wa.challengeId, wb.challengeId);
    });
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

    test('dispatches events to registered sinks', () async {
      final captured = <AppEvent>[];
      registerSink(captured.add);

      await applyCastSuccessEffects(
        challengeId: PromptChallengeId.evocationFizzbuzz,
        spellbook: spellbook,
        progress: progress,
      );

      expect(captured, hasLength(2));
      expect(captured[0], isA<WordLearned>());
      expect(captured[1], isA<ChallengeCompleted>());
    });

    test('returns the dispatched events', () async {
      final events = await applyCastSuccessEffects(
        challengeId: PromptChallengeId.evocationFizzbuzz,
        spellbook: spellbook,
        progress: progress,
      );

      expect(events, hasLength(2));
      expect(events[0], isA<WordLearned>());
      expect(events[1], isA<ChallengeCompleted>());
    });
  });

  group('performCast events', () {
    test('CastPass returns WordLearned + ChallengeCompleted events',
        () async {
      // Give the spellbook the word so classifyCast returns CastPass.
      await spellbook.learnWord(WordId.ignis);

      final (result, events) = await performCast(
        transcript: 'ignis',
        doorRequiredChallenges: [PromptChallengeId.evocationFizzbuzz],
        spellbook: spellbook,
        progress: progress,
      );

      expect(result, isA<CastPass>());
      expect(events, hasLength(2));
      expect(events[0], isA<WordLearned>());
      expect(events[1], isA<ChallengeCompleted>());
    });

    test('DoorCastNoMatch returns empty events', () async {
      final (result, events) = await performCast(
        transcript: 'nonsense',
        doorRequiredChallenges: [PromptChallengeId.evocationFizzbuzz],
        spellbook: spellbook,
        progress: progress,
      );

      expect(result, isA<DoorCastNoMatch>());
      expect(events, isEmpty);
    });

    test('DoorCastNotLearned returns empty events', () async {
      final (result, events) = await performCast(
        transcript: 'ignis',
        doorRequiredChallenges: [PromptChallengeId.evocationFizzbuzz],
        spellbook: spellbook,
        progress: progress,
      );

      expect(result, isA<DoorCastNotLearned>());
      expect(events, isEmpty);
    });

    test('CastWrongDoor returns empty events', () async {
      await spellbook.learnWord(WordId.ignis);

      final (result, events) = await performCast(
        transcript: 'ignis',
        // Different challenge than ignis's evocationFizzbuzz.
        doorRequiredChallenges: [PromptChallengeId.divinationColor],
        spellbook: spellbook,
        progress: progress,
      );

      expect(result, isA<CastWrongDoor>());
      expect(events, isEmpty);
    });

    test('null transcript returns DoorCastNoMatch with empty events',
        () async {
      final (result, events) = await performCast(
        transcript: null,
        doorRequiredChallenges: [PromptChallengeId.evocationFizzbuzz],
        spellbook: spellbook,
        progress: progress,
      );

      expect(result, isA<DoorCastNoMatch>());
      expect(events, isEmpty);
    });
  });
}
