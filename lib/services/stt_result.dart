/// Result of a single STT [SttService.listen] call.
///
/// Carries both the recognised transcript and the browser's confidence
/// score for the utterance — Phase 3's spell-algebra lattice classifies
/// casts on the confidence axis (see `lib/spellbook/spell_algebra.dart`),
/// but earlier consumers (door-cast, chat dictation) ignore it freely.
///
/// `confidence` is per-utterance, not per-word — the Web Speech API
/// returns one number per alternative, and we always read alternative
/// 0. If richer per-word confidence becomes useful, set
/// `maxAlternatives > 1` and synthesise from alternative disagreement.
///
/// Empty results (cancelled / unsupported / error) are surfaced as
/// [SttResult.empty] — both fields `null`. Distinguished from a
/// transcript with low confidence: the empty case means "STT didn't
/// produce a result," low confidence means "STT produced a result but
/// isn't sure about it."
class SttResult {
  const SttResult({
    required this.transcript,
    required this.confidence,
  });

  /// Sentinel used when STT is cancelled, unsupported, or errors out.
  /// Distinguished from a transcript with confidence 0 (which would
  /// be a real recognition that the browser couldn't score).
  const SttResult.empty()
      : transcript = null,
        confidence = null;

  /// The recognised utterance, or `null` if STT didn't return one.
  final String? transcript;

  /// Confidence in the recognition, `[0.0, 1.0]`, or `null` when
  /// unavailable (browser couldn't compute one, STT errored, etc.).
  final double? confidence;

  @override
  String toString() => 'SttResult(transcript: $transcript, '
      'confidence: ${confidence?.toStringAsFixed(2) ?? "n/a"})';
}
