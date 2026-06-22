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
    registerFallbackValue(
        RoomTimerMessage.cancel(generation: 0, startedBy: 'fallback'));
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

    /// A service backed by a controllable clock. Each gets its OWN LiveKit fake
    /// so its subscription is independent (simulating a distinct peer) unless it
    /// shares [incoming] — which it does, so messages fan out to all of them.
    TimerService buildWithClock(DateTime Function() now) => TimerService(
          liveKitService: liveKit,
          alarmPlayer: alarm,
          now: now,
        );

    tearDown(() async {
      service.dispose();
      await incoming.close();
    });

    test('start publishes a relative-remaining start with our identity + gen',
        () async {
      await service.start(300);
      expect(published, hasLength(1));
      final msg = published.single;
      expect(msg, isA<StartRoomTimerMessage>());
      final start = msg as StartRoomTimerMessage;
      expect(start.remainingSeconds, 300);
      expect(start.startedBy, 'user-me');
      expect(start.generation, 1); // first timer
    });

    test('each fresh start mints a higher generation', () async {
      await service.start(60);
      await service.start(30);
      final gens = published
          .whereType<StartRoomTimerMessage>()
          .map((m) => m.generation)
          .toList();
      expect(gens, [1, 2]);
    });

    test('start applies locally immediately (LiveKit does not self-echo)',
        () async {
      final now = DateTime.fromMillisecondsSinceEpoch(5000000);
      final s = buildWithClock(() => now);
      addTearDown(s.dispose);
      await s.start(300);
      expect(s.state.running, isTrue);
      expect(s.state.remaining, const Duration(seconds: 300));
    });

    test('start primes the alarm (web audio gesture unlock)', () async {
      await service.start(60);
      expect(alarm.primeCount, 1);
    });

    test('cancel publishes a cancel carrying the current generation', () async {
      await service.start(60);
      expect(service.state.running, isTrue);
      await service.cancel();
      final cancel = published.last;
      expect(cancel.action, TimerAction.cancel);
      expect(cancel.startedBy, 'user-me');
      expect(cancel.generation, 1);
      expect(service.state.running, isFalse);
    });

    test('cancel with no running timer is a no-op (nothing published)',
        () async {
      await service.cancel();
      expect(published, isEmpty);
      expect(service.state.running, isFalse);
    });

    test('an incoming start message begins the local countdown', () async {
      final now = DateTime.fromMillisecondsSinceEpoch(5000000);
      final s = buildWithClock(() => now);
      addTearDown(s.dispose);
      incoming.add(RoomTimerMessage.start(
        remainingSeconds: 120,
        generation: 1,
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
        remainingSeconds: 120,
        generation: 1,
        startedBy: 'a',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(s.state.running, isTrue);

      incoming.add(RoomTimerMessage.cancel(generation: 1, startedBy: 'a'));
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

    // ------------------------------------------------------------------
    // Late-joiner DELIVERY — the whole point of the feature. LiveKit does not
    // replay past messages, so the running peer must REPUBLISH on join. These
    // tests exercise the publish→receive handoff, not a hand-fed injection.
    // ------------------------------------------------------------------
    group('late-joiner delivery (republish on join)', () {
      test(
          'republishForJoiner emits the running timer; a fresh peer receiving '
          'it via the stream catches up to the correct remaining', () async {
        // Peer A starts a 120s timer, then 30s elapse on A's clock.
        var aNow = DateTime.fromMillisecondsSinceEpoch(1000000);
        final peerA = buildWithClock(() => aNow);
        addTearDown(peerA.dispose);
        await peerA.start(120);
        aNow = aNow.add(const Duration(seconds: 30));
        peerA.state.tick(); // A now shows 90s
        expect(peerA.state.remaining, const Duration(seconds: 90));

        published.clear();

        // A new participant joins → A republishes the running timer.
        await peerA.republishForJoiner();
        expect(published, hasLength(1));
        final resync = published.single as StartRoomTimerMessage;
        expect(resync.remainingSeconds, 90); // current remaining, not 120
        expect(resync.generation, 1); // same generation — idempotent

        // The joiner (its own clock, never present at start) receives it.
        final joinerNow = DateTime.fromMillisecondsSinceEpoch(9999999999);
        final joiner = buildWithClock(() => joinerNow);
        addTearDown(joiner.dispose);
        incoming.add(resync);
        await Future<void>.delayed(Duration.zero);

        expect(joiner.state.running, isTrue);
        expect(joiner.state.remaining, const Duration(seconds: 90));
      });

      test('republishForJoiner is a no-op when no timer is running', () async {
        await service.republishForJoiner();
        expect(published, isEmpty);
      });

      test('republishForJoiner is a no-op after the timer was cancelled',
          () async {
        var now = DateTime.fromMillisecondsSinceEpoch(0);
        final s = buildWithClock(() => now);
        addTearDown(s.dispose);
        await s.start(60);
        await s.cancel();
        published.clear();
        await s.republishForJoiner();
        expect(published, isEmpty);
      });
    });

    // ------------------------------------------------------------------
    // Clock skew — the relative-remaining wire is skew-immune by construction.
    // ------------------------------------------------------------------
    test(
        'skew-immune: a start authored on a wildly different sender clock still '
        'yields correct remaining on the receiver clock', () async {
      // Receiver's clock is far in the future relative to the (irrelevant)
      // sender clock — with an absolute timestamp this would be catastrophic;
      // with relative remaining it is exactly right.
      final receiverNow = DateTime.fromMillisecondsSinceEpoch(9999999999);
      final receiver = buildWithClock(() => receiverNow);
      addTearDown(receiver.dispose);

      incoming.add(RoomTimerMessage.start(
        remainingSeconds: 75,
        generation: 1,
        startedBy: 'sender-with-skewed-clock',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(receiver.state.running, isTrue);
      expect(receiver.state.remaining, const Duration(seconds: 75));
    });

    // ------------------------------------------------------------------
    // Arrival-order races — resolved by the monotonic generation guard.
    // ------------------------------------------------------------------
    group('generation race resolution', () {
      test('a stale cancel arriving after a newer start is ignored', () async {
        final now = DateTime.fromMillisecondsSinceEpoch(0);
        final s = buildWithClock(() => now);
        addTearDown(s.dispose);

        // Newer start (gen 2) is applied.
        incoming.add(RoomTimerMessage.start(
          remainingSeconds: 60,
          generation: 2,
          startedBy: 'a',
        ));
        await Future<void>.delayed(Duration.zero);
        expect(s.state.running, isTrue);

        // A stale cancel for the OLD timer (gen 1) arrives late — must NOT wipe
        // the newer running timer.
        incoming.add(RoomTimerMessage.cancel(generation: 1, startedBy: 'b'));
        await Future<void>.delayed(Duration.zero);
        expect(s.state.running, isTrue);
        expect(s.state.remaining, const Duration(seconds: 60));
      });

      test('a stale start arriving after a cancel does not resurrect the timer',
          () async {
        final now = DateTime.fromMillisecondsSinceEpoch(0);
        final s = buildWithClock(() => now);
        addTearDown(s.dispose);

        incoming.add(RoomTimerMessage.start(
          remainingSeconds: 60,
          generation: 1,
          startedBy: 'a',
        ));
        await Future<void>.delayed(Duration.zero);
        incoming.add(RoomTimerMessage.cancel(generation: 1, startedBy: 'a'));
        await Future<void>.delayed(Duration.zero);
        expect(s.state.running, isFalse);

        // A late republish of the SAME (now-cancelled) generation arrives —
        // must not bring the timer back.
        incoming.add(RoomTimerMessage.start(
          remainingSeconds: 40,
          generation: 1,
          startedBy: 'a',
        ));
        await Future<void>.delayed(Duration.zero);
        expect(s.state.running, isFalse);
      });

      test('a genuinely newer start after a cancel DOES start a new timer',
          () async {
        final now = DateTime.fromMillisecondsSinceEpoch(0);
        final s = buildWithClock(() => now);
        addTearDown(s.dispose);

        incoming.add(RoomTimerMessage.start(
          remainingSeconds: 60,
          generation: 1,
          startedBy: 'a',
        ));
        await Future<void>.delayed(Duration.zero);
        incoming.add(RoomTimerMessage.cancel(generation: 1, startedBy: 'a'));
        await Future<void>.delayed(Duration.zero);
        expect(s.state.running, isFalse);

        incoming.add(RoomTimerMessage.start(
          remainingSeconds: 30,
          generation: 2,
          startedBy: 'b',
        ));
        await Future<void>.delayed(Duration.zero);
        expect(s.state.running, isTrue);
        expect(s.state.remaining, const Duration(seconds: 30));
      });
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
        remainingSeconds: 60,
        generation: 1,
        startedBy: 'b',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(s.alarmActive.value, isFalse);
      expect(s.state.running, isTrue);
    });
  });
}
