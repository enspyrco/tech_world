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
  CountdownTimerState({this.onFinished});

  /// Invoked exactly once each time the countdown reaches zero (the tick that
  /// crosses from a positive remaining to zero). Used to fire the alarm.
  final VoidCallback? onFinished;

  Duration _remaining = Duration.zero;
  bool _running = false;

  /// Time left on the countdown. [Duration.zero] when not running.
  Duration get remaining => _remaining;

  /// Whether a countdown is currently active.
  bool get running => _running;

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

  /// Begin (or restart) the countdown at [durationSeconds].
  ///
  /// Replaces any running countdown — the shared timer is last-writer-wins, so
  /// a fresh start from any participant simply supersedes the current one.
  /// A non-positive [durationSeconds] is a no-op (the wire boundary already
  /// rejects these; this is defence in depth).
  void start(int durationSeconds) {
    if (durationSeconds <= 0) return;
    _remaining = Duration(seconds: durationSeconds);
    _running = true;
    notifyListeners();
  }

  /// Stop the countdown without firing [onFinished] (an explicit cancel).
  void cancel() {
    if (!_running) return;
    _running = false;
    _remaining = Duration.zero;
    notifyListeners();
  }

  /// Advance the countdown by [step] (default one second).
  ///
  /// No-op when not running. When the decrement reaches or crosses zero, the
  /// countdown stops, [onFinished] fires once, and listeners are notified.
  void tick([Duration step = const Duration(seconds: 1)]) {
    if (!_running) return;

    final next = _remaining - step;
    if (next <= Duration.zero) {
      _remaining = Duration.zero;
      _running = false;
      notifyListeners();
      onFinished?.call();
      return;
    }

    _remaining = next;
    notifyListeners();
  }
}
