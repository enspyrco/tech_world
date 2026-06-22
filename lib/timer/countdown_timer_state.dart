import 'package:flutter/foundation.dart';

/// Pure, Flame-free, network-free countdown state for the shared room timer.
///
/// Holds only the observable countdown — the remaining time and whether a
/// countdown is running — and the logic for advancing it one tick at a time.
/// It deliberately owns no `Timer`: the *driver* (a [Timer.periodic] in
/// `TimerService`, or a test) calls [tick] once per second. Keeping the clock
/// outside makes "start → remaining decreases → hits zero → fires finished"
/// trivially unit-testable without real time passing.
///
/// Extends [ChangeNotifier] (foundation only, no widgets) so the overlay can
/// rebuild via a `ListenableBuilder`/`AnimatedBuilder` and the repo's existing
/// notifier idiom carries over.
class CountdownTimerState extends ChangeNotifier {
  CountdownTimerState({this.onFinished, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// Invoked exactly once each time the countdown reaches zero (the tick that
  /// crosses from a positive remaining to zero). Used to fire the alarm.
  final VoidCallback? onFinished;

  /// Injectable wall clock — defaults to [DateTime.now]. Tests pass a
  /// controllable closure so "20 seconds have elapsed" needs no real time.
  /// The countdown is modelled against an absolute *end instant*, so the only
  /// time it consults is "what is now?". This is what makes late-joiner
  /// catch-up correct: a participant who joins mid-countdown computes
  /// `remaining = endsAt - now` and lands on the real remaining, never a
  /// fresh full duration.
  final DateTime Function() _now;

  /// The absolute instant the countdown finishes. Null when not running.
  /// This — not a decrementing counter — is the source of truth; [remaining]
  /// is always re-derived from it so skipped ticks / late joins can't drift.
  DateTime? _endsAt;

  Duration _remaining = Duration.zero;
  bool _running = false;

  /// Time left on the countdown. [Duration.zero] when not running.
  Duration get remaining => _remaining;

  /// Whether a countdown is currently active.
  bool get running => _running;

  /// The current remaining time rounded UP to whole seconds, for republishing
  /// the running timer to a late joiner. Rounding up (not down) means a joiner
  /// never sees *less* time than the room actually has — at worst a sub-second
  /// over-count that the next tick corrects. Returns 0 when not running.
  int get remainingSecondsCeil =>
      _running ? (_remaining.inMilliseconds / 1000).ceil() : 0;

  /// Remaining time formatted as `mm:ss` (e.g. `03:07`), zero-padded.
  ///
  /// Rounds up so a remaining of 4.2s reads `00:05`, matching what a user
  /// expects from a wall clock counting down — the displayed number is the
  /// seconds you still have, not the seconds already elapsed.
  String get formatted {
    final totalSeconds = (_remaining.inMilliseconds / 1000).ceil();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  /// Begin (or restart) a countdown that finishes [durationSeconds] from *now*.
  ///
  /// Replaces any running countdown — the shared timer is last-writer-wins, so
  /// a fresh start from any participant simply supersedes the current one.
  /// A non-positive [durationSeconds] is a no-op (the wire boundary already
  /// rejects these; this is defence in depth).
  ///
  /// Equivalent to `startAt(now + durationSeconds)`; the absolute end instant
  /// is the real state.
  void start(int durationSeconds) {
    if (durationSeconds <= 0) return;
    // Snapshot now ONCE so endsAt and the initial remaining are computed from
    // the same instant — otherwise a freshly-started 180s timer reads as
    // 179.999s on the very next clock read.
    final now = _now();
    _endsAt = now.add(Duration(seconds: durationSeconds));
    _remaining = Duration(seconds: durationSeconds);
    _running = true;
    notifyListeners();
  }

  /// Begin (or restart) a countdown that finishes at the absolute [endsAt].
  ///
  /// This is the late-joiner entry point: a participant joining mid-countdown
  /// knows the *end instant* (reconstructed from the broadcast start time +
  /// duration) and starts from it, so [remaining] reflects the true time left
  /// rather than a fresh full duration. If [endsAt] is already in the past the
  /// countdown finishes immediately — [onFinished] fires and the alarm sounds,
  /// matching what would have happened had this client been present all along.
  void startAt(DateTime endsAt) {
    _endsAt = endsAt;
    _remaining = _clampedRemaining(endsAt);
    if (_remaining <= Duration.zero) {
      // Already over — finish synchronously without leaving a running timer.
      _endsAt = null;
      _remaining = Duration.zero;
      _running = false;
      notifyListeners();
      onFinished?.call();
      return;
    }
    _running = true;
    notifyListeners();
  }

  /// Stop the countdown without firing [onFinished] (an explicit cancel).
  void cancel() {
    if (!_running) return;
    _running = false;
    _endsAt = null;
    _remaining = Duration.zero;
    notifyListeners();
  }

  /// Re-derive [remaining] from the clock and the absolute end instant.
  ///
  /// Remaining is always recomputed as `endsAt - now`, so the countdown is
  /// self-correcting against skipped beats (a backgrounded tab), a slow ticker,
  /// or a late join — there is no per-tick decrement to drift. No-op when not
  /// running. When now reaches or crosses the end instant the countdown stops,
  /// [onFinished] fires once, and listeners are notified.
  void tick() {
    final endsAt = _endsAt;
    if (!_running || endsAt == null) return;

    final next = _clampedRemaining(endsAt);
    if (next <= Duration.zero) {
      _endsAt = null;
      _remaining = Duration.zero;
      _running = false;
      notifyListeners();
      onFinished?.call();
      return;
    }

    _remaining = next;
    notifyListeners();
  }

  /// Time from now until [endsAt], never negative.
  Duration _clampedRemaining(DateTime endsAt) {
    final left = endsAt.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }
}
