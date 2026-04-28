import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:tech_world/progress/progress_service.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/services/stt_service.dart';
import 'package:tech_world/spellbook/cast_effects.dart';
import 'package:tech_world/spellbook/cast_result.dart';
import 'package:tech_world/spellbook/spellbook_service.dart';

final _log = Logger('SpeechCastService');

/// Voice-cast entry-point for the UI.
///
/// Pulls one transcript from [SttService.listen] and dispatches it
/// through [performCast]. The classification + side-effect pipeline
/// lives in `cast_effects.dart` — this service is intentionally thin,
/// existing only to wire STT to the cast pipeline so tests can target
/// `performCast` directly without going through a browser-only API.
///
/// Listening state is exposed via [listening] so the overlay can render
/// a "the oracle hears you" indicator. It mirrors [SttService.listening]
/// for convenience — the UI doesn't need to import the STT layer.
class SpeechCastService {
  SpeechCastService({
    required SttService stt,
    required SpellbookService? spellbook,
    required ProgressService? progress,
  })  : _stt = stt,
        _spellbook = spellbook,
        _progress = progress;

  final SttService _stt;
  final SpellbookService? _spellbook;
  final ProgressService? _progress;

  /// `true` while the browser is actively listening for speech. Mirrors
  /// [SttService.listening] so callers can `ValueListenableBuilder` on
  /// it without importing the STT layer directly.
  ValueListenable<bool> get listening => _stt.listening;

  /// Whether speech recognition is supported in the current browser.
  /// Used by the overlay to hide the mic FAB on platforms that can't
  /// listen.
  bool get isSupported => _stt.isSupported;

  /// Cast at a door whose required challenges are
  /// [doorRequiredChallenges]. Listens once via STT, classifies the
  /// transcript, and applies side-effects on success.
  ///
  /// Returns the typed [CastResult] for the UI to switch on. Never
  /// throws — STT failures surface as [CastNoMatch] with a `null`
  /// transcript.
  Future<CastResult> castAt({
    required List<PromptChallengeId> doorRequiredChallenges,
  }) async {
    _log.fine('castAt: requesting STT transcript');
    final transcript = await _stt.listen();
    _log.fine('castAt: transcript = ${transcript ?? "(null)"}');

    return performCast(
      transcript: transcript,
      doorRequiredChallenges: doorRequiredChallenges,
      spellbook: _spellbook,
      progress: _progress,
    );
  }

  /// Cancel the in-flight STT listen, if any. Used when the player
  /// taps the mic FAB again to abort, or walks away from the door.
  void cancel() => _stt.stop();
}
