import 'package:tech_world/prompt/spell_school.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// All 18 words of power, ordered by school then intensity.
///
/// Each [PromptChallenge] in `predefined_prompt_challenges.dart` earns
/// exactly one word here. The mapping is bijective — see
/// [predefined_words_test.dart].
const allWords = <WordOfPower>[
  // Evocation — fire
  WordOfPower(
    id: 'ignis',
    displayName: 'IGNIS',
    meaning: 'fire',
    school: SpellSchool.evocation,
    element: SpellElement.fire,
    intensity: 1,
    role: WordRole.substance,
    challengeId: 'evocation_fizzbuzz',
  ),
  WordOfPower(
    id: 'tempus',
    displayName: 'TEMPUS',
    meaning: 'time',
    school: SpellSchool.evocation,
    element: SpellElement.fire,
    intensity: 1,
    role: WordRole.substance,
    challengeId: 'evocation_countdown',
  ),
  WordOfPower(
    id: 'crystallum',
    displayName: 'CRYSTALLUM',
    meaning: 'crystal',
    school: SpellSchool.evocation,
    element: SpellElement.fire,
    intensity: 2,
    role: WordRole.substance,
    challengeId: 'evocation_diamond',
  ),

  // Divination — water
  WordOfPower(
    id: 'lumen',
    displayName: 'LUMEN',
    meaning: 'light',
    school: SpellSchool.divination,
    element: SpellElement.water,
    intensity: 1,
    role: WordRole.substance,
    challengeId: 'divination_color',
  ),
  WordOfPower(
    id: 'verum',
    displayName: 'VERUM',
    meaning: 'truth',
    school: SpellSchool.divination,
    element: SpellElement.water,
    intensity: 2,
    role: WordRole.modifier,
    challengeId: 'divination_extract',
  ),
  WordOfPower(
    id: 'oraculum',
    displayName: 'ORACULUM',
    meaning: 'oracle',
    school: SpellSchool.divination,
    element: SpellElement.water,
    intensity: 3,
    role: WordRole.substance,
    challengeId: 'divination_pattern',
  ),

  // Transmutation — earth
  WordOfPower(
    id: 'forma',
    displayName: 'FORMA',
    meaning: 'shape',
    school: SpellSchool.transmutation,
    element: SpellElement.earth,
    intensity: 1,
    role: WordRole.substance,
    challengeId: 'transmutation_bullets',
  ),
  WordOfPower(
    id: 'structura',
    displayName: 'STRUCTURA',
    meaning: 'structure',
    school: SpellSchool.transmutation,
    element: SpellElement.earth,
    intensity: 2,
    role: WordRole.substance,
    challengeId: 'transmutation_table',
  ),
  WordOfPower(
    id: 'muta',
    displayName: 'MUTA',
    meaning: 'change',
    school: SpellSchool.transmutation,
    element: SpellElement.earth,
    intensity: 2,
    role: WordRole.action,
    challengeId: 'transmutation_json',
  ),

  // Illusion — air
  WordOfPower(
    id: 'umbra',
    displayName: 'UMBRA',
    meaning: 'shadow',
    school: SpellSchool.illusion,
    element: SpellElement.air,
    intensity: 1,
    role: WordRole.substance,
    challengeId: 'illusion_pirate',
  ),
  WordOfPower(
    id: 'speculum',
    displayName: 'SPECULUM',
    meaning: 'mirror',
    school: SpellSchool.illusion,
    element: SpellElement.air,
    intensity: 2,
    role: WordRole.substance,
    challengeId: 'illusion_child',
  ),
  WordOfPower(
    id: 'phantasma',
    displayName: 'PHANTASMA',
    meaning: 'phantom',
    school: SpellSchool.illusion,
    element: SpellElement.air,
    intensity: 3,
    role: WordRole.substance,
    challengeId: 'illusion_dual',
  ),

  // Enchantment — spirit
  WordOfPower(
    id: 'vinculum',
    displayName: 'VINCULUM',
    meaning: 'bond',
    school: SpellSchool.enchantment,
    element: SpellElement.spirit,
    intensity: 1,
    role: WordRole.substance,
    challengeId: 'enchantment_brevity',
  ),
  WordOfPower(
    id: 'libera',
    displayName: 'LIBERA',
    meaning: 'freedom',
    school: SpellSchool.enchantment,
    element: SpellElement.spirit,
    intensity: 2,
    role: WordRole.action,
    challengeId: 'enchantment_formal',
  ),
  WordOfPower(
    id: 'dominus',
    displayName: 'DOMINUS',
    meaning: 'mastery',
    school: SpellSchool.enchantment,
    element: SpellElement.spirit,
    intensity: 3,
    role: WordRole.substance,
    challengeId: 'enchantment_contradict',
  ),

  // Conjuration — void
  WordOfPower(
    id: 'genesis',
    displayName: 'GENESIS',
    meaning: 'creation',
    school: SpellSchool.conjuration,
    element: SpellElement.void_,
    intensity: 1,
    role: WordRole.action,
    challengeId: 'conjuration_glorp',
  ),
  WordOfPower(
    id: 'exemplar',
    displayName: 'EXEMPLAR',
    meaning: 'pattern',
    school: SpellSchool.conjuration,
    element: SpellElement.void_,
    intensity: 2,
    role: WordRole.substance,
    challengeId: 'conjuration_pattern',
  ),
  WordOfPower(
    id: 'lexicon',
    displayName: 'LEXICON',
    meaning: 'language',
    school: SpellSchool.conjuration,
    element: SpellElement.void_,
    intensity: 3,
    role: WordRole.substance,
    challengeId: 'conjuration_language',
  ),
];

/// Lookup: word id → [WordOfPower]. O(1) at call sites.
final wordById = <String, WordOfPower>{
  for (final w in allWords) w.id: w,
};

/// Lookup: challenge id → [WordOfPower]. Earned on challenge completion.
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
