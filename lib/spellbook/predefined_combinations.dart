import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:tech_world/spellbook/spell_effect.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Branded canonical key for a combo lookup. Constructed only via the
/// [ComboKey.of] factory which sorts the input words by their wire
/// name and joins with commas — order-independent by construction
/// (`(IGNIS, LUMEN)` and `(LUMEN, IGNIS)` produce the same key).
///
/// Brand exists to prevent the failure mode Carnot flagged in PR #310:
/// callers indexing the predefined map with hand-built `String` keys
/// like `'ignis,lumen'` that bypass the canonicalisation invariant
/// (e.g. an unsorted key, or one drawn from arbitrary user input).
/// Forcing all keys through [ComboKey.of] makes the invariant
/// unforgeable at the type level.
///
/// Sorting on `WordId.name` (the wire form) rather than `WordId.index`
/// keeps the key stable across enum reorderings — a reorder of
/// `WordId.values` won't break Firestore-cached novel combos when
/// those land in PR 2.
final class ComboKey {
  /// Private — use [ComboKey.of].
  const ComboKey._(this.value);

  /// Build a canonical key from a list of [WordId]s. Order-independent.
  factory ComboKey.of(List<WordId> words) =>
      ComboKey._((words.map((w) => w.name).toList()..sort()).join(','));

  /// The underlying canonical string. Exposed for Firestore persistence
  /// (PR 2 cache); should not be parsed back into a [ComboKey] except
  /// via the [ComboKey.fromCanonical] escape hatch.
  final String value;

  /// Hydrate a [ComboKey] from a previously-stored canonical string
  /// (e.g. Firestore cache key in PR 2). **Validating** — rejects:
  /// * empty input
  /// * tokens that don't parse to a [WordId.name]
  /// * tokens that aren't in canonical sorted order
  ///
  /// Throws [FormatException] on any of the above. Carnot's PR-310
  /// finding: a non-validating hydration path makes the brand
  /// forgeable at runtime (`ComboKey.fromCanonical(userInput)`); the
  /// validation here makes the type-level claim actually true.
  factory ComboKey.fromCanonical(String canonical) {
    if (canonical.isEmpty) {
      throw const FormatException('combo key cannot be empty');
    }
    final parts = canonical.split(',');
    final wordNames = WordId.values.map((w) => w.name).toSet();
    for (final part in parts) {
      if (!wordNames.contains(part)) {
        throw FormatException(
            'combo key contains unknown WordId wire-name', part);
      }
    }
    final canonicalSorted = (List<String>.of(parts)..sort()).join(',');
    if (canonicalSorted != canonical) {
      throw FormatException(
          'combo key not in canonical sorted order (expected '
          '"$canonicalSorted")',
          canonical);
    }
    return ComboKey._(canonical);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ComboKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ComboKey($value)';
}

/// Internal mutable map used to construct [predefinedCombinations].
/// Kept private so the public surface is unmodifiable — see below.
final Map<ComboKey, SpellEffect> _rawCombinations = <ComboKey, SpellEffect>{
  ComboKey.of(const [WordId.ignis, WordId.lumen]): SpellEffect(
    id: SpellEffectId('blazing_sight'),
    name: 'Blazing Sight',
    description: 'Burning vision pierces shadows.',
    type: SpellEffectType.illumination,
    magnitude: 6,
  ),
  ComboKey.of(const [WordId.tempus, WordId.libera]): SpellEffect(
    id: SpellEffectId('time_unbound'),
    name: 'Time Unbound',
    description: 'Movement freed from the moment.',
    type: SpellEffectType.passage,
    magnitude: 7,
  ),
  ComboKey.of(const [WordId.crystallum, WordId.vinculum]): SpellEffect(
    id: SpellEffectId('crystal_ward'),
    name: 'Crystal Ward',
    description: 'A faceted shell hardens around the caster.',
    type: SpellEffectType.protection,
    magnitude: 5,
  ),
  ComboKey.of(const [WordId.verum, WordId.oraculum]): SpellEffect(
    id: SpellEffectId('oracle_truth'),
    name: "Oracle's Truth",
    description: 'The veil between question and answer thins.',
    type: SpellEffectType.revelation,
    magnitude: 6,
  ),
  ComboKey.of(const [WordId.ignis, WordId.muta, WordId.forma]): SpellEffect(
    id: SpellEffectId('pyric_reshape'),
    name: 'Pyric Reshape',
    description: 'Fire-spoken matter flows into a new mould.',
    type: SpellEffectType.fireBurst,
    magnitude: 8,
  ),
};

/// Hand-crafted combo → effect map, keyed by the branded [ComboKey] so
/// callers can't bypass the canonicalisation invariant by indexing with
/// a hand-built string. `@visibleForTesting` marks this as a test-only
/// inspection surface; runtime callers go through [lookupCombo].
///
/// Phase 3 PR 1 ships with five combos. More in PR 3 (playtest the
/// lattice with a small set first; novel combos via oracle
/// interpretation cover the gap).
///
/// Wrapped in [Map.unmodifiable] so the predefined lattice can't be
/// mutated at runtime — every combo addition must go through source code.
@visibleForTesting
final Map<ComboKey, SpellEffect> predefinedCombinations =
    Map<ComboKey, SpellEffect>.unmodifiable(_rawCombinations);

/// Look up a combo by its constituent words, ignoring order. Returns
/// `null` if no predefined combination matches.
SpellEffect? lookupCombo(List<WordId> words) =>
    predefinedCombinations[ComboKey.of(words)];
