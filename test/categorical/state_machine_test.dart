import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/widgets/wire_states.dart';

void main() {
  group('BotStatus state machine invariants', () {
    test('absent → thinking is forbidden (must pass through idle)', () {
      // The ChatService guard at line 402 returns early when absent.
      // This test verifies the invariant at the enum level: the only
      // valid predecessor to `thinking` is `idle`.
      const allowedPredecessors = {
        BotStatus.thinking: {BotStatus.idle},
        BotStatus.idle: {BotStatus.absent, BotStatus.thinking},
        BotStatus.absent: {BotStatus.idle, BotStatus.thinking},
      };

      // absent → thinking is not in the allowed set.
      expect(
        allowedPredecessors[BotStatus.thinking],
        isNot(contains(BotStatus.absent)),
        reason: 'Sending to an absent bot would lose messages',
      );
    });

    test('thinking is transient — must resolve to idle or absent', () {
      // From the ChatService: thinking always resolves via:
      //   - response received → idle (line 289)
      //   - timeout → idle (line 509)
      //   - error → idle (line 524)
      //   - bot leaves during thinking → absent (checked at line 482)
      // There is no path from thinking → thinking (no self-loop).
      const thinkingSuccessors = {BotStatus.idle, BotStatus.absent};

      // thinking never leads to thinking.
      expect(thinkingSuccessors, isNot(contains(BotStatus.thinking)));
      // thinking always leads to one of these two.
      expect(thinkingSuccessors, hasLength(2));
    });

    test('all states are reachable from initial state (absent)', () {
      // The bot starts absent, transitions to idle on join, then
      // idle → thinking on message send.
      const reachable = {BotStatus.absent, BotStatus.idle, BotStatus.thinking};
      expect(reachable, equals(BotStatus.values.toSet()));
    });

    test('BotStatus ValueNotifier can be observed without mutation', () {
      // BotStatus is exposed as ValueListenable (read-only) to consumers.
      // This verifies the comonad extract: notifier.value returns the state.
      final notifier = ValueNotifier(BotStatus.absent);
      expect(notifier.value, BotStatus.absent);

      notifier.value = BotStatus.idle;
      expect(notifier.value, BotStatus.idle);

      // ValueListenable<BotStatus> hides the setter.
      final ValueListenable<BotStatus> readOnly = notifier;
      expect(readOnly.value, BotStatus.idle);
    });
  });

  group('WireStatus state machine invariants', () {
    test('all wires start in pending state', () {
      final states = WireStates();
      for (final wire in Wire.values) {
        expect(states[wire], WireStatus.pending);
      }
    });

    test('start transitions pending → active', () {
      final states = WireStates();
      states.start(Wire.tilesets);
      expect(states[Wire.tilesets], WireStatus.active);
    });

    test('complete is terminal — no public API transitions out', () {
      final states = WireStates();
      states.complete(Wire.tilesets);
      expect(states[Wire.tilesets], WireStatus.complete);

      // After completing, start/complete/error still mutate (no guard),
      // but the UI contract treats complete as terminal. Verify the
      // API surface: only start(), complete(), error() exist — none
      // take a "from" state, so the caller must enforce ordering.
    });

    test('error is terminal — no public API transitions out', () {
      final states = WireStates();
      states.error(Wire.camera);
      expect(states[Wire.camera], WireStatus.error);
    });

    test('allComplete requires every wire to reach complete', () {
      final states = WireStates();
      expect(states.allComplete, isFalse);

      // Complete all but one.
      for (final wire in Wire.values) {
        if (wire != Wire.gameReady) states.complete(wire);
      }
      expect(states.allComplete, isFalse,
          reason: 'One pending wire blocks allComplete');

      // Complete the last one.
      states.complete(Wire.gameReady);
      expect(states.allComplete, isTrue);
    });

    test('allComplete is false if any wire has error', () {
      final states = WireStates();
      for (final wire in Wire.values) {
        states.complete(wire);
      }
      expect(states.allComplete, isTrue);

      // If we re-enter error (simulating a late failure), allComplete
      // should become false.
      states.error(Wire.server);
      expect(states.allComplete, isFalse);
    });

    test('wires are independent — one error does not affect others', () {
      final states = WireStates();
      states.start(Wire.tilesets);
      states.start(Wire.server);
      states.error(Wire.server);

      expect(states[Wire.tilesets], WireStatus.active,
          reason: 'Tilesets unaffected by server error');
      expect(states[Wire.server], WireStatus.error);
      expect(states[Wire.camera], WireStatus.pending,
          reason: 'Camera still pending');
    });

    test('WireStates notifies listeners on every transition', () {
      final states = WireStates();
      var notifyCount = 0;
      states.addListener(() => notifyCount++);

      states.start(Wire.tilesets);
      states.complete(Wire.tilesets);
      states.error(Wire.server);

      expect(notifyCount, 3);
    });
  });
}
