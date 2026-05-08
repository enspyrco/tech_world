import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/livekit_service.dart';

void main() {
  group('AvatarUpdate.tryParse', () {
    test('parses well-formed update with known sprite asset', () {
      final update = AvatarUpdate.tryParse({
        'playerId': 'user-1',
        'avatarId': 'npc11',
        'spriteAsset': 'NPC11.png',
      });
      expect(update, isNotNull);
      expect(update!.playerId, 'user-1');
      expect(update.avatarId, 'npc11');
      expect(update.spriteAsset, 'NPC11.png');
    });

    test('accepts all predefined sprite assets', () {
      for (final asset in ['NPC11.png', 'NPC12.png', 'NPC13.png']) {
        final update = AvatarUpdate.tryParse({
          'playerId': 'user-1',
          'spriteAsset': asset,
        });
        expect(update, isNotNull, reason: 'Expected $asset to be accepted');
      }
    });

    test('rejects unknown sprite asset', () {
      expect(
        AvatarUpdate.tryParse({
          'playerId': 'user-1',
          'spriteAsset': 'malicious_asset.png',
        }),
        isNull,
      );
    });

    test('rejects path-traversal attempt in sprite asset', () {
      expect(
        AvatarUpdate.tryParse({
          'playerId': 'user-1',
          'spriteAsset': '../../etc/passwd',
        }),
        isNull,
      );
    });

    test('rejects empty string sprite asset', () {
      expect(
        AvatarUpdate.tryParse({
          'playerId': 'user-1',
          'spriteAsset': '',
        }),
        isNull,
      );
    });

    test('defaults avatarId to empty string when missing', () {
      final update = AvatarUpdate.tryParse({
        'playerId': 'user-1',
        'spriteAsset': 'NPC11.png',
      });
      expect(update, isNotNull);
      expect(update!.avatarId, '');
    });

    test('defaults avatarId to empty string when wrong type', () {
      final update = AvatarUpdate.tryParse({
        'playerId': 'user-1',
        'avatarId': 42,
        'spriteAsset': 'NPC11.png',
      });
      expect(update, isNotNull);
      expect(update!.avatarId, '');
    });

    test('returns null for null map', () {
      expect(AvatarUpdate.tryParse(null), isNull);
    });

    test('returns null when playerId is missing', () {
      expect(
        AvatarUpdate.tryParse({'spriteAsset': 'NPC11.png'}),
        isNull,
      );
    });

    test('returns null when spriteAsset is missing', () {
      expect(
        AvatarUpdate.tryParse({'playerId': 'user-1'}),
        isNull,
      );
    });

    test('returns null when playerId is wrong type', () {
      expect(
        AvatarUpdate.tryParse({
          'playerId': 123,
          'spriteAsset': 'NPC11.png',
        }),
        isNull,
      );
    });

    test('returns null when spriteAsset is wrong type', () {
      expect(
        AvatarUpdate.tryParse({
          'playerId': 'user-1',
          'spriteAsset': true,
        }),
        isNull,
      );
    });

    test('ignores extra fields (forward-compat)', () {
      final update = AvatarUpdate.tryParse({
        'playerId': 'user-1',
        'avatarId': 'npc12',
        'spriteAsset': 'NPC12.png',
        'version': 2,
        'color': 'blue',
      });
      expect(update, isNotNull);
      expect(update!.playerId, 'user-1');
    });

    test('returns null for empty map', () {
      expect(AvatarUpdate.tryParse(<String, dynamic>{}), isNull);
    });
  });
}
