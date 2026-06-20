import 'package:web/web.dart' as web;

/// Web alarm implementation using the Web Audio API.
///
/// Plays a short, non-annoying three-beep burst with a synthesised oscillator
/// — no bundled asset, no audio package, WASM-safe (`package:web` only, typed
/// interop, no `dynamic` dispatch per the project's WASM rules).
///
/// Browsers leave an `AudioContext` that was created without a user gesture in
/// the `suspended` state, so oscillators scheduled on it are silent. [prime] is
/// therefore called from the timer-button gesture ([start]) to create and
/// `resume()` the context up front; [playAlarm] resumes again defensively
/// before scheduling, in case the context was suspended in the meantime.
class AlarmPlayer {
  web.AudioContext? _context;
  final List<web.OscillatorNode> _oscillators = [];
  bool _isPlaying = false;

  /// Monotonic burst id so a delayed cleanup from an earlier burst can't clear
  /// the oscillator list / playing flag of a newer one (generation guard).
  int _burstId = 0;

  /// Whether an alarm burst is currently scheduled/sounding.
  bool get isPlaying => _isPlaying;

  web.AudioContext _ensureContext() => _context ??= web.AudioContext();

  /// Create and resume the audio context from a user gesture so a later
  /// gesture-less [playAlarm] is audible. Safe to call repeatedly.
  void prime() {
    final ctx = _ensureContext();
    if (ctx.state == 'suspended') ctx.resume();
  }

  /// Play three short ascending beeps.
  void playAlarm() {
    // Re-trigger cleanly if already playing.
    stopAlarm();

    final ctx = _ensureContext();
    // Resume defensively — a context can be suspended by the browser between
    // priming and firing.
    if (ctx.state == 'suspended') ctx.resume();

    _isPlaying = true;
    final burst = ++_burstId;
    _oscillators.clear();

    const beepDuration = 0.18; // seconds
    const gap = 0.12; // seconds between beeps
    const frequencies = [880.0, 988.0, 1175.0]; // A5, B5, D6 — a rising trill

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

    // Mark not-playing once the last beep would have finished — but only if no
    // newer burst has started in the meantime.
    final totalMs =
        ((frequencies.length * (beepDuration + gap)) * 1000).round();
    Future.delayed(Duration(milliseconds: totalMs), () {
      if (burst != _burstId) return; // a newer burst owns the state now
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
    _burstId++; // invalidate any pending delayed cleanup
  }

  /// Release the audio context.
  void dispose() {
    stopAlarm();
    _context?.close();
    _context = null;
  }
}
