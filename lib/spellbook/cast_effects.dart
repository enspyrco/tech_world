import 'package:logging/logging.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/progress/progress_service.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/spellbook/door_cast_result.dart';
import 'package:tech_world/spellbook/predefined_words.dart';
import 'package:tech_world/spellbook/spellbook_service.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

final _log = Logger('CastEffects');

/// Pure function: determine which events a successful cast should produce.
///
/// Returns a [WordLearned] event (if the challenge maps to a word) and a
/// [ChallengeCompleted] event. No I/O, no service calls, no logging.
List<AppEvent> castSuccessEvents(PromptChallengeId challengeId) {
  final events = <AppEvent>[];
  final word = challengeToWord[challengeId];
  if (word != null) {
    events.add(WordLearned(wordId: word.id, challengeId: challengeId));
  }
  events.add(ChallengeCompleted(challengeId: challengeId.wireName));
  return events;
}

/// Apply the persistent side-effects of a successful prompt-challenge cast
/// and dispatch the corresponding events.
///
/// 1. Grant the [WordOfPower] earned by [challengeId] (if any), then
/// 2. Mark the challenge completed.
///
/// **Order matters.** `learnWord` runs first so a Firestore failure on the
/// spellbook write leaves the challenge re-castable —
/// [ProgressService.markChallengeCompleted] is idempotent and would
/// otherwise close off the retry path if it ran before a failing
/// `learnWord`.
///
/// Either service may be null (caller hasn't registered them yet, e.g. a
/// race against sign-in); each null is logged so the silent skip is
/// forensically visible.
///
/// Both per-service exceptions are logged and swallowed — the door-unlock
/// callback that follows in the UI should still run regardless of
/// persistence outcome.
///
/// Returns the events that were dispatched, so callers can inspect them
/// without re-deriving.
Future<List<AppEvent>> applyCastSuccessEffects({
  required PromptChallengeId challengeId,
  required SpellbookService? spellbook,
  required ProgressService? progress,
}) async {
  final word = challengeToWord[challengeId];
  if (word != null) {
    if (spellbook == null) {
      _log.warning('SpellbookService unavailable; word ${word.id.name} not '
          'granted for challenge ${challengeId.wireName}');
    } else {
      try {
        await spellbook.learnWord(word.id);
      } catch (e) {
        _log.warning('Failed to learn word ${word.id.name}: $e', e);
      }
    }
  }

  if (progress == null) {
    _log.warning('ProgressService unavailable; challenge '
        '${challengeId.wireName} not marked completed');
  } else {
    try {
      await progress.markChallengeCompleted(challengeId.wireName);
    } catch (e) {
      _log.warning('Failed to persist completion: $e', e);
    }
  }

  final events = castSuccessEvents(challengeId);
  dispatch(events);
  return events;
}

/// Door-cast orchestrator: classify the transcript and, on a
/// [CastPass], apply the same persistent side-effects as the
/// prompt-cast path ([applyCastSuccessEffects]). Negative outcomes
/// (NoMatch / NotLearned / WrongDoor) produce no events — by design,
/// because aiming a learned word at the wrong door must not silently
/// satisfy progression.
///
/// Returns the classification result alongside any events produced.
/// Events are already dispatched internally via [applyCastSuccessEffects].
///
/// `spellbook` may be null (race against sign-in) — every cast then
/// classifies as [DoorCastNotLearned] (or [DoorCastNoMatch]) which is
/// the correct degraded behaviour: nothing unlocks until the spellbook
/// loads.
///
/// The UI consumer is expected to switch on the returned [DoorCastResult]
/// and render feedback accordingly (success effects on [CastPass],
/// flavor on [DoorCastNoMatch], hint on [DoorCastNotLearned] /
/// [CastWrongDoor]). Free-cast outcomes ([FreeCastResult]) cannot reach
/// this path — the type system prevents it.
Future<WithEvents<DoorCastResult>> performCast({
  required String? transcript,
  required List<PromptChallengeId> doorRequiredChallenges,
  required SpellbookService? spellbook,
  required ProgressService? progress,
}) async {
  final result = classifyCast(
    transcript: transcript,
    learnedWords: spellbook?.learnedWordIds ?? const <WordId>{},
    doorRequiredChallenges: doorRequiredChallenges,
  );

  if (result is CastPass) {
    final events = await applyCastSuccessEffects(
      challengeId: result.challengeId,
      spellbook: spellbook,
      progress: progress,
    );
    return (result, events);
  }

  return (result, const <AppEvent>[]);
}
