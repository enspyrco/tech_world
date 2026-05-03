import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/spellbook/predefined_words.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Outcome of a **door-cast** attempt — a single learned word spoken
/// at a Wizard's Tower locked door, where the cast must match the
/// door's required challenge to unlock.
///
/// Sealed so consumers (door overlay, telemetry, tests) can switch
/// exhaustively. The free-cast lattice (Phase 3, [FreeCastResult])
/// lives in a separate sealed family — `DoorCastResult` and
/// `FreeCastResult` are intentionally disjoint so the door overlay
/// can't be handed a `CastComboNovel` and the free-cast UI can't be
/// handed a `CastWrongDoor`. The compiler proves the routing instead
/// of `UnsupportedError` doing it after entropy has increased.
///
/// Each variant carries the data the UI needs to render a useful
/// response.
sealed class DoorCastResult {
  const DoorCastResult();
}

/// The transcript matched a learned word that opens this door. Persistent
/// side-effects (learn-the-word + mark-challenge-completed) have run by
/// the time a [CastPass] is returned from `performCast`.
final class CastPass extends DoorCastResult {
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
final class DoorCastNoMatch extends DoorCastResult {
  const DoorCastNoMatch(this.transcript);

  /// What the player actually said, or `null` if STT produced no
  /// transcript at all. Useful for flavor generation and telemetry.
  final String? transcript;
}

/// The transcript parsed to a real [WordId] but the player hasn't
/// earned it yet. The UI nudges toward the corresponding challenge.
final class DoorCastNotLearned extends DoorCastResult {
  const DoorCastNotLearned(this.wordId);

  /// The word the player tried to cast. The mapped challenge is
  /// `wordById[wordId]!.challengeId` if the UI wants to show "solve
  /// the [name] challenge to earn this word".
  final WordId wordId;
}

/// The transcript parsed to a learned word, but the word's challenge
/// isn't in this door's required set. Wrong door, right vocabulary.
final class CastWrongDoor extends DoorCastResult {
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

/// Classify a door-cast attempt. Pure — no I/O, no side effects.
///
/// Decision order (matters for the UX):
///
/// 1. Null transcript → [DoorCastNoMatch] (mic was silent / cancelled).
/// 2. Transcript doesn't parse to a [WordId] → [DoorCastNoMatch] (heard
///    something but it's not a word of power).
/// 3. Word parsed but not in [learnedWords] → [DoorCastNotLearned]
///    (precedes the wrong-door check — "you don't know this word"
///    is more useful feedback than "this isn't the right door").
/// 4. Word learned but its challenge isn't in
///    [doorRequiredChallenges] → [CastWrongDoor].
/// 5. Otherwise → [CastPass].
///
/// The transcript is normalised with `.toLowerCase().trim()` before
/// parsing — STT engines vary on case and trailing whitespace, and a
/// perfect utterance shouldn't fail on those.
DoorCastResult classifyCast({
  required String? transcript,
  required Set<WordId> learnedWords,
  required List<PromptChallengeId> doorRequiredChallenges,
}) {
  if (transcript == null) return const DoorCastNoMatch(null);

  final normalized = transcript.toLowerCase().trim();
  final wordId = WordId.parse(normalized);
  if (wordId == null) return DoorCastNoMatch(transcript);

  if (!learnedWords.contains(wordId)) return DoorCastNotLearned(wordId);

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
