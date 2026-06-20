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
      await service.start(300);
      // The starter must see its own countdown without waiting for an echo
      // that LiveKit never delivers to the sender.
      expect(service.state.running, isTrue);
      expect(service.state.remaining, const Duration(seconds: 300));
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
      incoming.add(RoomTimerMessage.start(
        durationSeconds: 120,
        startedAtMillis: 0,
        startedBy: 'someone-else',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(service.state.running, isTrue);
      expect(service.state.remaining, const Duration(seconds: 120));
    });

    test('an incoming cancel stops a running countdown', () async {
      incoming.add(RoomTimerMessage.start(
        durationSeconds: 120,
        startedAtMillis: 0,
        startedBy: 'a',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(service.state.running, isTrue);

      incoming.add(RoomTimerMessage.cancel(startedBy: 'a'));
      await Future<void>.delayed(Duration.zero);
      expect(service.state.running, isFalse);
    });

    test('reaching zero plays the alarm and sets alarmActive', () {
      service.state.start(2);
      service.state.tick();
      service.state.tick(); // hits zero -> onFinished
      expect(alarm.playCount, 1);
      expect(service.alarmActive.value, isTrue);
    });

    test('dismissAlarm stops the alarm and clears alarmActive', () {
      service.state.start(1);
      service.state.tick(); // finished
      expect(service.alarmActive.value, isTrue);

      service.dismissAlarm();
      expect(service.alarmActive.value, isFalse);
      expect(alarm.stopCount, greaterThanOrEqualTo(1));
    });

    test('a new start clears a lingering alarm banner', () async {
      service.state.start(1);
      service.state.tick(); // finished, alarmActive true
      expect(service.alarmActive.value, isTrue);

      incoming.add(RoomTimerMessage.start(
        durationSeconds: 60,
        startedAtMillis: 0,
        startedBy: 'b',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(service.alarmActive.value, isFalse);
      expect(service.state.running, isTrue);
    });
  });
}
