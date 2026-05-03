import 'package:tech_world/spellbook/spell_effect.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Outcome of a **free-cast** attempt — one or more learned words
/// spoken outside any door-progression context. The 2x2 confidence
/// lattice (`{known, novel} × {high, low confidence}`) classifies the
/// utterance into one of four cells; sub-noise utterances are signalled
/// by the classifier returning `null` rather than a [FreeCastResult]
/// variant.
///
/// Sealed so consumers (free-cast UI, oracle pipeline, telemetry, tests)
/// can switch exhaustively. The door-cast family ([DoorCastResult])
/// lives separately — `FreeCastResult` and `DoorCastResult` are
/// intentionally disjoint sealed hierarchies so the compiler proves
/// routing correctness rather than runtime `UnsupportedError`s.
sealed class FreeCastResult {
  const FreeCastResult();
}

/// The transcript didn't parse to any known word, or contained an
/// unknown token, or the cast was a low-confidence novel combo (the
/// fail-cheap fallback that doesn't spend an oracle round-trip on a
/// likely mishear). The UI shows flavor text via
/// `OracleService.flavorForNoMatch`.
///
/// `transcript == null` means STT was silent / cancelled.
final class FreeCastNoMatch extends FreeCastResult {
  const FreeCastNoMatch(this.transcript);

  /// What the player actually said, or `null` if STT produced no
  /// transcript at all.
  final String? transcript;
}

/// The transcript parsed to one or more [WordId]s, but the player
/// hasn't earned the first un-learned one yet. Eager check — combos
/// containing un-learned words don't get interpreted.
final class FreeCastNotLearned extends FreeCastResult {
  const FreeCastNotLearned(this.wordId);

  /// The first un-learned word in the cast.
  final WordId wordId;
}

/// A combo of learned words matched a `predefinedCombinations` entry
/// and the utterance confidence was high (`>= castHighConfidenceBoundary`).
/// The full effect plays.
final class CastComboKnown extends FreeCastResult {
  const CastComboKnown(this.effect);

  /// The matched effect — drives VFX selection at full magnitude.
  final SpellEffect effect;
}

/// A known combo cast at low confidence (`>= castNoiseFloor` but
/// `< castHighConfidenceBoundary`). The effect plays but visibly
/// wavers — half-strength visual variant. Cue to the player to speak
/// more clearly without punishing the attempt.
final class CastComboKnownPartial extends FreeCastResult {
  const CastComboKnownPartial(this.effect);

  /// The matched effect — same selection as full strength, halved
  /// magnitude at render time.
  final SpellEffect effect;
}

/// A combo of learned words that doesn't match any predefined entry,
/// cast at high confidence. The oracle channel will be asked to
/// interpret these words; the returned text + improvised effect comes
/// back asynchronously via `OracleService.interpretCombo` (Phase 3 PR 2).
///
/// Below the high-confidence boundary, novel combos fall through to
/// [FreeCastNoMatch] instead — we don't spend an oracle round-trip on a
/// likely mishear.
final class CastComboNovel extends FreeCastResult {
  /// Wraps [words] in [List.unmodifiable] so the consuming oracle
  /// pipeline can't accidentally mutate the cast input mid-flight.
  CastComboNovel(List<WordId> words)
      : words = List<WordId>.unmodifiable(words);

  /// Input order preserved — the oracle prompt may want to riff on
  /// the order the words were spoken (semantic vs. alphabetic).
  /// Unmodifiable; mutation throws.
  final List<WordId> words;
}
