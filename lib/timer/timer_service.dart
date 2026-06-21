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
/// LiveKit does NOT loop a participant's own `publishData` back to itself
/// (`DataReceivedEvent` fires only for *other* participants — the same reason
/// `ChatService` adds the local user's message optimistically before
/// publishing). So [start]/[cancel] apply the change locally *and* broadcast
/// it; remote participants apply it when the broadcast arrives via
/// [LiveKitService.roomTimerReceived]. Both paths funnel through [_apply], so
/// the starter and everyone else run the same transition. Last-writer-wins on a
/// fresh start.
///
/// The UI never mutates [CountdownTimerState] directly; it calls
/// [start]/[cancel] and watches [state] / [alarmActive] for rendering.
///
/// Lifecycle mirrors the other room services: created in `RoomSession.create`,
/// registered in the `Locator`, disposed on `leave`.
class TimerService {
  TimerService({
    required LiveKitService liveKitService,
    @visibleForTesting AlarmPlayer? alarmPlayer,
    @visibleForTesting DateTime Function()? now,
  })  : _liveKit = liveKitService,
        _alarm = alarmPlayer ?? AlarmPlayer(),
        _now = now ?? DateTime.now {
    state = CountdownTimerState(onFinished: _onFinished, now: _now);
    _sub = _liveKit.roomTimerReceived.listen(_apply);
  }

  final LiveKitService _liveKit;
  final AlarmPlayer _alarm;

  /// Injectable wall clock — shared with [state] so the whole service runs on
  /// one notion of "now" in tests. Used to reconstruct the absolute end instant
  /// of an incoming start (late-joiner catch-up).
  final DateTime Function() _now;

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
  /// Applies locally immediately (LiveKit won't echo our own message back) and
  /// broadcasts a `start` to everyone else. Also primes the alarm so the web
  /// audio context is created/resumed from this user-gesture call rather than
  /// at fire-time (browsers leave a gesture-less `AudioContext` suspended).
  Future<void> start(int durationSeconds) async {
    if (durationSeconds <= 0) return;
    _alarm.prime();
    final message = StartRoomTimerMessage(
      durationSeconds: durationSeconds,
      startedAtMillis: _now().millisecondsSinceEpoch,
      startedBy: _liveKit.userId,
    );
    _apply(message);
    await _liveKit.publishRoomTimer(message);
  }

  /// Cancel any running shared countdown for everyone in the room.
  Future<void> cancel() async {
    final message = CancelRoomTimerMessage(startedBy: _liveKit.userId);
    _apply(message);
    await _liveKit.publishRoomTimer(message);
  }

  /// Silence the alarm locally and clear the "Time's up!" banner.
  void dismissAlarm() {
    _alarm.stopAlarm();
    alarmActive.value = false;
  }

  /// Apply a timer transition — from our own [start]/[cancel] or a remote
  /// broadcast. The single source of truth for both paths.
  void _apply(RoomTimerMessage message) {
    switch (message) {
      case StartRoomTimerMessage(
          :final durationSeconds,
          :final startedAtMillis,
          :final startedBy,
        ):
        dismissAlarm(); // a new timer clears any lingering alarm/banner
        // Late-joiner catch-up: reconstruct the absolute end instant from the
        // sender's start time + duration and start from THAT, so a participant
        // joining mid-countdown sees the real remaining time, not a fresh full
        // duration. When the message carries no timestamp (legacy/skew-free),
        // fall back to a fresh local countdown of [durationSeconds].
        //
        // Robust to a finished timer: if the reconstructed end is already in
        // the past, CountdownTimerState.startAt fires onFinished immediately
        // (alarm + banner), matching what an always-present client would show.
        if (startedAtMillis != null) {
          final endsAt = DateTime.fromMillisecondsSinceEpoch(startedAtMillis)
              .add(Duration(seconds: durationSeconds));
          state.startAt(endsAt);
        } else {
          state.start(durationSeconds);
        }
        // Only run the 1s ticker if the countdown is actually live — a
        // late-joiner whose timer had already expired finishes synchronously
        // inside startAt and needs no ticker.
        if (state.running) {
          _startTicker();
        } else {
          _stopTicker();
        }
        _log.fine('Room timer started: ${durationSeconds}s by $startedBy');
      case CancelRoomTimerMessage(:final startedBy):
        dismissAlarm();
        state.cancel();
        _stopTicker();
        _log.fine('Room timer cancelled by $startedBy');
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
