import 'package:tech_world/spellbook/cast_result.dart';
import 'package:tech_world/spellbook/predefined_combinations.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Confidence below which an utterance is treated as noise — the cast
/// is dropped entirely (UI shows nothing). Distinguishes "STT picked up
/// background noise" from "player intentionally cast something we don't
/// understand." Tunable via playtesting.
const double castNoiseFloor = 0.3;

/// Confidence boundary between the two confidence axes of the lattice.
/// At or above: known combos play at full strength, novel combos go to
/// the oracle for interpretation. Below: known combos play at
/// half-strength (visibly wavering) and novel combos fall back to the
/// "words swirl..." flavor without spending an oracle round-trip.
const double castHighConfidenceBoundary = 0.7;

/// Classify a multi-word voice cast against the 2x2 confidence lattice.
/// Pure — no I/O, no side effects.
///
/// ## The lattice
///
/// |              | conf >= 0.7              | 0.3 <= conf < 0.7         |
/// |--------------|--------------------------|---------------------------|
/// | **known**    | [CastComboKnown]         | [CastComboKnownPartial]   |
/// | **novel**    | [CastComboNovel]         | [CastNoMatch]             |
///
/// Below [castNoiseFloor], the function returns `null` — the caller
/// treats this as silence (no UI feedback at all). The fifth outcome is
/// "the cast wasn't a cast." This separation keeps the [CastResult]
/// sealed family closed to *intentional* outcomes.
///
/// ## Decision order
///
/// 1. confidence below [castNoiseFloor] → `null` (noise, not a cast).
/// 2. transcript is `null` → [CastNoMatch] (mic was silent).
/// 3. tokenize on whitespace; non-[WordId] tokens are ignored (filler
///    like "and", "the"). If zero recognised tokens → [CastNoMatch].
/// 4. Any token is a [WordId] the player hasn't earned →
///    [CastNotLearned] (first un-learned word). Eager — we don't
///    interpret combos containing un-learned words.
/// 5. All words learned, combo lookup hits → [CastComboKnown] (high
///    conf) or [CastComboKnownPartial] (low conf).
/// 6. All words learned, combo lookup misses → [CastComboNovel] (high
///    conf) or [CastNoMatch] (low conf — fail-cheap).
///
/// `confidence == null` (e.g. from the stub STT on non-web platforms)
/// is treated as zero — fail-safe; non-web platforms can't currently
/// cast at all, and the noise-floor check is the gate.
CastResult? classifyComboCast({
  required String? transcript,
  required double? confidence,
  required Set<WordId> learnedWords,
}) {
  final conf = confidence ?? 0.0;
  if (conf < castNoiseFloor) return null;
  if (transcript == null) return const CastNoMatch(null);

  final tokens = transcript.toLowerCase().trim().split(RegExp(r'\s+'));
  final wordIds = <WordId>[];
  for (final t in tokens) {
    if (t.isEmpty) continue;
    final w = WordId.parse(t);
    if (w != null) wordIds.add(w);
  }

  if (wordIds.isEmpty) return CastNoMatch(transcript);

  for (final w in wordIds) {
    if (!learnedWords.contains(w)) return CastNotLearned(w);
  }

  final isHighConfidence = conf >= castHighConfidenceBoundary;
  final effect = lookupCombo(wordIds);

  if (effect != null) {
    return isHighConfidence
        ? CastComboKnown(effect)
        : CastComboKnownPartial(effect);
  }

  return isHighConfidence
      ? CastComboNovel(wordIds)
      : CastNoMatch(transcript);
}
