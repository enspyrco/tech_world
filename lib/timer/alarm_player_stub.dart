import 'package:flutter/services.dart';

/// Native alarm implementation.
///
/// Production is web, where [playAlarm]/[stopAlarm] use the Web Audio API (see
/// `alarm_player_web.dart`). On native (macOS/iOS/Android — dev + tests) we
/// play the platform alert sound a few times. It is fire-and-forget and short,
/// so [stopAlarm] is a no-op: there is no handle to a `SystemSound` to cancel.
class AlarmPlayer {
  /// Whether an alarm is currently sounding. Always false on native because the
  /// platform alert is fire-and-forget (no stoppable handle).
  bool get isPlaying => false;

  /// No-op on native — the platform alert needs no gesture-driven audio
  /// context (that's a web-only constraint). Present for interface parity.
  void prime() {}

  /// Play a short alarm: three spaced platform alert sounds.
  void playAlarm() {
    SystemSound.play(SystemSoundType.alert);
    Future.delayed(const Duration(milliseconds: 400),
        () => SystemSound.play(SystemSoundType.alert));
    Future.delayed(const Duration(milliseconds: 800),
        () => SystemSound.play(SystemSoundType.alert));
  }

  /// No-op on native — the platform alert cannot be cancelled mid-flight.
  void stopAlarm() {}

  /// Release resources. No-op on native.
  void dispose() {}
}
