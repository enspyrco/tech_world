import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/emote.dart';
import 'package:tech_world/flame/shared/player_anim_state.dart';

void main() {
  group('EmoteId', () {
    test('round-trips every value through its wire form', () {
      for (final e in EmoteId.values) {
        expect(EmoteId.parse(e.wireName), equals(e));
      }
    });

    test('rejects unknown wire values rather than defaulting', () {
      // A hostile or newer peer must render as NOTHING, never as the wrong
      // animation — the receiver drops the message on a null parse.
      for (final junk in ['', 'WAVE', 'dance', '../wave', 'wave ']) {
        expect(EmoteId.parse(junk), isNull, reason: 'should reject "$junk"');
      }
    });

    test('wire names are unique', () {
      final wires = EmoteId.values.map((e) => e.wireName).toSet();
      expect(wires.length, equals(EmoteId.values.length));
    });
  });

  group('PlayerAnimState.forDirection', () {
    test('maps every Direction to a walk state, never to wave', () {
      for (final d in Direction.values) {
        final state = PlayerAnimState.forDirection(d);
        expect(
          state,
          isNot(PlayerAnimState.wave),
          reason: 'movement must never resolve to the emote state',
        );
      }
    });

    test('Direction.none rests facing down (no dedicated idle strip)', () {
      expect(
        PlayerAnimState.forDirection(Direction.none),
        equals(PlayerAnimState.walkDown),
      );
    });

    test('every non-none Direction has a distinct-or-shared walk mapping', () {
      expect(PlayerAnimState.forDirection(Direction.up),
          equals(PlayerAnimState.walkUp));
      expect(PlayerAnimState.forDirection(Direction.down),
          equals(PlayerAnimState.walkDown));
      expect(PlayerAnimState.forDirection(Direction.left),
          equals(PlayerAnimState.walkLeft));
      expect(PlayerAnimState.forDirection(Direction.right),
          equals(PlayerAnimState.walkRight));
      expect(PlayerAnimState.forDirection(Direction.upLeft),
          equals(PlayerAnimState.walkUpLeft));
      expect(PlayerAnimState.forDirection(Direction.upRight),
          equals(PlayerAnimState.walkUpRight));
      expect(PlayerAnimState.forDirection(Direction.downLeft),
          equals(PlayerAnimState.walkDownLeft));
      expect(PlayerAnimState.forDirection(Direction.downRight),
          equals(PlayerAnimState.walkDownRight));
    });
  });
}
