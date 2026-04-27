import 'package:tech_world/prompt/spell_school.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// All 18 words of power, ordered by school then intensity.
///
/// Each [PromptChallenge] in `predefined_prompt_challenges.dart` earns
/// exactly one word here. The mapping is bijective — see
/// [predefined_words_test.dart] (the bijection collapses to a single
/// length assertion now that `id` is a [WordId] enum: uniqueness is
/// guaranteed by the type system).
const allWords = <WordOfPower>[
  // Evocation — fire
  WordOfPower(
    id: WordId.ignis,
    meaning: 'fire',
    school: SpellSchool.evocation,
    element: SpellElement.fire,
    intensity: 1,
    role: WordRole.substance,
    challengeId: 'evocation_fizzbuzz',
  ),
  WordOfPower(
    id: WordId.tempus,
    meaning: 'time',
    school: SpellSchool.evocation,
    element: SpellElement.fire,
    intensity: 1,
    role: WordRole.substance,
    challengeId: 'evocation_countdown',
  ),
  WordOfPower(
    id: WordId.crystallum,
    meaning: 'crystal',
    school: SpellSchool.evocation,
    element: SpellElement.fire,
    intensity: 2,
    role: WordRole.substance,
    challengeId: 'evocation_diamond',
  ),

  // Divination — water
  WordOfPower(
    id: WordId.lumen,
    meaning: 'light',
    school: SpellSchool.divination,
    element: SpellElement.water,
    intensity: 1,
    role: WordRole.substance,
    challengeId: 'divination_color',
  ),
  WordOfPower(
    id: WordId.verum,
    meaning: 'truth',
    school: SpellSchool.divination,
    element: SpellElement.water,
    intensity: 2,
    role: WordRole.modifier,
    challengeId: 'divination_extract',
  ),
  WordOfPower(
    id: WordId.oraculum,
    meaning: 'oracle',
    school: SpellSchool.divination,
    element: SpellElement.water,
    intensity: 3,
    role: WordRole.substance,
    challengeId: 'divination_pattern',
  ),

  // Transmutation — earth
  WordOfPower(
    id: WordId.forma,
    meaning: 'shape',
    school: SpellSchool.transmutation,
    element: SpellElement.earth,
    intensity: 1,
    role: WordRole.substance,
    challengeId: 'transmutation_bullets',
  ),
  WordOfPower(
    id: WordId.structura,
    meaning: 'structure',
    school: SpellSchool.transmutation,
    element: SpellElement.earth,
    intensity: 2,
    role: WordRole.substance,
    challengeId: 'transmutation_table',
  ),
  WordOfPower(
    id: WordId.muta,
    meaning: 'change',
    school: SpellSchool.transmutation,
    element: SpellElement.earth,
    intensity: 2,
    role: WordRole.action,
    challengeId: 'transmutation_json',
  ),

  // Illusion — air
  WordOfPower(
    id: WordId.umbra,
    meaning: 'shadow',
    school: SpellSchool.illusion,
    element: SpellElement.air,
    intensity: 1,
    role: WordRole.substance,
    challengeId: 'illusion_pirate',
  ),
  WordOfPower(
    id: WordId.speculum,
    meaning: 'mirror',
    school: SpellSchool.illusion,
    element: SpellElement.air,
    intensity: 2,
    role: WordRole.substance,
    challengeId: 'illusion_child',
  ),
  WordOfPower(
    id: WordId.phantasma,
    meaning: 'phantom',
    school: SpellSchool.illusion,
    element: SpellElement.air,
    intensity: 3,
    role: WordRole.substance,
    challengeId: 'illusion_dual',
  ),

  // Enchantment — spirit
  WordOfPower(
    id: WordId.vinculum,
    meaning: 'bond',
    school: SpellSchool.enchantment,
    element: SpellElement.spirit,
    intensity: 1,
    role: WordRole.substance,
    challengeId: 'enchantment_brevity',
  ),
  WordOfPower(
    id: WordId.libera,
    meaning: 'freedom',
    school: SpellSchool.enchantment,
    element: SpellElement.spirit,
    intensity: 2,
    role: WordRole.action,
    challengeId: 'enchantment_formal',
  ),
  WordOfPower(
    id: WordId.dominus,
    meaning: 'mastery',
    school: SpellSchool.enchantment,
    element: SpellElement.spirit,
    intensity: 3,
    role: WordRole.substance,
    challengeId: 'enchantment_contradict',
  ),

  // Conjuration — void
  WordOfPower(
    id: WordId.genesis,
    meaning: 'creation',
    school: SpellSchool.conjuration,
    element: SpellElement.void_,
    intensity: 1,
    role: WordRole.action,
    challengeId: 'conjuration_glorp',
  ),
  WordOfPower(
    id: WordId.exemplar,
    meaning: 'pattern',
    school: SpellSchool.conjuration,
    element: SpellElement.void_,
    intensity: 2,
    role: WordRole.substance,
    challengeId: 'conjuration_pattern',
  ),
  WordOfPower(
    id: WordId.lexicon,
    meaning: 'language',
    school: SpellSchool.conjuration,
    element: SpellElement.void_,
    intensity: 3,
    role: WordRole.substance,
    challengeId: 'conjuration_language',
  ),
];

/// Lookup: [WordId] → [WordOfPower]. Total over `WordId.values` because
/// the bijection is enforced at compile time by the enum itself.
final wordById = <WordId, WordOfPower>{
  for (final w in allWords) w.id: w,
};

/// Lookup: challenge id (still stringly-typed, lives outside the
/// spellbook module) → [WordOfPower].
final challengeToWord = <String, WordOfPower>{
  for (final w in allWords) w.challengeId: w,
};

/// Element associated with each [SpellSchool] (1:1 mapping).
const schoolElement = <SpellSchool, SpellElement>{
  SpellSchool.evocation: SpellElement.fire,
  SpellSchool.divination: SpellElement.water,
  SpellSchool.transmutation: SpellElement.earth,
  SpellSchool.illusion: SpellElement.air,
  SpellSchool.enchantment: SpellElement.spirit,
  SpellSchool.conjuration: SpellElement.void_,
};
