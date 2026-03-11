import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/auth/user_profile_service.dart';

void main() {
  group('UserProfileService', () {
    late FakeFirebaseFirestore fakeFirestore;
    late UserProfileService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = UserProfileService(
        collection: fakeFirestore.collection('users'),
      );
    });

    group('saveUserProfile', () {
      test('saves displayName and email when both provided', () async {
        await service.saveUserProfile(
          uid: 'user-123',
          displayName: 'Alice Smith',
          email: 'alice@example.com',
        );

        final doc =
            await fakeFirestore.collection('users').doc('user-123').get();
        expect(doc.exists, isTrue);
        expect(doc.data()?['displayName'], equals('Alice Smith'));
        expect(doc.data()?['email'], equals('alice@example.com'));
        expect(doc.data()?['updatedAt'], isNotNull);
      });

      test('saves only displayName when email is null', () async {
        await service.saveUserProfile(
          uid: 'user-456',
          displayName: 'Bob Jones',
          email: null,
        );

        final doc =
            await fakeFirestore.collection('users').doc('user-456').get();
        expect(doc.exists, isTrue);
        expect(doc.data()?['displayName'], equals('Bob Jones'));
        expect(doc.data()?.containsKey('email'), isFalse);
      });

      test('saves only email when displayName is empty', () async {
        await service.saveUserProfile(
          uid: 'user-789',
          displayName: '',
          email: 'bob@example.com',
        );

        final doc =
            await fakeFirestore.collection('users').doc('user-789').get();
        expect(doc.exists, isTrue);
        expect(doc.data()?.containsKey('displayName'), isFalse);
        expect(doc.data()?['email'], equals('bob@example.com'));
      });

      test('merges data without overwriting existing fields', () async {
        // First save with displayName
        await service.saveUserProfile(
          uid: 'user-merge',
          displayName: 'Original Name',
        );

        // Second save with only email - should preserve displayName
        await service.saveUserProfile(
          uid: 'user-merge',
          email: 'new@example.com',
        );

        final doc =
            await fakeFirestore.collection('users').doc('user-merge').get();
        expect(doc.data()?['displayName'], equals('Original Name'));
        expect(doc.data()?['email'], equals('new@example.com'));
      });
    });

    group('getUserProfile', () {
      test('returns UserProfile when document exists', () async {
        await fakeFirestore.collection('users').doc('existing-user').set({
          'displayName': 'Existing User',
          'email': 'existing@example.com',
        });

        final profile = await service.getUserProfile('existing-user');

        expect(profile, isNotNull);
        expect(profile?.uid, equals('existing-user'));
        expect(profile?.displayName, equals('Existing User'));
        expect(profile?.email, equals('existing@example.com'));
      });

      test('returns null when document does not exist', () async {
        final profile = await service.getUserProfile('non-existent-user');

        expect(profile, isNull);
      });

      test('handles missing fields gracefully', () async {
        await fakeFirestore.collection('users').doc('partial-user').set({
          'displayName': 'Only Name',
        });

        final profile = await service.getUserProfile('partial-user');

        expect(profile, isNotNull);
        expect(profile?.displayName, equals('Only Name'));
        expect(profile?.email, isNull);
      });
    });

    group('getDisplayName', () {
      test('returns displayName from Firestore when available', () async {
        await fakeFirestore.collection('users').doc('user-with-name').set({
          'displayName': 'Stored Name',
        });

        final displayName = await service.getDisplayName('user-with-name');

        expect(displayName, equals('Stored Name'));
      });

      test('returns fallback when user does not exist', () async {
        final displayName = await service.getDisplayName(
          'non-existent',
          fallback: 'Default Name',
        );

        expect(displayName, equals('Default Name'));
      });

      test('returns empty string as default fallback', () async {
        final displayName = await service.getDisplayName('non-existent');

        expect(displayName, isEmpty);
      });

      test('returns fallback when displayName is null', () async {
        await fakeFirestore.collection('users').doc('user-no-name').set({
          'email': 'only@email.com',
        });

        final displayName = await service.getDisplayName(
          'user-no-name',
          fallback: 'Fallback',
        );

        expect(displayName, equals('Fallback'));
      });
    });

    group('saveProfilePictureUrl', () {
      test('saves profile picture URL to Firestore', () async {
        await service.saveProfilePictureUrl(
          'user-pic',
          'https://storage.example.com/photo.jpg',
        );

        final doc =
            await fakeFirestore.collection('users').doc('user-pic').get();
        expect(doc.exists, isTrue);
        expect(doc.data()?['profilePictureUrl'],
            equals('https://storage.example.com/photo.jpg'));
        expect(doc.data()?['updatedAt'], isNotNull);
      });

      test('merges without overwriting existing fields', () async {
        await service.saveUserProfile(
          uid: 'user-merge-pic',
          displayName: 'Keep This Name',
        );

        await service.saveProfilePictureUrl(
          'user-merge-pic',
          'https://storage.example.com/photo.jpg',
        );

        final doc =
            await fakeFirestore.collection('users').doc('user-merge-pic').get();
        expect(doc.data()?['displayName'], equals('Keep This Name'));
        expect(doc.data()?['profilePictureUrl'],
            equals('https://storage.example.com/photo.jpg'));
      });
    });

    group('getUserProfile with profilePictureUrl', () {
      test('returns profilePictureUrl when stored', () async {
        await fakeFirestore.collection('users').doc('user-with-pic').set({
          'displayName': 'Photo User',
          'profilePictureUrl': 'https://storage.example.com/photo.jpg',
        });

        final profile = await service.getUserProfile('user-with-pic');

        expect(profile, isNotNull);
        expect(profile?.profilePictureUrl,
            equals('https://storage.example.com/photo.jpg'));
      });

      test('returns null profilePictureUrl when not stored', () async {
        await fakeFirestore.collection('users').doc('user-no-pic').set({
          'displayName': 'No Photo',
        });

        final profile = await service.getUserProfile('user-no-pic');

        expect(profile, isNotNull);
        expect(profile?.profilePictureUrl, isNull);
      });
    });

    group('searchUsers', () {
      test('returns profiles matching display name prefix', () async {
        await fakeFirestore.collection('users').doc('user-1').set({
          'displayName': 'Alice Smith',
          'displayNameLower': 'alice smith',
        });
        await fakeFirestore.collection('users').doc('user-2').set({
          'displayName': 'Alice Jones',
          'displayNameLower': 'alice jones',
        });
        await fakeFirestore.collection('users').doc('user-3').set({
          'displayName': 'Bob Brown',
          'displayNameLower': 'bob brown',
        });

        final results = await service.searchUsers('alice');

        expect(results, hasLength(2));
        expect(results.map((p) => p.displayName),
            containsAll(['Alice Smith', 'Alice Jones']));
      });

      test('is case-insensitive', () async {
        await fakeFirestore.collection('users').doc('user-1').set({
          'displayName': 'Charlie',
          'displayNameLower': 'charlie',
        });

        final results = await service.searchUsers('CHARLIE');

        expect(results, hasLength(1));
        expect(results.first.displayName, 'Charlie');
      });

      test('returns empty list for empty query', () async {
        final results = await service.searchUsers('');

        expect(results, isEmpty);
      });

      test('respects limit parameter', () async {
        for (var i = 0; i < 5; i++) {
          await fakeFirestore.collection('users').doc('user-$i').set({
            'displayName': 'Test User $i',
            'displayNameLower': 'test user $i',
          });
        }

        final results = await service.searchUsers('test', limit: 3);

        expect(results, hasLength(3));
      });
    });

    group('getUserProfiles', () {
      test('returns profiles for given UIDs', () async {
        await fakeFirestore.collection('users').doc('uid-1').set({
          'displayName': 'Alice',
        });
        await fakeFirestore.collection('users').doc('uid-2').set({
          'displayName': 'Bob',
        });

        final profiles = await service.getUserProfiles(['uid-1', 'uid-2']);

        expect(profiles, hasLength(2));
        expect(profiles.map((p) => p.displayName), containsAll(['Alice', 'Bob']));
      });

      test('returns empty list for empty UIDs', () async {
        final profiles = await service.getUserProfiles([]);

        expect(profiles, isEmpty);
      });

      test('handles UIDs that do not exist', () async {
        await fakeFirestore.collection('users').doc('exists').set({
          'displayName': 'Real User',
        });

        final profiles =
            await service.getUserProfiles(['exists', 'does-not-exist']);

        expect(profiles, hasLength(1));
        expect(profiles.first.displayName, 'Real User');
      });
    });

    group('saveUserProfile stores displayNameLower', () {
      test('saves lowercase version of displayName', () async {
        await service.saveUserProfile(
          uid: 'user-lower',
          displayName: 'Alice Smith',
        );

        final doc =
            await fakeFirestore.collection('users').doc('user-lower').get();
        expect(doc.data()?['displayNameLower'], equals('alice smith'));
      });

      test('does not save displayNameLower when displayName is empty',
          () async {
        await service.saveUserProfile(
          uid: 'user-empty',
          displayName: '',
          email: 'test@example.com',
        );

        final doc =
            await fakeFirestore.collection('users').doc('user-empty').get();
        expect(doc.data()?.containsKey('displayNameLower'), isFalse);
      });
    });
  });

  group('UserProfile', () {
    test('stores all fields correctly', () {
      const profile = UserProfile(
        uid: 'test-uid',
        displayName: 'Test User',
        email: 'test@example.com',
        profilePictureUrl: 'https://example.com/photo.jpg',
      );

      expect(profile.uid, equals('test-uid'));
      expect(profile.displayName, equals('Test User'));
      expect(profile.email, equals('test@example.com'));
      expect(
          profile.profilePictureUrl, equals('https://example.com/photo.jpg'));
    });

    test('allows null displayName, email, and profilePictureUrl', () {
      const profile = UserProfile(uid: 'test-uid');

      expect(profile.uid, equals('test-uid'));
      expect(profile.displayName, isNull);
      expect(profile.email, isNull);
      expect(profile.profilePictureUrl, isNull);
    });
  });
}
