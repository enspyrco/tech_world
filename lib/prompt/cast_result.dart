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
  ///
  /// [passed] is derived from [feedback]: only [CastFeedback.resonates]
  /// counts as a pass. The named parameter is accepted for backward
  /// compatibility but ignored — the canonical source of truth is the
  /// feedback enum.
  const CastResult({
    bool passed = false, // ignored — derived from feedback
    required this.feedback,
    this.judgeReasoning,
  });

  /// Whether the challenge criteria were met.
  ///
  /// Derived from [feedback] — the enum is the single source of truth.
  /// `resonates` is the only passing feedback; all others fail.
  bool get passed => feedback == CastFeedback.resonates;

  /// Qualitative feedback category.
  final CastFeedback feedback;

  /// Brief explanation from the judge, if available.
  ///
  /// Present for structural and behavioral tier evaluations where an LLM
  /// judge provides reasoning. Null for deterministic checks.
  final String? judgeReasoning;
}
