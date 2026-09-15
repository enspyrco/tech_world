import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/avatar/avatar_spec.dart';
import 'package:tech_world/avatar/parts/avatar_part.dart';
import 'package:tech_world/livekit/livekit_service.dart';

/// The gate on peer-supplied appearance.
///
/// This used to whitelist a `spriteAsset` filename, and its tests were about
/// rejecting bad filenames (path traversal, empty strings, unknown names). No
/// filename crosses the wire any more — only closed-enum ids — so those
/// attacks are structurally unreachable rather than filtered, and the property
/// worth pinning changed shape:
///
/// - the parse is **total**: hostile input yields a bundled fallback, never
///   null and never a throw, because this runs inside a stream `map` where a
///   throw kills avatar reception for the session;
/// - the *only* null is a message that can't be attributed to a player;
/// - a failure never renders anything the sender chose.
void main() {
  Map<String, dynamic> partsPayload({
    String playerId = 'user-1',
    String body = 'npc11',
    String hair = 'hair_none',
    String outfit = 'outfit_none',
    String accessory = 'accessory_none',
    Object? version = kAssetPackVersion,
  }) =>
      {
        'playerId': playerId,
        'parts': {
          'body': body,
          'hair': hair,
          'outfit': outfit,
          'accessory': accessory,
          if (version != null) 'v': version,
        },
      };

  group('attribution — the only way to get null', () {
    test('returns null for a null map', () {
      expect(AvatarUpdate.tryParse(null), isNull);
    });

    test('returns null for an empty map', () {
      expect(AvatarUpdate.tryParse(<String, dynamic>{}), isNull);
    });

    test('returns null when playerId is missing', () {
      expect(AvatarUpdate.tryParse({'parts': {'body': 'npc11'}}), isNull);
    });

    test('returns null when playerId is the wrong type', () {
      expect(AvatarUpdate.tryParse({'playerId': 123}), isNull);
    });

    test('returns null when playerId is empty', () {
      // An empty id would attribute the update to a participant named "",
      // which is nobody — dropping beats picking a victim.
      expect(AvatarUpdate.tryParse({'playerId': ''}), isNull);
    });

    test('an attributable message with NO appearance still parses', () {
      // Total: the player is known, the appearance isn't. Render the default.
      final update = AvatarUpdate.tryParse({'playerId': 'user-1'});
      expect(update, isNotNull);
      expect(update!.spec, AvatarSpec.fallback);
    });
  });

  group('parts payload', () {
    test('parses a well-formed spec', () {
      final update = AvatarUpdate.tryParse(partsPayload(body: 'npc12'));
      expect(update!.playerId, 'user-1');
      expect(update.spec.parts.body, BodyId.npc12);
    });

    test('round-trips through the wire form', () {
      const original = AvatarSpec(parts: CompositeAvatar(body: BodyId.npc13));
      final update = AvatarUpdate.tryParse({
        'playerId': 'user-1',
        ...original.toWire(),
      });
      expect(update!.spec, original);
    });

    test('ignores extra fields (forward-compat)', () {
      final update = AvatarUpdate.tryParse({
        ...partsPayload(body: 'npc12'),
        'colour': 'blue',
        'somethingFromTheFuture': {'nested': true},
      });
      expect(update!.spec.parts.body, BodyId.npc12);
    });
  });

  group('identity fails closed, additions degrade', () {
    test('an unknown body falls back — it never silently defaults a slot', () {
      final update = AvatarUpdate.tryParse(partsPayload(body: 'npc99'));
      expect(update!.spec, AvatarSpec.fallback);
    });

    test('a path-traversal string in body is just an unknown id', () {
      final update =
          AvatarUpdate.tryParse(partsPayload(body: '../../etc/passwd'));
      expect(update!.spec, AvatarSpec.fallback);
    });

    test('an empty body id falls back', () {
      expect(AvatarUpdate.tryParse(partsPayload(body: ''))!.spec,
          AvatarSpec.fallback);
    });

    test('a wrong-typed body falls back rather than throwing', () {
      final update = AvatarUpdate.tryParse({
        'playerId': 'user-1',
        'parts': {'body': 42, 'v': kAssetPackVersion},
      });
      expect(update!.spec, AvatarSpec.fallback);
    });

    test('an unknown OPTIONAL slot degrades to none, keeping the body', () {
      final update = AvatarUpdate.tryParse(
          partsPayload(body: 'npc13', hair: 'hair_from_the_future'));
      expect(update!.spec.parts.body, BodyId.npc13,
          reason: 'identity survives an unknown addition');
      expect(update.spec.parts.hair, HairId.none);
    });

    test('a non-map parts value falls back', () {
      final update =
          AvatarUpdate.tryParse({'playerId': 'user-1', 'parts': 'nope'});
      expect(update!.spec, AvatarSpec.fallback);
    });
  });

  group('asset pack version', () {
    test('a mismatched major falls back', () {
      final update =
          AvatarUpdate.tryParse(partsPayload(version: kAssetPackVersion + 1));
      expect(update!.spec, AvatarSpec.fallback);
    });

    test('a missing version falls back rather than assuming current', () {
      // This is the first version to publish parts at all, so an omitted `v`
      // is malformed, not "an older client being polite".
      final update = AvatarUpdate.tryParse(partsPayload(version: null));
      expect(update!.spec, AvatarSpec.fallback);
    });

    test('a wrong-typed version falls back', () {
      final update = AvatarUpdate.tryParse(partsPayload(version: '1'));
      expect(update!.spec, AvatarSpec.fallback);
    });
  });

  group('legacy migration (F5)', () {
    test('a pre-parts payload maps its avatarId to a composite', () {
      final update =
          AvatarUpdate.tryParse({'playerId': 'user-1', 'avatarId': 'npc12'});
      expect(update!.spec.parts.body, BodyId.npc12,
          reason: 'a live user must not reset to default on upgrade');
    });

    test('every legacy preset id migrates', () {
      for (final id in ['npc11', 'npc12', 'npc13']) {
        final update =
            AvatarUpdate.tryParse({'playerId': 'user-1', 'avatarId': id});
        expect(update!.spec.parts.body.wireName, id);
      }
    });

    test('an unknown legacy id falls back', () {
      final update =
          AvatarUpdate.tryParse({'playerId': 'user-1', 'avatarId': 'npc99'});
      expect(update!.spec, AvatarSpec.fallback);
    });

    test('a legacy spriteAsset filename is simply never read', () {
      // The old gate whitelisted this field. Nothing reads it now, so a
      // hostile value can't reach the renderer even in principle.
      final update = AvatarUpdate.tryParse({
        'playerId': 'user-1',
        'avatarId': 'npc12',
        'spriteAsset': '../../etc/passwd',
      });
      expect(update!.spec.parts.body, BodyId.npc12);
      expect(update.spec.parts.body.asset, 'NPC12.png');
    });
  });

  test('no hostile payload ever throws', () {
    // Totality is the security property: this parse runs inside a stream's
    // `map`, so one throw would end avatar reception for the whole session.
    final hostile = <Map<String, dynamic>>[
      {'playerId': 'u', 'parts': []},
      {'playerId': 'u', 'parts': null},
      {'playerId': 'u', 'parts': <String, dynamic>{}},
      {'playerId': 'u', 'parts': {'body': null, 'v': null}},
      {'playerId': 'u', 'parts': {'v': kAssetPackVersion}},
      {'playerId': 'u', 'avatarId': 42},
      {'playerId': 'u', 'avatarId': null},
    ];
    for (final json in hostile) {
      expect(() => AvatarUpdate.tryParse(json), returnsNormally,
          reason: 'threw on $json');
      expect(AvatarUpdate.tryParse(json)!.spec, AvatarSpec.fallback);
    }
  });
}
