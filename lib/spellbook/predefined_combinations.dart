import 'package:tech_world/spellbook/spell_effect.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Canonical lookup key for a combo: words sorted by their wire name,
/// joined with commas. Order-independent by construction — `(IGNIS, LUMEN)`
/// and `(LUMEN, IGNIS)` produce the same key.
///
/// Sorting on `WordId.name` (the wire form) rather than `WordId.index`
/// keeps the key stable across enum reorderings — a reorder of
/// `WordId.values` won't break Firestore-cached novel combos when those
/// land in PR 2.
String comboKey(List<WordId> words) =>
    (words.map((w) => w.name).toList()..sort()).join(',');

/// Internal mutable map used to construct [predefinedCombinations].
/// Kept private so the public surface is unmodifiable — see below.
final Map<String, SpellEffect> _rawCombinations = <String, SpellEffect>{
  comboKey(const [WordId.ignis, WordId.lumen]): SpellEffect(
    id: const SpellEffectId('blazing_sight'),
    name: 'Blazing Sight',
    description: 'Burning vision pierces shadows.',
    type: SpellEffectType.illumination,
    magnitude: 6,
  ),
  comboKey(const [WordId.tempus, WordId.libera]): SpellEffect(
    id: const SpellEffectId('time_unbound'),
    name: 'Time Unbound',
    description: 'Movement freed from the moment.',
    type: SpellEffectType.passage,
    magnitude: 7,
  ),
  comboKey(const [WordId.crystallum, WordId.vinculum]): SpellEffect(
    id: const SpellEffectId('crystal_ward'),
    name: 'Crystal Ward',
    description: 'A faceted shell hardens around the caster.',
    type: SpellEffectType.protection,
    magnitude: 5,
  ),
  comboKey(const [WordId.verum, WordId.oraculum]): SpellEffect(
    id: const SpellEffectId('oracle_truth'),
    name: "Oracle's Truth",
    description: 'The veil between question and answer thins.',
    type: SpellEffectType.revelation,
    magnitude: 6,
  ),
  comboKey(const [WordId.ignis, WordId.muta, WordId.forma]): SpellEffect(
    id: const SpellEffectId('pyric_reshape'),
    name: 'Pyric Reshape',
    description: 'Fire-spoken matter flows into a new mould.',
    type: SpellEffectType.fireBurst,
    magnitude: 8,
  ),
};

/// Hand-crafted combo → effect map. Phase 3 PR 1 ships with five.
/// More combos in PR 3 (we want to playtest the lattice with a small
/// set first; novel combos via oracle interpretation cover the gap).
///
/// Keyed by [comboKey] so order of utterance doesn't matter — saying
/// "lumen ignis" finds the same combo as "ignis lumen".
///
/// Wrapped in [Map.unmodifiable] so the predefined lattice can't be
/// mutated at runtime — every combo addition must go through source code.
final Map<String, SpellEffect> predefinedCombinations =
    Map<String, SpellEffect>.unmodifiable(_rawCombinations);

/// Look up a combo by its constituent words, ignoring order.
/// Returns `null` if no predefined combination matches.
SpellEffect? lookupCombo(List<WordId> words) =>
    predefinedCombinations[comboKey(words)];
