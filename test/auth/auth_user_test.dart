import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/auth/auth_user.dart';

void main() {
  group('AuthUser', () {
    test('creates user with id and displayName', () {
      final user = AuthUser(id: 'user-123', displayName: 'John Doe');

      expect(user.id, equals('user-123'));
      expect(user.displayName, equals('John Doe'));
    });

    test('implements User interface', () {
      final user = AuthUser(id: 'user-456', displayName: 'Jane');

      expect(user, isA<User>());
    });

    test('can have empty displayName', () {
      final user = AuthUser(id: 'user-789', displayName: '');

      expect(user.displayName, equals(''));
    });

    group('equality', () {
      test('users with same id are equal', () {
        final user1 = AuthUser(id: 'same-id', displayName: 'Name 1');
        final user2 = AuthUser(id: 'same-id', displayName: 'Name 2');

        expect(user1, equals(user2));
      });

      test('users with different id are not equal', () {
        final user1 = AuthUser(id: 'id-1', displayName: 'Same Name');
        final user2 = AuthUser(id: 'id-2', displayName: 'Same Name');

        expect(user1, isNot(equals(user2)));
      });

      test('AuthUser equals SignedOutUser with same id', () {
        final authUser = AuthUser(id: 'shared-id', displayName: 'Name');
        final signedOut = SignedOutUser(id: 'shared-id', displayName: 'Name');

        expect(authUser, equals(signedOut));
      });

      test('equality works with any User implementation', () {
        final user = AuthUser(id: 'test-id', displayName: 'Test');

        // equals compares by id via User interface
        expect(user == user, isTrue);
      });

      test('equals method handles different types', () {
        final user = AuthUser(id: 'test', displayName: 'Test');
        // Test that operator== returns false for non-User objects
        // ignore: unrelated_type_equality_checks
        expect(user == 'test', isFalse);
      });
    });

    group('hashCode', () {
      test('hashCode is based on id', () {
        final user = AuthUser(id: 'hash-test', displayName: 'Name');

        expect(user.hashCode, equals('hash-test'.hashCode));
      });

      test('equal users have equal hashCode', () {
        final user1 = AuthUser(id: 'same', displayName: 'Name 1');
        final user2 = AuthUser(id: 'same', displayName: 'Name 2');

        expect(user1.hashCode, equals(user2.hashCode));
      });

      test('can be used in Set', () {
        final user1 = AuthUser(id: 'set-test', displayName: 'Name 1');
        final user2 = AuthUser(id: 'set-test', displayName: 'Name 2');
        final user3 = AuthUser(id: 'different', displayName: 'Name 3');

        final userSet = {user1, user2, user3};

        // user1 and user2 have same id, so set should have 2 items
        expect(userSet.length, equals(2));
      });

      test('can be used as Map key', () {
        final user1 = AuthUser(id: 'map-key', displayName: 'Name');
        final user2 = AuthUser(id: 'map-key', displayName: 'Different');

        final map = <User, String>{};
        map[user1] = 'first';
        map[user2] = 'second';

        // Same id means same key
        expect(map.length, equals(1));
        expect(map[user1], equals('second'));
      });
    });
  });

  group('SignedOutUser', () {
    test('creates signed out user with id and displayName', () {
      final user = SignedOutUser(id: 'signed-out-123', displayName: 'Ex User');

      expect(user.id, equals('signed-out-123'));
      expect(user.displayName, equals('Ex User'));
    });

    test('extends AuthUser', () {
      final user = SignedOutUser(id: 'test', displayName: 'Test');

      expect(user, isA<AuthUser>());
      expect(user, isA<User>());
    });

    test('inherits equality from AuthUser', () {
      final signedOut1 = SignedOutUser(id: 'user-1', displayName: 'A');
      final signedOut2 = SignedOutUser(id: 'user-1', displayName: 'B');

      expect(signedOut1, equals(signedOut2));
    });

    test('can be distinguished from AuthUser by type', () {
      final User authUser = AuthUser(id: 'test', displayName: 'Test');
      final User signedOut = SignedOutUser(id: 'test', displayName: 'Test');

      expect(authUser is SignedOutUser, isFalse);
      expect(signedOut is SignedOutUser, isTrue);
      expect(signedOut is AuthUser, isTrue);
    });
  });

  group('PlaceholderUser', () {
    test('creates placeholder with default empty values', () {
      final user = PlaceholderUser();

      expect(user.id, equals(''));
      expect(user.displayName, equals(''));
    });

    test('creates placeholder with custom values', () {
      final user = PlaceholderUser(id: 'custom-id', displayName: 'Custom Name');

      expect(user.id, equals('custom-id'));
      expect(user.displayName, equals('Custom Name'));
    });

    test('extends AuthUser', () {
      final user = PlaceholderUser();

      expect(user, isA<AuthUser>());
      expect(user, isA<User>());
    });

    test('can be distinguished from AuthUser by type', () {
      final User authUser = AuthUser(id: '', displayName: '');
      final User placeholder = PlaceholderUser();

      expect(authUser is PlaceholderUser, isFalse);
      expect(placeholder is PlaceholderUser, isTrue);
      expect(placeholder is AuthUser, isTrue);
    });

    test('placeholder equals another placeholder with same id', () {
      final placeholder1 = PlaceholderUser();
      final placeholder2 = PlaceholderUser();

      // Both have empty id
      expect(placeholder1, equals(placeholder2));
    });

    test('placeholder equals AuthUser with same (empty) id', () {
      final placeholder = PlaceholderUser();
      final authUser = AuthUser(id: '', displayName: 'Some Name');

      expect(placeholder, equals(authUser));
    });
  });

  group('User type checking', () {
    test('can distinguish between user types at runtime', () {
      final authUser = AuthUser(id: '1', displayName: 'Auth');
      final signedOut = SignedOutUser(id: '2', displayName: 'SignedOut');
      final placeholder = PlaceholderUser();

      bool isSignedIn(User user) {
        return user is! PlaceholderUser && user is! SignedOutUser;
      }

      expect(isSignedIn(authUser), isTrue);
      expect(isSignedIn(signedOut), isFalse);
      expect(isSignedIn(placeholder), isFalse);
    });
  });
}
