import 'package:tech_world/prompt/cast_result.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';

/// Evaluates a player's prompt against a challenge by running generation
/// and judging steps.
///
/// The evaluation flow:
/// 1. **Generation**: Send the player's prompt to the agent with the
///    challenge's [PromptChallenge.generationSystemPrompt] as context.
/// 2. **Evaluation**: Judge the agent's response against the challenge's
///    [PromptChallenge.evaluationCriteria].
///
/// For [EvaluationTier.deterministic] challenges, step 2 uses programmatic
/// checks. For [EvaluationTier.behavioral], it always uses an LLM judge.
/// [EvaluationTier.structural] tries programmatic checks first, falling
/// back to the LLM judge.
abstract class EvaluationEngine {
  /// Evaluate a player's prompt against a challenge.
  ///
  /// Returns the agent's response text and the evaluation result as a
  /// record. The response is included so the UI can display what the
  /// agent said before showing the verdict.
  Future<(String response, CastResult result)> evaluate(
    PromptChallenge challenge,
    String playerPrompt,
  );
}

/// A mock evaluation engine for testing and offline development.
///
/// Returns preconfigured responses and results, cycling through the
/// provided [results] list. If no results are provided, defaults to
/// a passing result with [CastFeedback.resonates].
class MockEvaluationEngine extends EvaluationEngine {
  /// Creates a mock engine with optional preconfigured results.
  ///
  /// Each call to [evaluate] consumes the next entry from [results].
  /// When exhausted, wraps around to the beginning.
  MockEvaluationEngine({
    this.responseText = 'Mock agent response.',
    List<CastResult>? results,
  }) : _results = results ??
            [
              const CastResult(
                passed: true,
                feedback: CastFeedback.resonates,
              ),
            ];

  /// The response text returned by the mock agent.
  final String responseText;

  final List<CastResult> _results;
  int _callIndex = 0;

  /// How many times [evaluate] has been called.
  int get callCount => _callIndex;

  @override
  Future<(String, CastResult)> evaluate(
    PromptChallenge challenge,
    String playerPrompt,
  ) async {
    final result = _results[_callIndex % _results.length];
    _callIndex++;
    return (responseText, result);
  }
}
