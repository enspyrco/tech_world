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
  });

  group('UserProfile', () {
    test('stores all fields correctly', () {
      const profile = UserProfile(
        uid: 'test-uid',
        displayName: 'Test User',
        email: 'test@example.com',
      );

      expect(profile.uid, equals('test-uid'));
      expect(profile.displayName, equals('Test User'));
      expect(profile.email, equals('test@example.com'));
    });

    test('allows null displayName and email', () {
      const profile = UserProfile(uid: 'test-uid');

      expect(profile.uid, equals('test-uid'));
      expect(profile.displayName, isNull);
      expect(profile.email, isNull);
    });
  });
}
