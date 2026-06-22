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

  /// The highest timer generation this service has applied. Messages with an
  /// older generation are dropped (arrival-order race resolution). A fresh
  /// local [start] mints the next generation; an incoming `start` adopts the
  /// sender's generation if it is newer.
  int _generation = 0;

  /// The generation of the currently running (or most-recently cancelled)
  /// timer, used when republishing on join. Null when no timer has run.
  int? _currentGeneration;

  /// The highest generation that has been *cancelled*. A `start` at or below
  /// this is refused, so a late republish of an already-cancelled timer (which
  /// carries the same generation) can't resurrect it. -1 means none cancelled.
  int _cancelledGeneration = -1;

  /// Start (or replace) the shared countdown for everyone in the room.
  ///
  /// Applies locally immediately (LiveKit won't echo our own message back) and
  /// broadcasts a `start` to everyone else. Also primes the alarm so the web
  /// audio context is created/resumed from this user-gesture call rather than
  /// at fire-time (browsers leave a gesture-less `AudioContext` suspended).
  Future<void> start(int durationSeconds) async {
    if (durationSeconds <= 0) return;
    _alarm.prime();
    // A fresh start mints the next generation, superseding any running timer.
    final message = StartRoomTimerMessage(
      remainingSeconds: durationSeconds,
      generation: _generation + 1,
      startedBy: _liveKit.userId,
    );
    _apply(message);
    await _liveKit.publishRoomTimer(message);
  }

  /// Cancel any running shared countdown for everyone in the room.
  ///
  /// No-op if no timer is running — there is no generation to cancel, and
  /// publishing a cancel for a never-started timer would be meaningless.
  Future<void> cancel() async {
    final generation = _currentGeneration;
    if (generation == null || !state.running) return;
    final message = CancelRoomTimerMessage(
      generation: generation,
      startedBy: _liveKit.userId,
    );
    _apply(message);
    await _liveKit.publishRoomTimer(message);
  }

  /// Republish the currently running timer so a participant who just joined the
  /// room receives it — LiveKit data channels do NOT replay past messages, so
  /// without this a late joiner would see idle state forever.
  ///
  /// Sends the *current* remaining and the *current* generation, so the message
  /// is idempotent: if several peers republish on the same join they all carry
  /// the same generation and remaining (modulo ~1s rounding), and the joiner's
  /// generation guard keeps only the first. No-op when no timer is running.
  ///
  /// Wired into the participant-joined handler (mirrors how `publishMapInfo` is
  /// re-sent on join so a new peer learns the current map).
  Future<void> republishForJoiner() async {
    final generation = _currentGeneration;
    if (generation == null || !state.running) return;
    final remaining = state.remainingSecondsCeil;
    if (remaining <= 0) return;
    final message = StartRoomTimerMessage(
      remainingSeconds: remaining,
      generation: generation,
      startedBy: _liveKit.userId,
    );
    // Do NOT _apply locally — we are already running this timer; this is purely
    // an outbound resync for others.
    await _liveKit.publishRoomTimer(message);
    _log.fine('Republished running timer (gen $generation, ${remaining}s) '
        'for a late joiner');
  }

  /// Silence the alarm locally and clear the "Time's up!" banner.
  void dismissAlarm() {
    _alarm.stopAlarm();
    alarmActive.value = false;
  }

  /// Apply a timer transition — from our own [start]/[cancel] or a remote
  /// broadcast. The single source of truth for both paths.
  void _apply(RoomTimerMessage message) {
    // Arrival-order race guard. Drop any message older than the highest
    // generation we have applied — a stale cancel can't wipe a newer start, and
    // a resync start can't resurrect a cancelled timer. Equal generations are
    // allowed through: that is the idempotent republish path (a peer resending
    // the timer we already run; applying it just re-derives the same endsAt).
    if (message.generation < _generation) {
      _log.fine('Dropping stale timer message: gen ${message.generation} '
          '< current $_generation');
      return;
    }
    _generation = message.generation;

    switch (message) {
      case StartRoomTimerMessage(:final remainingSeconds, :final startedBy):
        // Refuse a start at or below a cancelled generation — a late republish
        // of an already-cancelled timer carries the same generation and must
        // not resurrect it.
        if (message.generation <= _cancelledGeneration) {
          _log.fine('Dropping start for cancelled gen ${message.generation}');
          return;
        }
        _currentGeneration = message.generation;
        dismissAlarm(); // a new timer clears any lingering alarm/banner
        // Skew-immune catch-up: the wire carries the remaining time as of send.
        // We anchor it to OUR OWN clock (endsAt = now + remaining), so a
        // participant joining mid-countdown sees the real remaining without
        // depending on the sender's wall clock matching ours.
        final endsAt = _now().add(Duration(seconds: remainingSeconds));
        state.startAt(endsAt);
        // Only run the 1s ticker if the countdown is actually live — a joiner
        // whose timer had already expired finishes synchronously inside startAt
        // and needs no ticker.
        if (state.running) {
          _startTicker();
        } else {
          _stopTicker();
        }
        _log.fine('Room timer started: ${remainingSeconds}s by $startedBy '
            '(gen ${message.generation})');
      case CancelRoomTimerMessage(:final startedBy):
        _currentGeneration = message.generation;
        if (message.generation > _cancelledGeneration) {
          _cancelledGeneration = message.generation;
        }
        dismissAlarm();
        state.cancel();
        _stopTicker();
        _log.fine('Room timer cancelled by $startedBy '
            '(gen ${message.generation})');
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
