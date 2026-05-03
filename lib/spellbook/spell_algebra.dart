import 'package:tech_world/spellbook/free_cast_result.dart';
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

/// Classify a free-form voice cast (one or more learned words) against
/// the 2x2 confidence lattice. Pure — no I/O, no side effects.
///
/// "Free" because the call has no door / progression context: any
/// number of learned words (including a single word) flows through the
/// same lattice. Door-cast (Phase 2) uses `classifyCast` instead.
///
/// ## The lattice
///
/// |              | conf >= 0.7              | 0.3 <= conf < 0.7         |
/// |--------------|--------------------------|---------------------------|
/// | **known**    | [CastComboKnown]         | [CastComboKnownPartial]   |
/// | **novel**    | [CastComboNovel]         | [FreeCastNoMatch]         |
///
/// Below [castNoiseFloor], the function returns `null` — the caller
/// treats this as silence (no UI feedback at all). The fifth outcome is
/// "the cast wasn't a cast." This separation keeps the [FreeCastResult]
/// sealed family closed to *intentional* outcomes.
///
/// ## Decision order
///
/// 1. confidence is non-finite (`NaN` / infinity) or below
///    [castNoiseFloor] → `null` (noise, not a cast). The `isFinite`
///    check matters because `NaN < x` is always `false` in Dart, so a
///    bare comparison would let `NaN` through as low-confidence.
/// 2. transcript is `null` → [FreeCastNoMatch] (mic was silent).
/// 3. tokenize on whitespace; strip surrounding punctuation that STT
///    engines occasionally emit (`'ignis,'` → `'ignis'`). Any token
///    that isn't a known [WordId] → [FreeCastNoMatch] (the magic
///    doesn't recognise what was said; fail-cheap rather than silently
///    cherry-pick the recognisable subset and risk casting an
///    unintended combo).
/// 4. Any token is a [WordId] the player hasn't earned →
///    [FreeCastNotLearned] (first un-learned word). Eager — we don't
///    interpret combos containing un-learned words.
/// 5. All words learned, combo lookup hits → [CastComboKnown] (high
///    conf) or [CastComboKnownPartial] (low conf).
/// 6. All words learned, combo lookup misses → [CastComboNovel] (high
///    conf) or [FreeCastNoMatch] (low conf — fail-cheap).
///
/// `confidence == null` (e.g. from the stub STT on non-web platforms)
/// is treated as zero — fail-safe; non-web platforms can't currently
/// cast at all, and the noise-floor check is the gate.
FreeCastResult? classifyFreeCast({
  required String? transcript,
  required double? confidence,
  required Set<WordId> learnedWords,
}) {
  final conf = confidence ?? 0.0;
  if (!conf.isFinite || conf < castNoiseFloor) return null;
  if (transcript == null) return const FreeCastNoMatch(null);

  final tokens = transcript.toLowerCase().trim().split(RegExp(r'\s+'));
  final wordIds = <WordId>[];
  for (final t in tokens) {
    if (t.isEmpty) continue;
    // STT engines occasionally emit trailing/leading punctuation
    // (`"ignis."`); strip it so a clean utterance never fails on cosmetics.
    final clean = t.replaceAll(RegExp(r'[.,!?;:]'), '');
    if (clean.isEmpty) continue;
    final w = WordId.parse(clean);
    if (w == null) return FreeCastNoMatch(transcript);
    wordIds.add(w);
  }

  if (wordIds.isEmpty) return FreeCastNoMatch(transcript);

  for (final w in wordIds) {
    if (!learnedWords.contains(w)) return FreeCastNotLearned(w);
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
      : FreeCastNoMatch(transcript);
}
