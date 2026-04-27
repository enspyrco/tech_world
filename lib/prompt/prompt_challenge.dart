import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/prompt/spell_school.dart';

/// The closed set of prompt-engineering challenges a player can ever earn
/// a word from.
///
/// `PromptChallengeId` is the **domain type** for prompt challenges across
/// the spellbook, doors, and cast-effects pipeline. Strings only appear at
/// boundaries — Firestore on-disk format, network metadata, future STT —
/// and parse via [PromptChallengeId.parse]. Internally everything operates
/// on `PromptChallengeId`, so the compiler enforces what would otherwise
/// be runtime invariants:
///
///  * Typos can't refer to a non-existent challenge — they won't compile.
///  * Switch expressions over `PromptChallengeId` must be exhaustive —
///    adding the 19th challenge fails the build at every site that hasn't
///    handled it.
///  * The bijection with [WordId] reduces to a length assertion.
///
/// Wire format: each value owns its [wireName] (e.g.
/// `PromptChallengeId.evocationFizzbuzz.wireName == 'evocation_fizzbuzz'`).
/// Existing Firestore data parses unchanged. We can't use `enum.name`
/// directly because Dart's `constant_identifier_names` lint rejects
/// snake_case on enum values.
enum PromptChallengeId {
  evocationFizzbuzz('evocation_fizzbuzz'),
  evocationCountdown('evocation_countdown'),
  evocationDiamond('evocation_diamond'),
  divinationColor('divination_color'),
  divinationExtract('divination_extract'),
  divinationPattern('divination_pattern'),
  transmutationBullets('transmutation_bullets'),
  transmutationTable('transmutation_table'),
  transmutationJson('transmutation_json'),
  illusionPirate('illusion_pirate'),
  illusionChild('illusion_child'),
  illusionDual('illusion_dual'),
  enchantmentBrevity('enchantment_brevity'),
  enchantmentFormal('enchantment_formal'),
  enchantmentContradict('enchantment_contradict'),
  conjurationGlorp('conjuration_glorp'),
  conjurationPattern('conjuration_pattern'),
  conjurationLanguage('conjuration_language');

  const PromptChallengeId(this.wireName);

  /// On-disk / wire identifier. Stable across refactors of the Dart
  /// identifier — this is what Firestore stores.
  final String wireName;

  /// Parse a wire-format string into a [PromptChallengeId], or `null` if
  /// unknown. Use at boundaries (Firestore reads, network metadata) and
  /// decide what to do with `null` at the call site (typically log + skip
  /// for forward-compat with future challenges).
  static PromptChallengeId? parse(String wire) {
    for (final c in PromptChallengeId.values) {
      if (c.wireName == wire) return c;
    }
    return null;
  }
}

/// How a challenge's output is evaluated — determines whether we use
/// programmatic checks, an LLM judge, or both.
enum EvaluationTier {
  /// Pure programmatic checks: string contains, regex, JSON parse.
  /// No LLM judge needed — fast and deterministic.
  deterministic,

  /// Try parsing/validation first, fall back to LLM judge if needed.
  /// Good for challenges where output structure matters but exact
  /// content may vary.
  structural,

  /// Always uses an LLM judge. For challenges where "correctness"
  /// is subjective or requires understanding nuance.
  behavioral,
}

/// A prompt engineering challenge that players solve by crafting incantations.
///
/// Unlike code challenges where players write Dart, prompt challenges ask
/// players to write natural language prompts that produce a desired outcome
/// from the AI agent.
class PromptChallenge {
  /// Creates a prompt challenge.
  const PromptChallenge({
    required this.id,
    required this.title,
    required this.description,
    required this.school,
    required this.difficulty,
    required this.generationSystemPrompt,
    required this.evaluationCriteria,
    required this.evaluationPrompt,
    required this.tier,
  });

  /// Strongly-typed identifier — see [PromptChallengeId].
  final PromptChallengeId id;

  /// Display title shown to the player.
  final String title;

  /// What the player sees — explains the goal without giving away the answer.
  final String description;

  /// Which school of prompt magic this challenge belongs to.
  final SpellSchool school;

  /// Difficulty tier, reused from the code challenge system.
  final Difficulty difficulty;

  /// System prompt given to the agent when generating a response.
  ///
  /// This sets up the scenario — the player never sees it directly.
  final String generationSystemPrompt;

  /// Human-readable description of what counts as success.
  final String evaluationCriteria;

  /// Prompt template sent to the LLM judge for evaluation.
  ///
  /// The judge sees the agent's response and these criteria, but never
  /// the player's original prompt — this prevents gaming the evaluation.
  final String evaluationPrompt;

  /// Determines the evaluation strategy: deterministic, structural,
  /// or behavioral.
  final EvaluationTier tier;
}
