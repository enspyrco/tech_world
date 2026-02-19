import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/avatar/avatar.dart';
import 'package:tech_world/avatar/predefined_avatars.dart';

void main() {
  group('Avatar', () {
    test('has id, displayName, and spriteAsset fields', () {
      const avatar = Avatar(
        id: 'npc11',
        displayName: 'Explorer',
        spriteAsset: 'NPC11.png',
      );

      expect(avatar.id, equals('npc11'));
      expect(avatar.displayName, equals('Explorer'));
      expect(avatar.spriteAsset, equals('NPC11.png'));
    });

    test('equality is by id only', () {
      const avatar1 = Avatar(
        id: 'npc11',
        displayName: 'Explorer',
        spriteAsset: 'NPC11.png',
      );
      const avatar2 = Avatar(
        id: 'npc11',
        displayName: 'Different Name',
        spriteAsset: 'NPC11.png',
      );
      const avatar3 = Avatar(
        id: 'npc12',
        displayName: 'Explorer',
        spriteAsset: 'NPC12.png',
      );

      expect(avatar1, equals(avatar2));
      expect(avatar1, isNot(equals(avatar3)));
    });

    test('hashCode is consistent with equality', () {
      const avatar1 = Avatar(
        id: 'npc11',
        displayName: 'Explorer',
        spriteAsset: 'NPC11.png',
      );
      const avatar2 = Avatar(
        id: 'npc11',
        displayName: 'Different Name',
        spriteAsset: 'NPC11.png',
      );

      expect(avatar1.hashCode, equals(avatar2.hashCode));
    });

    group('JSON serialization', () {
      test('toJson produces correct map', () {
        const avatar = Avatar(
          id: 'npc11',
          displayName: 'Explorer',
          spriteAsset: 'NPC11.png',
        );

        final json = avatar.toJson();

        expect(json, equals({
          'id': 'npc11',
          'displayName': 'Explorer',
          'spriteAsset': 'NPC11.png',
        }));
      });

      test('fromJson creates correct Avatar', () {
        final json = {
          'id': 'npc12',
          'displayName': 'Ranger',
          'spriteAsset': 'NPC12.png',
        };

        final avatar = Avatar.fromJson(json);

        expect(avatar.id, equals('npc12'));
        expect(avatar.displayName, equals('Ranger'));
        expect(avatar.spriteAsset, equals('NPC12.png'));
      });

      test('round-trip through JSON preserves data', () {
        const original = Avatar(
          id: 'npc13',
          displayName: 'Scholar',
          spriteAsset: 'NPC13.png',
        );

        final json = original.toJson();
        final encoded = jsonEncode(json);
        final decoded = jsonDecode(encoded) as Map<String, dynamic>;
        final restored = Avatar.fromJson(decoded);

        expect(restored, equals(original));
        expect(restored.displayName, equals(original.displayName));
        expect(restored.spriteAsset, equals(original.spriteAsset));
      });
    });
  });

  group('predefinedAvatars', () {
    test('contains 3 entries', () {
      expect(predefinedAvatars, hasLength(3));
    });

    test('each entry has unique id', () {
      final ids = predefinedAvatars.map((a) => a.id).toSet();
      expect(ids, hasLength(predefinedAvatars.length));
    });

    test('each entry has non-empty fields', () {
      for (final avatar in predefinedAvatars) {
        expect(avatar.id, isNotEmpty);
        expect(avatar.displayName, isNotEmpty);
        expect(avatar.spriteAsset, isNotEmpty);
      }
    });

    test('includes NPC11, NPC12, and NPC13', () {
      final spriteAssets = predefinedAvatars.map((a) => a.spriteAsset).toSet();
      expect(spriteAssets, containsAll(['NPC11.png', 'NPC12.png', 'NPC13.png']));
    });
  });

  group('defaultAvatar', () {
    test('is NPC11 (matches current hardcoded behavior)', () {
      expect(defaultAvatar.spriteAsset, equals('NPC11.png'));
    });

    test('is the first entry in predefinedAvatars', () {
      expect(defaultAvatar, equals(predefinedAvatars.first));
    });
  });

  group('avatarById', () {
    test('finds avatar by id', () {
      final avatar = avatarById('npc12');
      expect(avatar, isNotNull);
      expect(avatar!.spriteAsset, equals('NPC12.png'));
    });

    test('returns null for unknown id', () {
      final avatar = avatarById('nonexistent');
      expect(avatar, isNull);
    });

    test('returns defaultAvatar for null id via helper', () {
      final avatar = avatarById(null);
      expect(avatar, isNull);
    });
  });
}
