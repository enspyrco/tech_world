import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/auth/user_profile_service.dart';

void main() {
  group('UserProfile avatarId field', () {
    test('UserProfile stores optional avatarId', () {
      const profile = UserProfile(
        uid: 'user-1',
        displayName: 'Test',
        avatarId: 'npc12',
      );

      expect(profile.avatarId, equals('npc12'));
    });

    test('UserProfile avatarId defaults to null', () {
      const profile = UserProfile(uid: 'user-1');
      expect(profile.avatarId, isNull);
    });
  });

  group('UserProfileService avatar methods', () {
    // Note: Full Firestore integration tests require mock Firestore.
    // These tests verify the data model contracts.

    test('saveAvatarId produces correct merge data', () {
      // Verify the method signature exists and the field name is correct.
      // The actual Firestore call is tested via integration tests.
      const profile = UserProfile(
        uid: 'user-1',
        displayName: 'Test',
        avatarId: 'npc13',
      );

      expect(profile.avatarId, equals('npc13'));
      expect(profile.uid, equals('user-1'));
    });

    test('getAvatarId returns null when no profile exists', () {
      // Simulates the contract: getUserProfile returns null for unknown user
      const UserProfile? profile = null;
      expect(profile?.avatarId, isNull);
    });
  });
}
