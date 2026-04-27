import 'package:logging/logging.dart';
import 'package:tech_world/progress/progress_service.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/spellbook/predefined_words.dart';
import 'package:tech_world/spellbook/spellbook_service.dart';

final _log = Logger('CastEffects');

/// Apply the persistent side-effects of a successful prompt-challenge cast:
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
Future<void> applyCastSuccessEffects({
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
}
