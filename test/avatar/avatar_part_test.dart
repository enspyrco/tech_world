import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/avatar/avatar_spec.dart';
import 'package:tech_world/avatar/parts/avatar_part.dart';

void main() {
  group('wireName round-trip', () {
    test('every BodyId parses back to itself', () {
      for (final id in BodyId.values) {
        expect(BodyId.parse(id.wireName), id);
      }
    });

    test('every optional-slot id parses back to itself', () {
      for (final id in HairId.values) {
        expect(HairId.parse(id.wireName), id);
      }
      for (final id in OutfitId.values) {
        expect(OutfitId.parse(id.wireName), id);
      }
      for (final id in AccessoryId.values) {
        expect(AccessoryId.parse(id.wireName), id);
      }
    });

    test('an unknown wire value parses to null, never a default', () {
      // Fail-closed: the caller decides the fallback, because "unknown body"
      // and "unknown hat" deserve different answers (defaultAvatar vs none).
      expect(BodyId.parse('npc99'), isNull);
      expect(HairId.parse(''), isNull);
      expect(OutfitId.parse('hair_none'), isNull,
          reason: 'a valid wire name from another slot is still unknown here');
    });
  });

  group('cross-namespace disjointness', () {
    test('no wire name is shared between any two slots', () {
      final all = <String>[
        ...BodyId.values.map((e) => e.wireName),
        ...HairId.values.map((e) => e.wireName),
        ...OutfitId.values.map((e) => e.wireName),
        ...AccessoryId.values.map((e) => e.wireName),
      ];

      // Four typed namespaces reach the same persistence boundary (the
      // Firestore profile and the avatar wire payload). Keeping the wire forms
      // disjoint by construction means a value can never be silently read into
      // the wrong slot; this pins that by length, the same way
      // `code_challenge_id_test.dart` pins its pair.
      expect(all.toSet(), hasLength(all.length));
    });

    test('optional slots carry a slot-prefixed none, not a bare "none"', () {
      // A bare 'none' in three enums would be the collision above.
      expect(HairId.none.wireName, 'hair_none');
      expect(OutfitId.none.wireName, 'outfit_none');
      expect(AccessoryId.none.wireName, 'accessory_none');
    });
  });

  group('slot structure', () {
    test('body has no empty value — a character always has a body', () {
      // `BodyId.asset` is non-nullable while the optional slots' is `String?`,
      // so this is a type-level guarantee, not a runtime one: the analyzer
      // rejects a `null` asset on BodyId outright. Asserted through the
      // AvatarPart view, where the field is nullable for every slot.
      for (final AvatarPart body in BodyId.values) {
        expect(body.asset, isNotNull,
            reason: 'BodyId deliberately has no `none`');
      }
    });

    test('every optional slot has exactly one empty value', () {
      expect(HairId.values.where((h) => h.asset == null), hasLength(1));
      expect(OutfitId.values.where((o) => o.asset == null), hasLength(1));
      expect(AccessoryId.values.where((a) => a.asset == null), hasLength(1));
    });

    test('paint order is body under outfit under hair under accessory', () {
      expect(ZPos.body, lessThan(ZPos.outfit));
      expect(ZPos.outfit, lessThan(ZPos.hair));
      expect(ZPos.hair, lessThan(ZPos.accessory));
    });

    test('every shipping preset maps to a real asset', () {
      for (final preset in [
        CompositeAvatar.npc11,
        CompositeAvatar.npc12,
        CompositeAvatar.npc13,
      ]) {
        expect(preset.layers, hasLength(1));
        expect(preset.body.asset, endsWith('.png'));
      }
    });
  });

  group('AvatarSpec equality', () {
    const parts = CompositeAvatar(body: BodyId.npc11);

    test('equal parts with no edit are equal', () {
      expect(const AvatarSpec(parts: parts),
          equals(const AvatarSpec(parts: parts)));
    });

    test('different parts are unequal', () {
      expect(
        const AvatarSpec(parts: parts),
        isNot(equals(
            const AvatarSpec(parts: CompositeAvatar(body: BodyId.npc12)))),
      );
    });

    test('an edit distinguishes two specs with identical parts', () {
      const edited = AvatarSpec(
        parts: parts,
        edit: CanvasEdit(uid: 'u1', hash: 'abc'),
      );
      expect(const AvatarSpec(parts: parts), isNot(equals(edited)));
    });

    test('same uid and hash but a different edit TIER are NOT equal', () {
      // The promotion case: identical bytes, promoted from overlay to canvas,
      // render completely differently — so the promotion must MISS the composed
      // cache. This is the test that keeps that true; it holds because each
      // PixelEdit subclass's `==` requires `other is <its own type>`.
      const overlay = AvatarSpec(
        parts: parts,
        edit: OverlayEdit(uid: 'u1', hash: 'abc', basePartsHash: 'p'),
      );
      const canvas = AvatarSpec(
        parts: parts,
        edit: CanvasEdit(uid: 'u1', hash: 'abc'),
      );

      expect(overlay, isNot(equals(canvas)));
      expect(overlay.hashCode, isNot(equals(canvas.hashCode)));
    });

    test('equal specs hash equally', () {
      final a = AvatarSpec(parts: parts.copyWith(body: BodyId.npc13));
      final b = AvatarSpec(parts: parts.copyWith(body: BodyId.npc13));
      expect(a.hashCode, b.hashCode);
      expect({a, b}, hasLength(1));
    });
  });
}
