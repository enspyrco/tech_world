import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/avatar/avatar.dart';
import 'package:tech_world/avatar/predefined_avatars.dart';
import 'package:tech_world/livekit/livekit_service.dart';

void main() {
  group('Avatar data channel message format', () {
    test('avatar message contains playerId, avatarId, spriteAsset', () {
      const avatar = Avatar(
        id: 'npc12',
        displayName: 'Ranger',
        spriteAsset: 'NPC12.png',
      );
      const playerId = 'user-123';

      final message = {
        'playerId': playerId,
        'avatarId': avatar.id,
        'spriteAsset': avatar.spriteAsset,
      };

      expect(message['playerId'], equals('user-123'));
      expect(message['avatarId'], equals('npc12'));
      expect(message['spriteAsset'], equals('NPC12.png'));

      // Verify JSON round-trip
      final encoded = jsonEncode(message);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded['playerId'], equals('user-123'));
      expect(decoded['avatarId'], equals('npc12'));
      expect(decoded['spriteAsset'], equals('NPC12.png'));
    });
  });

  group('avatarReceived stream parsing', () {
    test('parses valid avatar message from DataChannelMessage', () {
      final message = DataChannelMessage(
        senderId: 'user-456',
        topic: 'avatar',
        data: utf8.encode(jsonEncode({
          'playerId': 'user-456',
          'avatarId': 'npc13',
          'spriteAsset': 'NPC13.png',
        })),
      );

      expect(message.topic, equals('avatar'));
      final json = message.json!;
      expect(json['playerId'], equals('user-456'));
      expect(json['avatarId'], equals('npc13'));
      expect(json['spriteAsset'], equals('NPC13.png'));
    });

    test('ignores malformed message (missing fields)', () {
      final message = DataChannelMessage(
        senderId: 'user-789',
        topic: 'avatar',
        data: utf8.encode(jsonEncode({'playerId': 'user-789'})),
      );

      final json = message.json!;
      expect(json['spriteAsset'], isNull);
    });

    test('AvatarUpdate.tryParse succeeds for valid data', () {
      final json = {
        'playerId': 'user-123',
        'avatarId': 'npc11',
        'spriteAsset': 'NPC11.png',
      };

      final update = AvatarUpdate.tryParse(json);
      expect(update, isNotNull);
      expect(update!.playerId, equals('user-123'));
      expect(update.avatarId, equals('npc11'));
      expect(update.spriteAsset, equals('NPC11.png'));
    });

    test('AvatarUpdate.tryParse returns null for missing playerId', () {
      final json = {
        'avatarId': 'npc11',
        'spriteAsset': 'NPC11.png',
      };
      expect(AvatarUpdate.tryParse(json), isNull);
    });

    test('AvatarUpdate.tryParse returns null for missing spriteAsset', () {
      final json = {
        'playerId': 'user-123',
        'avatarId': 'npc11',
      };
      expect(AvatarUpdate.tryParse(json), isNull);
    });

    test('AvatarUpdate.tryParse returns null for non-map data', () {
      expect(AvatarUpdate.tryParse(null), isNull);
    });
  });

  group('avatarById fallback for deleted sprites', () {
    test('returns null for unknown avatar id', () {
      expect(avatarById('deleted_sprite'), isNull);
    });

    test('fallback to defaultAvatar when avatarById returns null', () {
      final avatar = avatarById('deleted_sprite') ?? defaultAvatar;
      expect(avatar, equals(defaultAvatar));
    });
  });
}
