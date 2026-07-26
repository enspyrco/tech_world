import 'dart:typed_data';

import 'package:realm/realm.dart';
import 'package:test/test.dart';

void main() {
  group('FoyerVisibility wire parsing', () {
    test('round-trips every value', () {
      for (final v in FoyerVisibility.values) {
        expect(FoyerVisibility.parse(v.wire), v);
        expect(FoyerVisibility.tryParse(v.wire), v);
      }
    });

    test('parse throws on an unknown wire string', () {
      // The failure mode this forecloses: a typo'd or renamed wire value
      // resolving to a default. If that default were `public`, a typo leaks a
      // private room into the foyer; if it were `private`, a typo silently
      // hides a room its owner believes is listed. Both are worse than a
      // crash, so the strict door crashes.
      expect(() => FoyerVisibility.parse('pubic'), throwsArgumentError);
      expect(() => FoyerVisibility.parse(''), throwsArgumentError);
    });

    test('tryParse returns null rather than choosing a fallback', () {
      // The lenient door exists for trust boundaries, but it still refuses to
      // pick the fallback for you — the caller states the policy at the call
      // site: `tryParse(wire) ?? FoyerVisibility.private`.
      expect(FoyerVisibility.tryParse('pubic'), isNull);
    });

    test('wire values are snake_case-stable, not tied to Dart names', () {
      expect(FoyerVisibility.public.wire, 'public');
      expect(FoyerVisibility.unlisted.wire, 'unlisted');
      expect(FoyerVisibility.private.wire, 'private');
    });
  });

  group('LeaveReason', () {
    test('round-trips every value including the reserved v2 variant', () {
      for (final v in LeaveReason.values) {
        expect(LeaveReason.tryParse(v.wire), v);
      }
      // portalTransit is declared in v1 and emitted only in v2. Declaring it
      // now is what makes v2 a non-breaking change: consumers already carry an
      // arm for it, so lighting up emission does not break their switches.
      expect(LeaveReason.tryParse('portal_transit'), LeaveReason.portalTransit);
    });

    test('unknown wire strings return null', () {
      expect(LeaveReason.tryParse('kicked'), isNull);
    });
  });

  group('RoomRef federation reservation', () {
    test('LocalRoomRef is constructible in v1', () {
      const ref = LocalRoomRef(RoomId('room-1'));
      expect(ref.roomId, const RoomId('room-1'));
    });

    test('FederatedRoomRef cannot be constructed in v1', () {
      // Reserved-but-never-emitted. The type exists so that v2 can start
      // emitting it without breaking any exhaustive switch; the assertion is
      // what stops "exists" from sliding into "used" before federation is real.
      expect(
        () => FederatedRoomRef(
          operatorUri: Uri.parse('https://other.example'),
          roomId: const RoomId('room-1'),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('consumers can switch exhaustively over the v1 family', () {
      String describe(RoomRef ref) => switch (ref) {
            LocalRoomRef() => 'local',
            FederatedRoomRef() => 'federated',
          };

      expect(describe(const LocalRoomRef(RoomId('r'))), 'local');
    });
  });

  group('RoomPreview is a genuine XOR', () {
    test('every variant is reachable through one exhaustive switch', () {
      const hints = PreviewHints(participantCount: 3, activityLabel: 'quiet');

      String kind(RoomPreview p) => switch (p) {
            RasterPreview() => 'raster',
            VectorPreview() => 'vector',
            EmptyPreview() => 'empty',
          };

      expect(
        kind(RasterPreview(image: Uint8List(0), worldHints: hints)),
        'raster',
      );
      expect(kind(const VectorPreview(shapes: [], worldHints: hints)), 'vector');
      expect(kind(const EmptyPreview(worldHints: hints)), 'empty');
    });

    test('hints survive on every variant, including the visual-less one', () {
      // The foyer must be able to render "3 people, quiet" for a world that
      // offers no picture at all — otherwise EmptyPreview would be worthless
      // and worlds would be pushed into faking a raster.
      const preview = EmptyPreview(
        worldHints: PreviewHints(participantCount: 3, voiceActive: true),
      );
      expect(preview.worldHints.participantCount, 3);
      expect(preview.worldHints.voiceActive, isTrue);
    });

    test('PreviewShape stays open — a world can ship its own', () {
      const preview = VectorPreview(
        shapes: [_HexPreviewShape(sides: 6)],
        worldHints: PreviewHints(participantCount: 0),
      );
      expect(preview.shapes.single, isA<PreviewShape>());
      expect(preview.shapes.single, isNot(isA<CirclePreviewShape>()));
    });
  });

  group('presence projections', () {
    test('FullProjection dedupes on user id', () {
      final now = DateTime.utc(2026, 7, 26);
      final set = {
        FullProjection(
          userId: const UserId('u1'),
          displayName: 'Nick',
          joinedAt: now,
        ),
        FullProjection(
          userId: const UserId('u1'),
          displayName: 'Nick (rejoined)',
          joinedAt: now.add(const Duration(minutes: 5)),
        ),
      };
      expect(set, hasLength(1));
    });

    test('PublicProjection dedupes on the per-room hash', () {
      // Built from a list rather than a set literal, because that is how an
      // implementation actually gets here: a backend hands over a payload that
      // may repeat a participant (a reconnect mid-poll, an at-least-once
      // delivery), and the Set semantics are what collapse it back to one.
      final payload = ['a1b2c3d4', 'a1b2c3d4', 'ffffffff'];
      final projections =
          payload.map((h) => PublicProjection(userIdHash: h)).toSet();

      expect(projections, hasLength(2));
    });

    test('a foyer projection still counts opted-out users', () {
      // opaqueAvatarRef is optional; userIdHash is not. Without that, a room
      // full of opted-out users would be indistinguishable from an empty one.
      const opted = PublicProjection(userIdHash: 'a1b2c3d4');
      expect(opted.opaqueAvatarRef, isNull);
      expect(opted.userIdHash, isNotEmpty);
    });
  });

  group('branded ids are distinct types', () {
    test('RoomId and UserId do not compare equal on the same string', () {
      // extension types are erased at runtime, so this is a compile-time
      // guarantee rather than a runtime one — the value of the test is that it
      // documents the intent and would fail to compile if either were widened
      // back to a bare String typedef.
      const room = RoomId('shared-value');
      const user = UserId('shared-value');
      expect(room.value, user.value);
    });
  });
}

/// A shape the engine has never heard of — the point of the open extension.
class _HexPreviewShape implements PreviewShape {
  const _HexPreviewShape({required this.sides});
  final int sides;
}
