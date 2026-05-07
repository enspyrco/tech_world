import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/livekit_service.dart';

void main() {
  // PositionHeartbeat ships in the audit/position-heartbeat branch as the
  // wire-format type for the reliable 2-second position correction. The
  // parser is the single source of truth for what a valid heartbeat
  // payload looks like — every dropped/malformed packet flows through
  // tryParse and either teleports a remote player to a new position or
  // silently drops. A bug here either:
  //   - rejects valid payloads (remote players freeze in stale positions)
  //   - accepts wrong-shaped payloads (player teleports to (null,null) or
  //     to coordinates from another player's frame).
  //
  // The Dart type system can't express "this Map matches this shape" so
  // these failure modes are exactly what tests should catch.

  group('PositionHeartbeat.tryParse', () {
    test('parses a well-formed heartbeat', () {
      final hb = PositionHeartbeat.tryParse({
        'playerId': 'user-42',
        'x': 7,
        'y': 3,
      });
      expect(hb, isNotNull);
      expect(hb!.playerId, 'user-42');
      expect(hb.x, 7);
      expect(hb.y, 3);
    });

    test('returns null for null map (defensive against malformed JSON)', () {
      expect(PositionHeartbeat.tryParse(null), isNull);
    });

    test('returns null when playerId is missing', () {
      expect(PositionHeartbeat.tryParse({'x': 1, 'y': 2}), isNull);
    });

    test('returns null when x is missing', () {
      expect(
        PositionHeartbeat.tryParse({'playerId': 'u', 'y': 2}),
        isNull,
      );
    });

    test('returns null when y is missing', () {
      expect(
        PositionHeartbeat.tryParse({'playerId': 'u', 'x': 1}),
        isNull,
      );
    });

    test('returns null when playerId is the wrong type', () {
      // A bot or older client could publish a numeric id; the receiver
      // must drop it rather than crash.
      expect(
        PositionHeartbeat.tryParse({'playerId': 42, 'x': 1, 'y': 2}),
        isNull,
      );
    });

    test('returns null when x is a double rather than int', () {
      // Heartbeat is grid-quantized; a fractional coordinate is malformed
      // and must not be silently truncated. This pins the int contract
      // so a future loosening to "num" is an explicit decision, not a
      // surprise that lets continuous-position drift through.
      expect(
        PositionHeartbeat.tryParse({'playerId': 'u', 'x': 1.5, 'y': 2}),
        isNull,
      );
    });

    test('accepts negative coordinates (off-origin maps are valid)', () {
      // The grid origin is not always (0,0) — some maps extend into
      // negative coordinates. A naive `x >= 0` check would silently drop
      // these.
      final hb = PositionHeartbeat.tryParse({
        'playerId': 'u',
        'x': -5,
        'y': -3,
      });
      expect(hb, isNotNull);
      expect(hb!.x, -5);
      expect(hb.y, -3);
    });

    test('accepts zero coordinates', () {
      final hb = PositionHeartbeat.tryParse({
        'playerId': 'u',
        'x': 0,
        'y': 0,
      });
      expect(hb, isNotNull);
    });

    test('returns null for empty map', () {
      expect(PositionHeartbeat.tryParse(<String, dynamic>{}), isNull);
    });

    test('ignores extra fields rather than rejecting (forward-compat)', () {
      // If a future client adds an `avatar` or `version` field, older
      // clients should still teleport, not freeze.
      final hb = PositionHeartbeat.tryParse({
        'playerId': 'u',
        'x': 1,
        'y': 2,
        'avatarId': 'wizard',
        'version': 2,
      });
      expect(hb, isNotNull);
      expect(hb!.x, 1);
      expect(hb.y, 2);
    });
  });
}
