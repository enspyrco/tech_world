import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/prompt/spell_school.dart';

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

  /// Unique identifier for this challenge.
  final String id;

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
