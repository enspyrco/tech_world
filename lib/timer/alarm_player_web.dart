import 'package:web/web.dart' as web;

/// Web alarm implementation using the Web Audio API.
///
/// Plays a short, non-annoying three-beep burst with a synthesised oscillator
/// — no bundled asset, no audio package, WASM-safe (`package:web` only, typed
/// interop, no `dynamic` dispatch per the project's WASM rules).
///
/// The whole burst is scheduled up front against the [web.AudioContext] clock;
/// each beep is an [web.OscillatorNode] → [web.GainNode] → destination, with a
/// quick gain ramp so beeps don't click. [stopAlarm] stops every scheduled
/// oscillator immediately.
class AlarmPlayer {
  web.AudioContext? _context;
  final List<web.OscillatorNode> _oscillators = [];
  bool _isPlaying = false;

  /// Whether an alarm burst is currently scheduled/sounding.
  bool get isPlaying => _isPlaying;

  /// Play three short ascending beeps.
  void playAlarm() {
    // Re-trigger cleanly if already playing.
    stopAlarm();

    final ctx = _context ??= web.AudioContext();
    _isPlaying = true;
    _oscillators.clear();

    const beepDuration = 0.18; // seconds
    const gap = 0.12; // seconds between beeps
    const frequencies = [880.0, 988.0, 1175.0]; // A5, B5, D6 — a quick rising trill

    final start = ctx.currentTime;
    for (var i = 0; i < frequencies.length; i++) {
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.value = frequencies[i];

      final beepStart = start + i * (beepDuration + gap);
      final beepEnd = beepStart + beepDuration;

      // Attack/decay envelope so each beep doesn't click.
      gain.gain.setValueAtTime(0.0001, beepStart);
      gain.gain.linearRampToValueAtTime(0.2, beepStart + 0.02);
      gain.gain.linearRampToValueAtTime(0.0001, beepEnd);

      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(beepStart);
      osc.stop(beepEnd);
      _oscillators.add(osc);
    }

    // Mark not-playing once the last beep would have finished.
    final totalMs =
        ((frequencies.length * (beepDuration + gap)) * 1000).round();
    Future.delayed(Duration(milliseconds: totalMs), () {
      _isPlaying = false;
      _oscillators.clear();
    });
  }

  /// Stop every scheduled oscillator immediately.
  void stopAlarm() {
    for (final osc in _oscillators) {
      try {
        osc.stop();
      } catch (_) {
        // Already stopped/expired — safe to ignore.
      }
    }
    _oscillators.clear();
    _isPlaying = false;
  }

  /// Release the audio context.
  void dispose() {
    stopAlarm();
    _context?.close();
    _context = null;
  }
}
