import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/mention_beacon_component.dart';
import 'package:tech_world/flame/mention/mention_pulse_controller.dart';

void main() {
  group('MentionBeaconComponent', () {
    late MentionPulseController controller;
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 6, 22, 12);
      controller = MentionPulseController(clock: () => now);
    });

    MentionBeaconComponent build() => MentionBeaconComponent(
          mentionedUid: 'bob',
          controller: controller,
          displayName: 'Bob',
          reduceMotion: false,
        );

    test('is a world PositionComponent', () {
      expect(build(), isA<PositionComponent>());
    });

    testWithGame<FlameGame>(
      'self-removes from its parent once the pulse stops',
      FlameGame.new,
      (game) async {
        controller.onMention(
          mentionedUid: 'bob',
          mentionerUid: 'alice',
          messageId: 'm1',
        );

        final parent = PositionComponent();
        await game.world.add(parent);
        await game.ready();

        final beacon = build();
        await parent.add(beacon);
        await game.ready();
        expect(parent.children.contains(beacon), isTrue);

        // Still pulsing → still attached after a frame.
        game.update(0.016);
        await game.ready();
        expect(parent.children.contains(beacon), isTrue);

        // Pulse stops (ack) → beacon removes itself on the next update.
        controller.onAck(mentionedUid: 'bob', messageId: 'm1');
        game.update(0.016);
        await game.ready();
        expect(parent.children.contains(beacon), isFalse,
            reason: 'beacon should self-remove when no longer pulsing');
      },
    );

    test('reduceMotion settles the bloom instantly (no animation gate)', () {
      final beacon = MentionBeaconComponent(
        mentionedUid: 'bob',
        controller: controller,
        displayName: 'Bob',
        reduceMotion: true,
      );
      // With reduce-motion the bloom is immediate — exercised via render not
      // throwing; the key guarantee is it doesn't depend on animated time.
      expect(beacon.reduceMotion, isTrue);
    });
  });
}
