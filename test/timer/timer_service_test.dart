import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/timer/alarm_player.dart';
import 'package:tech_world/timer/room_timer_message.dart';
import 'package:tech_world/timer/timer_service.dart';

class _FakeLiveKit extends Mock implements LiveKitService {}

/// Records alarm play/stop calls so tests can assert on them. Extends the
/// (native-stub) [AlarmPlayer] so no real sound is produced.
class _SpyAlarm extends AlarmPlayer {
  int playCount = 0;
  int stopCount = 0;
  int primeCount = 0;

  @override
  void prime() => primeCount++;

  @override
  void playAlarm() => playCount++;

  @override
  void stopAlarm() => stopCount++;

  @override
  void dispose() {}
}

void main() {
  setUpAll(() {
    registerFallbackValue(RoomTimerMessage.cancel(startedBy: 'fallback'));
  });

  group('TimerService', () {
    late _FakeLiveKit liveKit;
    late StreamController<RoomTimerMessage> incoming;
    late List<RoomTimerMessage> published;
    late _SpyAlarm alarm;
    late TimerService service;

    setUp(() {
      liveKit = _FakeLiveKit();
      incoming = StreamController<RoomTimerMessage>.broadcast();
      published = [];
      alarm = _SpyAlarm();

      when(() => liveKit.userId).thenReturn('user-me');
      when(() => liveKit.roomTimerReceived)
          .thenAnswer((_) => incoming.stream);
      when(() => liveKit.publishRoomTimer(any())).thenAnswer((invocation) async {
        published.add(invocation.positionalArguments.first as RoomTimerMessage);
      });

      service = TimerService(liveKitService: liveKit, alarmPlayer: alarm);
    });

    // A service backed by a controllable clock, for late-joiner catch-up.
    TimerService buildWithClock(DateTime Function() now) => TimerService(
          liveKitService: liveKit,
          alarmPlayer: alarm,
          now: now,
        );

    tearDown(() async {
      service.dispose();
      await incoming.close();
    });

    test('start publishes a start message stamped with our identity', () async {
      await service.start(300);
      expect(published, hasLength(1));
      final msg = published.single;
      expect(msg, isA<StartRoomTimerMessage>());
      final start = msg as StartRoomTimerMessage;
      expect(start.durationSeconds, 300);
      expect(start.startedBy, 'user-me');
      expect(start.startedAtMillis, isNotNull);
    });

    test('start applies locally immediately (LiveKit does not self-echo)',
        () async {
      // Frozen clock so stamp-time == apply-time and the remaining is exact.
      final now = DateTime.fromMillisecondsSinceEpoch(5000000);
      final s = buildWithClock(() => now);
      addTearDown(s.dispose);
      await s.start(300);
      // The starter must see its own countdown without waiting for an echo
      // that LiveKit never delivers to the sender.
      expect(s.state.running, isTrue);
      expect(s.state.remaining, const Duration(seconds: 300));
    });

    test('start primes the alarm (web audio gesture unlock)', () async {
      await service.start(60);
      expect(alarm.primeCount, 1);
    });

    test('cancel publishes a cancel message and stops locally', () async {
      await service.start(60);
      expect(service.state.running, isTrue);
      await service.cancel();
      expect(published.last.action, TimerAction.cancel);
      expect(published.last.startedBy, 'user-me');
      expect(service.state.running, isFalse);
    });

    test('an incoming start message begins the local countdown', () async {
      // A just-started timer (startedAtMillis == now) gives the full duration.
      final now = DateTime.fromMillisecondsSinceEpoch(5000000);
      final s = buildWithClock(() => now);
      addTearDown(s.dispose);
      incoming.add(RoomTimerMessage.start(
        durationSeconds: 120,
        startedAtMillis: now.millisecondsSinceEpoch,
        startedBy: 'someone-else',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(s.state.running, isTrue);
      expect(s.state.remaining, const Duration(seconds: 120));
    });

    test('an incoming cancel stops a running countdown', () async {
      final now = DateTime.fromMillisecondsSinceEpoch(5000000);
      final s = buildWithClock(() => now);
      addTearDown(s.dispose);
      incoming.add(RoomTimerMessage.start(
        durationSeconds: 120,
        startedAtMillis: now.millisecondsSinceEpoch,
        startedBy: 'a',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(s.state.running, isTrue);

      incoming.add(RoomTimerMessage.cancel(startedBy: 'a'));
      await Future<void>.delayed(Duration.zero);
      expect(s.state.running, isFalse);
    });

    test('reaching zero plays the alarm and sets alarmActive', () {
      var now = DateTime.fromMillisecondsSinceEpoch(0);
      final s = buildWithClock(() => now);
      addTearDown(s.dispose);
      s.state.start(2);
      now = now.add(const Duration(seconds: 2));
      s.state.tick(); // hits zero -> onFinished
      expect(alarm.playCount, 1);
      expect(s.alarmActive.value, isTrue);
    });

    test('dismissAlarm stops the alarm and clears alarmActive', () {
      var now = DateTime.fromMillisecondsSinceEpoch(0);
      final s = buildWithClock(() => now);
      addTearDown(s.dispose);
      s.state.start(1);
      now = now.add(const Duration(seconds: 1));
      s.state.tick(); // finished
      expect(s.alarmActive.value, isTrue);

      s.dismissAlarm();
      expect(s.alarmActive.value, isFalse);
      expect(alarm.stopCount, greaterThanOrEqualTo(1));
    });

    test(
        'a late joiner catches up: an incoming start whose end is in the '
        'future yields the REMAINING time, not the full duration', () async {
      // The starter began a 120s timer 30s ago (startedAtMillis in the past).
      // A joiner receiving it now must see ~90s left.
      var now = DateTime.fromMillisecondsSinceEpoch(5000000);
      final lateJoiner = buildWithClock(() => now);
      addTearDown(lateJoiner.dispose);

      final startedAt = now.subtract(const Duration(seconds: 30));
      incoming.add(RoomTimerMessage.start(
        durationSeconds: 120,
        startedAtMillis: startedAt.millisecondsSinceEpoch,
        startedBy: 'starter',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(lateJoiner.state.running, isTrue);
      expect(lateJoiner.state.remaining, const Duration(seconds: 90));
    });

    test(
        'a late joiner whose timer already expired finishes immediately '
        '(no negative remaining)', () async {
      var now = DateTime.fromMillisecondsSinceEpoch(5000000);
      final lateJoiner = buildWithClock(() => now);
      addTearDown(lateJoiner.dispose);

      // Started 200s ago for only 60s — already over.
      final startedAt = now.subtract(const Duration(seconds: 200));
      incoming.add(RoomTimerMessage.start(
        durationSeconds: 60,
        startedAtMillis: startedAt.millisecondsSinceEpoch,
        startedBy: 'starter',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(lateJoiner.state.running, isFalse);
      expect(lateJoiner.state.remaining, Duration.zero);
    });

    test(
        'an incoming start WITHOUT startedAtMillis falls back to a fresh '
        'full-duration countdown', () async {
      var now = DateTime.fromMillisecondsSinceEpoch(5000000);
      final joiner = buildWithClock(() => now);
      addTearDown(joiner.dispose);

      // Legacy / skew-free message with no timestamp.
      incoming.add(const StartRoomTimerMessage(
        durationSeconds: 45,
        startedBy: 'legacy',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(joiner.state.running, isTrue);
      expect(joiner.state.remaining, const Duration(seconds: 45));
    });

    test('a new start clears a lingering alarm banner', () async {
      var now = DateTime.fromMillisecondsSinceEpoch(0);
      final s = buildWithClock(() => now);
      addTearDown(s.dispose);
      s.state.start(1);
      now = now.add(const Duration(seconds: 1));
      s.state.tick(); // finished, alarmActive true
      expect(s.alarmActive.value, isTrue);

      incoming.add(RoomTimerMessage.start(
        durationSeconds: 60,
        startedAtMillis: now.millisecondsSinceEpoch,
        startedBy: 'b',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(s.alarmActive.value, isFalse);
      expect(s.state.running, isTrue);
    });
  });
}
