import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/timer/alarm_player.dart';
import 'package:tech_world/timer/countdown_timer_state.dart';
import 'package:tech_world/timer/room_timer_message.dart';

final _log = Logger('TimerService');

/// Room-scoped controller for the shared countdown timer.
///
/// Bridges three pieces:
///  * the network ([LiveKitService] publish/subscribe on the `room-timer`
///    topic),
///  * the pure countdown logic ([CountdownTimerState]),
///  * the alarm ([AlarmPlayer]).
///
/// Every client — including the one that pressed the button — reacts to the
/// broadcast, so all clients stay in lock-step (last-writer-wins on a fresh
/// start). The UI never mutates [CountdownTimerState] directly; it calls
/// [start]/[cancel] (which publish) and watches [state] for rendering.
///
/// Lifecycle mirrors the other room services: created in `RoomSession.create`,
/// registered in the `Locator`, disposed on `leave`.
class TimerService {
  TimerService({
    required LiveKitService liveKitService,
    @visibleForTesting AlarmPlayer? alarmPlayer,
  })  : _liveKit = liveKitService,
        _alarm = alarmPlayer ?? AlarmPlayer() {
    state = CountdownTimerState(onFinished: _onFinished);
    _sub = _liveKit.roomTimerReceived.listen(_onMessage);
  }

  final LiveKitService _liveKit;
  final AlarmPlayer _alarm;

  /// Observable countdown state for the overlay to render.
  late final CountdownTimerState state;

  /// True from the moment the countdown hits zero (alarm sounding) until the
  /// user dismisses it or a new timer starts/cancels. Drives the overlay's
  /// "Time's up!" banner so it persists after [state] stops running.
  final alarmActive = ValueNotifier<bool>(false);

  StreamSubscription<RoomTimerMessage>? _sub;
  Timer? _ticker;

  /// Start (or replace) the shared countdown for everyone in the room.
  ///
  /// Publishes a `start` message; the local countdown begins when the message
  /// echoes back through [roomTimerReceived], keeping the starter in step with
  /// everyone else.
  Future<void> start(int durationSeconds) async {
    if (durationSeconds <= 0) return;
    await _liveKit.publishRoomTimer(
      RoomTimerMessage.start(
        durationSeconds: durationSeconds,
        startedAtMillis: DateTime.now().millisecondsSinceEpoch,
        startedBy: _liveKit.userId,
      ),
    );
  }

  /// Cancel any running shared countdown for everyone in the room.
  Future<void> cancel() async {
    await _liveKit.publishRoomTimer(
      RoomTimerMessage.cancel(startedBy: _liveKit.userId),
    );
  }

  /// Silence the alarm locally and clear the "Time's up!" banner.
  void dismissAlarm() {
    _alarm.stopAlarm();
    alarmActive.value = false;
  }

  void _onMessage(RoomTimerMessage message) {
    switch (message.action) {
      case TimerAction.start:
        final duration = message.durationSeconds;
        if (duration == null || duration <= 0) return; // already gated at parse
        dismissAlarm(); // a new timer clears any lingering alarm/banner
        state.start(duration);
        _startTicker();
        _log.fine('Room timer started: ${duration}s by ${message.startedBy}');
      case TimerAction.cancel:
        dismissAlarm();
        state.cancel();
        _stopTicker();
        _log.fine('Room timer cancelled by ${message.startedBy}');
    }
  }

  void _onFinished() {
    _stopTicker();
    _alarm.playAlarm();
    alarmActive.value = true;
    _log.fine('Room timer finished — alarm played');
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => state.tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Cancel the subscription, ticker, and release the alarm.
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _stopTicker();
    _alarm.dispose();
    state.dispose();
    alarmActive.dispose();
  }
}
