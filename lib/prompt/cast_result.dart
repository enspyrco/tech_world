/// Qualitative feedback on how a prompt "spell" performed.
///
/// Ordered from worst to best — the names evoke the magical metaphor
/// while mapping to real prompt engineering outcomes.
enum CastFeedback {
  /// The prompt was too vague for the agent to act on meaningfully.
  unclear,

  /// The prompt was clear but failed to meet the challenge criteria.
  fizzled,

  /// The prompt produced an unintended or opposite effect.
  backfired,

  /// The prompt met the challenge criteria — the spell lands.
  resonates,
}

/// The outcome of evaluating a player's prompt against a challenge.
class CastResult {
  /// Creates a cast result.
  const CastResult({
    required this.passed,
    required this.feedback,
    this.judgeReasoning,
  });

  /// Whether the challenge criteria were met.
  final bool passed;

  /// Qualitative feedback category.
  final CastFeedback feedback;

  /// Brief explanation from the judge, if available.
  ///
  /// Present for structural and behavioral tier evaluations where an LLM
  /// judge provides reasoning. Null for deterministic checks.
  final String? judgeReasoning;
}
