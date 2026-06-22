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
        remainingSeconds: 300,
        generation: 7,
        startedBy: 'user-42',
      );
      final parsed = RoomTimerMessage.tryParse(msg.toJson());

      expect(parsed, isA<StartRoomTimerMessage>());
      final start = parsed! as StartRoomTimerMessage;
      expect(start.action, TimerAction.start);
      expect(start.remainingSeconds, 300);
      expect(start.generation, 7);
      expect(start.startedBy, 'user-42');
    });

    test('start factory builds a StartRoomTimerMessage', () {
      final msg = RoomTimerMessage.start(
        remainingSeconds: 60,
        generation: 1,
        startedBy: 'a',
      );
      expect(msg, isA<StartRoomTimerMessage>());
      expect(msg.action, TimerAction.start);
    });

    test('the wire carries RELATIVE remaining, not an absolute timestamp', () {
      final json = RoomTimerMessage.start(
        remainingSeconds: 120,
        generation: 3,
        startedBy: 'a',
      ).toJson();
      expect(json['remainingSeconds'], 120);
      expect(json.containsKey('startedAtMillis'), isFalse);
      expect(json.containsKey('durationSeconds'), isFalse);
    });
  });

  group('RoomTimerMessage cancel round-trip', () {
    test('toJson → tryParse yields a Cancel variant with the canceller + gen',
        () {
      final msg = RoomTimerMessage.cancel(generation: 9, startedBy: 'user-7');
      final parsed = RoomTimerMessage.tryParse(msg.toJson());

      expect(parsed, isA<CancelRoomTimerMessage>());
      expect(parsed!.action, TimerAction.cancel);
      expect(parsed.startedBy, 'user-7');
      expect(parsed.generation, 9);
    });
  });

  group('RoomTimerMessage.tryParse rejects malformed input', () {
    test('null map', () {
      expect(RoomTimerMessage.tryParse(null), isNull);
    });

    test('missing action', () {
      expect(
        RoomTimerMessage.tryParse({'remainingSeconds': 60, 'generation': 1}),
        isNull,
      );
    });

    test('unknown action', () {
      expect(
        RoomTimerMessage.tryParse({'action': 'reset', 'generation': 1}),
        isNull,
      );
    });

    test('missing generation is rejected (start)', () {
      expect(
        RoomTimerMessage.tryParse({'action': 'start', 'remainingSeconds': 60}),
        isNull,
      );
    });

    test('missing generation is rejected (cancel)', () {
      expect(RoomTimerMessage.tryParse({'action': 'cancel'}), isNull);
    });

    test('non-int generation is rejected', () {
      expect(
        RoomTimerMessage.tryParse(
            {'action': 'cancel', 'generation': '1'}),
        isNull,
      );
    });

    test('start with no remaining is rejected', () {
      expect(
        RoomTimerMessage.tryParse({'action': 'start', 'generation': 1}),
        isNull,
      );
    });

    test('start with zero remaining is rejected', () {
      expect(
        RoomTimerMessage.tryParse(
            {'action': 'start', 'remainingSeconds': 0, 'generation': 1}),
        isNull,
      );
    });

    test('start with negative remaining is rejected', () {
      expect(
        RoomTimerMessage.tryParse(
            {'action': 'start', 'remainingSeconds': -5, 'generation': 1}),
        isNull,
      );
    });

    test('start with non-int remaining is rejected', () {
      expect(
        RoomTimerMessage.tryParse(
            {'action': 'start', 'remainingSeconds': '60', 'generation': 1}),
        isNull,
      );
    });

    // Hostile / newer-client wire shapes must yield null, never throw and tear
    // down the subscription stream.
    test('non-string action does not throw, returns null', () {
      expect(RoomTimerMessage.tryParse({'action': 42, 'generation': 1}), isNull);
      expect(
        RoomTimerMessage.tryParse({'action': true, 'generation': 1}),
        isNull,
      );
      expect(
        RoomTimerMessage.tryParse({'action': ['start'], 'generation': 1}),
        isNull,
      );
    });

    test('non-string startedBy is ignored rather than throwing', () {
      final parsed = RoomTimerMessage.tryParse({
        'action': 'start',
        'remainingSeconds': 30,
        'generation': 1,
        'startedBy': 99,
      });
      expect(parsed, isA<StartRoomTimerMessage>());
      expect(parsed!.startedBy, isNull);
    });
  });
}
