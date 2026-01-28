import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/auth/auth_user.dart';

void main() {
  group('AuthUser', () {
    test('creates user with id and displayName', () {
      final user = AuthUser(id: 'user123', displayName: 'Test User');

      expect(user.id, equals('user123'));
      expect(user.displayName, equals('Test User'));
    });

    test('equality is based on id only', () {
      final user1 = AuthUser(id: 'user123', displayName: 'Test User');
      final user2 = AuthUser(id: 'user123', displayName: 'Different Name');
      final user3 = AuthUser(id: 'different', displayName: 'Test User');

      expect(user1, equals(user2));
      expect(user1, isNot(equals(user3)));
    });

    test('hashCode is based on id', () {
      final user1 = AuthUser(id: 'user123', displayName: 'Test User');
      final user2 = AuthUser(id: 'user123', displayName: 'Different Name');

      expect(user1.hashCode, equals(user2.hashCode));
      expect(user1.hashCode, equals('user123'.hashCode));
    });

    test('can be used in Set correctly', () {
      final user1 = AuthUser(id: 'user123', displayName: 'Name 1');
      final user2 = AuthUser(id: 'user123', displayName: 'Name 2');
      final user3 = AuthUser(id: 'user456', displayName: 'Name 3');

      final set = {user1, user2, user3};

      // user1 and user2 have same id, so only one should be in set
      expect(set.length, equals(2));
    });
  });

  group('SignedOutUser', () {
    test('extends AuthUser', () {
      final user = SignedOutUser(id: 'user123', displayName: 'Test User');

      expect(user, isA<AuthUser>());
      expect(user.id, equals('user123'));
      expect(user.displayName, equals('Test User'));
    });

    test('can be identified with is check', () {
      final AuthUser signedOut = SignedOutUser(id: 'id', displayName: 'name');
      final AuthUser regular = AuthUser(id: 'id', displayName: 'name');

      expect(signedOut is SignedOutUser, isTrue);
      expect(regular is SignedOutUser, isFalse);
    });
  });

  group('PlaceholderUser', () {
    test('extends AuthUser', () {
      final user = PlaceholderUser();

      expect(user, isA<AuthUser>());
    });

    test('has empty defaults', () {
      final user = PlaceholderUser();

      expect(user.id, equals(''));
      expect(user.displayName, equals(''));
    });

    test('can override defaults', () {
      final user = PlaceholderUser(id: 'custom', displayName: 'Custom Name');

      expect(user.id, equals('custom'));
      expect(user.displayName, equals('Custom Name'));
    });

    test('can be identified with is check', () {
      final AuthUser placeholder = PlaceholderUser();
      final AuthUser regular = AuthUser(id: 'id', displayName: 'name');

      expect(placeholder is PlaceholderUser, isTrue);
      expect(regular is PlaceholderUser, isFalse);
    });
  });
}
