import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/timer/room_timer_message.dart';

void main() {
  group('TimerAction.tryParse', () {
    for (final action in TimerAction.values) {
      test('round-trips ${action.name}', () {
        expect(TimerAction.tryParse(action.wire), equals(action));
      });
    }

    test('returns null for unknown wire', () {
      expect(TimerAction.tryParse('pause'), isNull);
    });

    test('returns null for null', () {
      expect(TimerAction.tryParse(null), isNull);
    });

    test('wire strings are stable', () {
      expect(TimerAction.start.wire, 'start');
      expect(TimerAction.cancel.wire, 'cancel');
    });
  });

  group('RoomTimerMessage start round-trip', () {
    test('toJson → tryParse preserves all fields and yields a Start variant',
        () {
      final msg = RoomTimerMessage.start(
        durationSeconds: 300,
        startedAtMillis: 1700000000000,
        startedBy: 'user-42',
      );
      final parsed = RoomTimerMessage.tryParse(msg.toJson());

      expect(parsed, isA<StartRoomTimerMessage>());
      final start = parsed! as StartRoomTimerMessage;
      expect(start.action, TimerAction.start);
      expect(start.durationSeconds, 300);
      expect(start.startedAtMillis, 1700000000000);
      expect(start.startedBy, 'user-42');
    });

    test('start factory builds a StartRoomTimerMessage', () {
      final msg = RoomTimerMessage.start(
        durationSeconds: 60,
        startedAtMillis: 0,
        startedBy: 'a',
      );
      expect(msg, isA<StartRoomTimerMessage>());
      expect(msg.action, TimerAction.start);
    });
  });

  group('RoomTimerMessage cancel round-trip', () {
    test('toJson → tryParse yields a Cancel variant with the canceller', () {
      final msg = RoomTimerMessage.cancel(startedBy: 'user-7');
      final parsed = RoomTimerMessage.tryParse(msg.toJson());

      expect(parsed, isA<CancelRoomTimerMessage>());
      expect(parsed!.action, TimerAction.cancel);
      expect(parsed.startedBy, 'user-7');
    });
  });

  group('RoomTimerMessage.tryParse rejects malformed input', () {
    test('null map', () {
      expect(RoomTimerMessage.tryParse(null), isNull);
    });

    test('missing action', () {
      expect(RoomTimerMessage.tryParse({'durationSeconds': 60}), isNull);
    });

    test('unknown action', () {
      expect(RoomTimerMessage.tryParse({'action': 'reset'}), isNull);
    });

    test('start with no duration is rejected', () {
      expect(RoomTimerMessage.tryParse({'action': 'start'}), isNull);
    });

    test('start with zero duration is rejected', () {
      expect(
        RoomTimerMessage.tryParse({'action': 'start', 'durationSeconds': 0}),
        isNull,
      );
    });

    test('start with negative duration is rejected', () {
      expect(
        RoomTimerMessage.tryParse({'action': 'start', 'durationSeconds': -5}),
        isNull,
      );
    });

    test('start with non-int duration is rejected', () {
      expect(
        RoomTimerMessage.tryParse(
            {'action': 'start', 'durationSeconds': '60'}),
        isNull,
      );
    });

    test('start tolerates a missing startedAtMillis', () {
      final parsed = RoomTimerMessage.tryParse(
          {'action': 'start', 'durationSeconds': 120});
      expect(parsed, isA<StartRoomTimerMessage>());
      final start = parsed! as StartRoomTimerMessage;
      expect(start.durationSeconds, 120);
      expect(start.startedAtMillis, isNull);
    });

    // Hostile / newer-client wire shapes must yield null, never throw and tear
    // down the subscription stream.
    test('non-string action does not throw, returns null', () {
      expect(RoomTimerMessage.tryParse({'action': 42}), isNull);
      expect(RoomTimerMessage.tryParse({'action': true}), isNull);
      expect(
        RoomTimerMessage.tryParse({'action': ['start']}),
        isNull,
      );
    });

    test('non-string startedBy is ignored rather than throwing', () {
      final parsed = RoomTimerMessage.tryParse(
        {'action': 'start', 'durationSeconds': 30, 'startedBy': 99},
      );
      expect(parsed, isA<StartRoomTimerMessage>());
      expect(parsed!.startedBy, isNull);
    });

    test('non-int startedAtMillis is ignored rather than throwing', () {
      final parsed = RoomTimerMessage.tryParse(
        {'action': 'start', 'durationSeconds': 30, 'startedAtMillis': 'soon'},
      );
      expect(parsed, isA<StartRoomTimerMessage>());
      expect((parsed! as StartRoomTimerMessage).startedAtMillis, isNull);
    });
  });
}
