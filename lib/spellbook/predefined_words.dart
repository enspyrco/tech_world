import 'package:tech_world/prompt/prompt_challenge.dart';
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
    challengeId: PromptChallengeId.evocationFizzbuzz,
  ),
  WordOfPower(
    id: WordId.tempus,
    meaning: 'time',
    school: SpellSchool.evocation,
    element: SpellElement.fire,
    intensity: 1,
    role: WordRole.substance,
    challengeId: PromptChallengeId.evocationCountdown,
  ),
  WordOfPower(
    id: WordId.crystallum,
    meaning: 'crystal',
    school: SpellSchool.evocation,
    element: SpellElement.fire,
    intensity: 2,
    role: WordRole.substance,
    challengeId: PromptChallengeId.evocationDiamond,
  ),

  // Divination — water
  WordOfPower(
    id: WordId.lumen,
    meaning: 'light',
    school: SpellSchool.divination,
    element: SpellElement.water,
    intensity: 1,
    role: WordRole.substance,
    challengeId: PromptChallengeId.divinationColor,
  ),
  WordOfPower(
    id: WordId.verum,
    meaning: 'truth',
    school: SpellSchool.divination,
    element: SpellElement.water,
    intensity: 2,
    role: WordRole.modifier,
    challengeId: PromptChallengeId.divinationExtract,
  ),
  WordOfPower(
    id: WordId.oraculum,
    meaning: 'oracle',
    school: SpellSchool.divination,
    element: SpellElement.water,
    intensity: 3,
    role: WordRole.substance,
    challengeId: PromptChallengeId.divinationPattern,
  ),

  // Transmutation — earth
  WordOfPower(
    id: WordId.forma,
    meaning: 'shape',
    school: SpellSchool.transmutation,
    element: SpellElement.earth,
    intensity: 1,
    role: WordRole.substance,
    challengeId: PromptChallengeId.transmutationBullets,
  ),
  WordOfPower(
    id: WordId.structura,
    meaning: 'structure',
    school: SpellSchool.transmutation,
    element: SpellElement.earth,
    intensity: 2,
    role: WordRole.substance,
    challengeId: PromptChallengeId.transmutationTable,
  ),
  WordOfPower(
    id: WordId.muta,
    meaning: 'change',
    school: SpellSchool.transmutation,
    element: SpellElement.earth,
    intensity: 2,
    role: WordRole.action,
    challengeId: PromptChallengeId.transmutationJson,
  ),

  // Illusion — air
  WordOfPower(
    id: WordId.umbra,
    meaning: 'shadow',
    school: SpellSchool.illusion,
    element: SpellElement.air,
    intensity: 1,
    role: WordRole.substance,
    challengeId: PromptChallengeId.illusionPirate,
  ),
  WordOfPower(
    id: WordId.speculum,
    meaning: 'mirror',
    school: SpellSchool.illusion,
    element: SpellElement.air,
    intensity: 2,
    role: WordRole.substance,
    challengeId: PromptChallengeId.illusionChild,
  ),
  WordOfPower(
    id: WordId.phantasma,
    meaning: 'phantom',
    school: SpellSchool.illusion,
    element: SpellElement.air,
    intensity: 3,
    role: WordRole.substance,
    challengeId: PromptChallengeId.illusionDual,
  ),

  // Enchantment — spirit
  WordOfPower(
    id: WordId.vinculum,
    meaning: 'bond',
    school: SpellSchool.enchantment,
    element: SpellElement.spirit,
    intensity: 1,
    role: WordRole.substance,
    challengeId: PromptChallengeId.enchantmentBrevity,
  ),
  WordOfPower(
    id: WordId.libera,
    meaning: 'freedom',
    school: SpellSchool.enchantment,
    element: SpellElement.spirit,
    intensity: 2,
    role: WordRole.action,
    challengeId: PromptChallengeId.enchantmentFormal,
  ),
  WordOfPower(
    id: WordId.dominus,
    meaning: 'mastery',
    school: SpellSchool.enchantment,
    element: SpellElement.spirit,
    intensity: 3,
    role: WordRole.substance,
    challengeId: PromptChallengeId.enchantmentContradict,
  ),

  // Conjuration — void
  WordOfPower(
    id: WordId.genesis,
    meaning: 'creation',
    school: SpellSchool.conjuration,
    element: SpellElement.void_,
    intensity: 1,
    role: WordRole.action,
    challengeId: PromptChallengeId.conjurationGlorp,
  ),
  WordOfPower(
    id: WordId.exemplar,
    meaning: 'pattern',
    school: SpellSchool.conjuration,
    element: SpellElement.void_,
    intensity: 2,
    role: WordRole.substance,
    challengeId: PromptChallengeId.conjurationPattern,
  ),
  WordOfPower(
    id: WordId.lexicon,
    meaning: 'language',
    school: SpellSchool.conjuration,
    element: SpellElement.void_,
    intensity: 3,
    role: WordRole.substance,
    challengeId: PromptChallengeId.conjurationLanguage,
  ),
];

/// Lookup: [WordId] → [WordOfPower]. Total over `WordId.values` because
/// the bijection is enforced at compile time by the enum itself.
final wordById = <WordId, WordOfPower>{
  for (final w in allWords) w.id: w,
};

/// Lookup: [PromptChallengeId] → [WordOfPower]. Total over
/// `PromptChallengeId.values` because the bijection is enforced at
/// compile time by the type system, plus the construction-time
/// uniqueness of [allWords] entries.
final challengeToWord = <PromptChallengeId, WordOfPower>{
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
