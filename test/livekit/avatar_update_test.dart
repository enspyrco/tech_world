import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/livekit_service.dart';

void main() {
  group('AvatarUpdate.tryParse', () {
    test('parses well-formed update', () {
      final update = AvatarUpdate.tryParse({
        'playerId': 'user-1',
        'avatarId': 'wizard',
        'spriteAsset': 'assets/wizard.png',
      });
      expect(update, isNotNull);
      expect(update!.playerId, 'user-1');
      expect(update.avatarId, 'wizard');
      expect(update.spriteAsset, 'assets/wizard.png');
    });

    test('defaults avatarId to empty string when missing', () {
      final update = AvatarUpdate.tryParse({
        'playerId': 'user-1',
        'spriteAsset': 'assets/wizard.png',
      });
      expect(update, isNotNull);
      expect(update!.avatarId, '');
    });

    test('defaults avatarId to empty string when wrong type', () {
      final update = AvatarUpdate.tryParse({
        'playerId': 'user-1',
        'avatarId': 42,
        'spriteAsset': 'assets/wizard.png',
      });
      expect(update, isNotNull);
      expect(update!.avatarId, '');
    });

    test('returns null for null map', () {
      expect(AvatarUpdate.tryParse(null), isNull);
    });

    test('returns null when playerId is missing', () {
      expect(
        AvatarUpdate.tryParse({'spriteAsset': 'assets/wizard.png'}),
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
          'spriteAsset': 'assets/wizard.png',
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
        'avatarId': 'wizard',
        'spriteAsset': 'assets/wizard.png',
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
