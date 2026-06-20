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
    test('toJson → tryParse preserves all fields', () {
      final msg = RoomTimerMessage.start(
        durationSeconds: 300,
        startedAtMillis: 1700000000000,
        startedBy: 'user-42',
      );
      final parsed = RoomTimerMessage.tryParse(msg.toJson());

      expect(parsed, isNotNull);
      expect(parsed!.action, TimerAction.start);
      expect(parsed.durationSeconds, 300);
      expect(parsed.startedAtMillis, 1700000000000);
      expect(parsed.startedBy, 'user-42');
    });

    test('start factory sets the start action', () {
      expect(
        RoomTimerMessage.start(
          durationSeconds: 60,
          startedAtMillis: 0,
          startedBy: 'a',
        ).action,
        TimerAction.start,
      );
    });
  });

  group('RoomTimerMessage cancel round-trip', () {
    test('toJson → tryParse preserves canceller', () {
      final msg = RoomTimerMessage.cancel(startedBy: 'user-7');
      final parsed = RoomTimerMessage.tryParse(msg.toJson());

      expect(parsed, isNotNull);
      expect(parsed!.action, TimerAction.cancel);
      expect(parsed.startedBy, 'user-7');
      expect(parsed.durationSeconds, isNull);
      expect(parsed.startedAtMillis, isNull);
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
      expect(parsed, isNotNull);
      expect(parsed!.durationSeconds, 120);
      expect(parsed.startedAtMillis, isNull);
    });
  });
}
