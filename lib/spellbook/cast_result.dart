import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/spellbook/predefined_words.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Outcome of a voice-cast attempt.
///
/// Sealed so consumers (UI overlay, telemetry, tests) can switch
/// exhaustively. Adding a new outcome (e.g. `CastTooQuiet` if we
/// surface STT confidence later) fails the build at every site that
/// hasn't handled it — the type system enumerates the work the same
/// way it did for the [PromptChallengeId] refactor.
///
/// Each variant carries the data the UI needs to render a useful
/// response: the matched challenge for [CastPass], the heard text for
/// [CastNoMatch], the un-learned word for [CastNotLearned], the
/// expected door requirements for [CastWrongDoor].
sealed class CastResult {
  const CastResult();
}

/// The transcript matched a learned word that opens this door. Persistent
/// side-effects (learn-the-word + mark-challenge-completed) have run by
/// the time a [CastPass] is returned from [performCast].
final class CastPass extends CastResult {
  const CastPass(this.challengeId);

  /// Which of the door's required challenges this cast satisfied.
  /// Drives the visual effect (school-coloured particles in Phase 2.5).
  final PromptChallengeId challengeId;
}

/// The transcript didn't parse to any known word — heard sound the
/// spellbook can't even recognise as a candidate. The UI uses this to
/// trigger flavor feedback ("the words swirl but find no form...").
///
/// `transcript == null` means STT was silent / cancelled / timed out;
/// the UI may want to show a different cue ("did you mean to cast?").
final class CastNoMatch extends CastResult {
  const CastNoMatch(this.transcript);

  /// What the player actually said, or `null` if STT produced no
  /// transcript at all. Useful for flavor generation and telemetry.
  final String? transcript;
}

/// The transcript parsed to a real [WordId] but the player hasn't
/// earned it yet. The UI nudges toward the corresponding challenge.
final class CastNotLearned extends CastResult {
  const CastNotLearned(this.wordId);

  /// The word the player tried to cast. The mapped challenge is
  /// `wordById[wordId]!.challengeId` if the UI wants to show "solve
  /// the [name] challenge to earn this word".
  final WordId wordId;
}

/// The transcript parsed to a learned word, but the word's challenge
/// isn't in this door's required set. Wrong door, right vocabulary.
final class CastWrongDoor extends CastResult {
  const CastWrongDoor({
    required this.wordId,
    required this.expectedChallenges,
  });

  /// The word the player cast.
  final WordId wordId;

  /// Challenges this door actually requires. Exposed so the UI can
  /// hint ("this door wants a [school] word") without re-querying.
  final List<PromptChallengeId> expectedChallenges;
}

/// Classify a voice-cast attempt. Pure — no I/O, no side effects.
///
/// Decision order (matters for the UX):
///
/// 1. Null transcript → [CastNoMatch] (mic was silent / cancelled).
/// 2. Transcript doesn't parse to a [WordId] → [CastNoMatch] (heard
///    something but it's not a word of power).
/// 3. Word parsed but not in [learnedWords] → [CastNotLearned]
///    (precedes the wrong-door check — "you don't know this word"
///    is more useful feedback than "this isn't the right door").
/// 4. Word learned but its challenge isn't in
///    [doorRequiredChallenges] → [CastWrongDoor].
/// 5. Otherwise → [CastPass].
///
/// The transcript is normalised with `.toLowerCase().trim()` before
/// parsing — STT engines vary on case and trailing whitespace, and a
/// perfect utterance shouldn't fail on those.
CastResult classifyCast({
  required String? transcript,
  required Set<WordId> learnedWords,
  required List<PromptChallengeId> doorRequiredChallenges,
}) {
  if (transcript == null) return const CastNoMatch(null);

  final normalized = transcript.toLowerCase().trim();
  final wordId = WordId.parse(normalized);
  if (wordId == null) return CastNoMatch(transcript);

  if (!learnedWords.contains(wordId)) return CastNotLearned(wordId);

  // wordById is total over WordId.values (predefined_words.dart), so
  // the lookup never returns null for a learned word.
  final word = wordById[wordId]!;

  if (!doorRequiredChallenges.contains(word.challengeId)) {
    return CastWrongDoor(
      wordId: wordId,
      expectedChallenges: doorRequiredChallenges,
    );
  }

  return CastPass(word.challengeId);
}
