import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tech_world/flame/maps/door_data.dart';
import 'package:tech_world/spellbook/cast_result.dart';
import 'package:tech_world/spellbook/oracle_service.dart';
import 'package:tech_world/spellbook/predefined_words.dart';
import 'package:tech_world/spellbook/speech_cast_service.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Voice-cast affordance overlay — the moment Phase 2 makes embodied.
///
/// Composed of two pieces stacked vertically:
///
/// 1. A **mic FAB** at bottom-centre, visible only when [nearbyLockedDoor]
///    is non-null and STT is supported (web only). Tap to listen for
///    one utterance; tap again while listening to cancel.
///
/// 2. A **flash message** above the FAB that renders the result of the
///    most recent cast — success line on [CastPass], oracle-generated
///    flavor on [CastNoMatch], hint text on [CastNotLearned] /
///    [CastWrongDoor]. Auto-dismisses after [_flashDuration].
///
/// The overlay never owns the world's door state — on success it calls
/// [onCastSuccess] and the world handles the visual unlock + LiveKit
/// broadcast. Persistence (spellbook + progress) has already happened
/// inside `performCast` by the time a [CastResult] arrives here.
class SpeechCastOverlay extends StatefulWidget {
  const SpeechCastOverlay({
    super.key,
    required this.nearbyLockedDoor,
    required this.speechCast,
    required this.oracle,
    required this.onCastSuccess,
  });

  /// Source of the proximity affordance — emits the closest still-locked
  /// door within range, or `null` to hide the FAB.
  final ValueListenable<DoorData?> nearbyLockedDoor;

  /// Voice-cast pipeline. The overlay listens to its [SpeechCastService.listening]
  /// notifier for the FAB pulse.
  final SpeechCastService speechCast;

  /// Bot-mediated flavor channel. Asked for a fresh line on [CastNoMatch].
  final OracleService oracle;

  /// Called with the door that was opened on a successful cast — the
  /// world uses this to flip the door's visual state and broadcast.
  final void Function(DoorData door) onCastSuccess;

  @override
  State<SpeechCastOverlay> createState() => _SpeechCastOverlayState();
}

class _SpeechCastOverlayState extends State<SpeechCastOverlay> {
  static const _flashDuration = Duration(seconds: 3);

  String? _flashMessage;
  Color _flashColor = arcaneColor;
  bool _resolving = false;
  int _flashSeq = 0;

  Future<void> _onTapMic(DoorData door) async {
    // Tap-to-cancel — if we're already listening, the second tap stops STT.
    if (widget.speechCast.listening.value) {
      widget.speechCast.cancel();
      return;
    }
    if (_resolving) return;

    setState(() => _resolving = true);
    try {
      final result = await widget.speechCast.castAt(
        doorRequiredChallenges: door.requiredChallengeIds,
      );
      await _renderFeedback(result, door);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _renderFeedback(CastResult result, DoorData door) async {
    String text;
    Color color;

    switch (result) {
      case CastPass(:final challengeId):
        // Persistence (spellbook + progress) already ran inside
        // performCast; this just flips the world's door visual + broadcast.
        widget.onCastSuccess(door);
        // challengeToWord is total over PromptChallengeId.values, so the
        // lookup never fails for a CastPass (which carries a real
        // challenge id from a learned word).
        final word = challengeToWord[challengeId]!;
        text = '${word.id.displayName} — the door yields.';
        color = arcaneColor;
      case CastNotLearned(:final wordId):
        text = 'You have not learned ${wordId.displayName} yet.';
        color = Colors.orange.shade700;
      case CastWrongDoor():
        text = 'The door is unmoved.';
        color = Colors.blueGrey.shade700;
      case CastNoMatch(:final transcript):
        text = await widget.oracle.flavorForNoMatch(transcript: transcript);
        color = Colors.indigo.shade700;
    }

    _showFlash(text, color);
  }

  void _showFlash(String text, Color color) {
    if (!mounted) return;
    final seq = ++_flashSeq;
    setState(() {
      _flashMessage = text;
      _flashColor = color;
    });
    Future.delayed(_flashDuration, () {
      // Only clear if no newer flash has replaced this one — guards
      // against fast back-to-back casts where the second flash would
      // otherwise be cut short by the first's expiry timer.
      if (mounted && seq == _flashSeq) {
        setState(() => _flashMessage = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // The whole overlay is gated on STT support — non-web platforms
    // never show the FAB or any flash.
    if (!widget.speechCast.isSupported) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_flashMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _FlashBanner(
                          text: _flashMessage!,
                          color: _flashColor,
                        ),
                      ),
                    ValueListenableBuilder<DoorData?>(
                      valueListenable: widget.nearbyLockedDoor,
                      builder: (context, door, _) {
                        if (door == null) return const SizedBox.shrink();
                        return ValueListenableBuilder<bool>(
                          valueListenable: widget.speechCast.listening,
                          builder: (context, listening, _) => _MicButton(
                            listening: listening,
                            resolving: _resolving && !listening,
                            onTap: () => _onTapMic(door),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.listening,
    required this.resolving,
    required this.onTap,
  });

  final bool listening;
  final bool resolving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = listening
        ? Colors.redAccent.shade400
        : (resolving ? Colors.grey.shade500 : arcaneColor);

    return Tooltip(
      message: listening
          ? 'Listening… speak the word, or tap to cancel'
          : (resolving
              ? 'Casting…'
              : 'Speak a word of power'),
      child: FloatingActionButton(
        onPressed: resolving && !listening ? null : onTap,
        backgroundColor: bg,
        elevation: listening ? 8 : 4,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Icon(
            listening
                ? Icons.stop_rounded
                : (resolving ? Icons.hourglass_top_rounded : Icons.mic_rounded),
            key: ValueKey<int>(listening
                ? 1
                : (resolving ? 2 : 0)),
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class _FlashBanner extends StatelessWidget {
  const _FlashBanner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(12),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
