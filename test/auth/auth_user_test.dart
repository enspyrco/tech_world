import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/auth/auth_user.dart';

void main() {
  group('SignedInUser', () {
    test('creates user with id and displayName', () {
      const user = SignedInUser(id: 'user-123', displayName: 'John Doe');

      expect(user.id, equals('user-123'));
      expect(user.displayName, equals('John Doe'));
    });

    test('is an AuthUser and User', () {
      const user = SignedInUser(id: 'user-456', displayName: 'Jane');

      expect(user, isA<AuthUser>());
      expect(user, isA<User>());
    });

    test('can have empty displayName', () {
      const user = SignedInUser(id: 'user-789', displayName: '');

      expect(user.displayName, equals(''));
    });

    group('equality', () {
      test('users with same id are equal', () {
        const user1 = SignedInUser(id: 'same-id', displayName: 'Name 1');
        const user2 = SignedInUser(id: 'same-id', displayName: 'Name 2');

        expect(user1, equals(user2));
      });

      test('users with different id are not equal', () {
        const user1 = SignedInUser(id: 'id-1', displayName: 'Same Name');
        const user2 = SignedInUser(id: 'id-2', displayName: 'Same Name');

        expect(user1, isNot(equals(user2)));
      });

      test('SignedInUser equals SignedOutUser with same id', () {
        const signedIn = SignedInUser(id: 'shared-id', displayName: 'Name');
        const signedOut =
            SignedOutUser(id: 'shared-id', displayName: 'Name');

        expect(signedIn, equals(signedOut));
      });

      test('equality is reflexive', () {
        const user = SignedInUser(id: 'test-id', displayName: 'Test');

        expect(user == user, isTrue);
      });

      test('equals method handles different types', () {
        const user = SignedInUser(id: 'test', displayName: 'Test');
        // Test that operator== returns false for non-AuthUser objects
        // ignore: unrelated_type_equality_checks
        expect(user == 'test', isFalse);
      });
    });

    group('hashCode', () {
      test('hashCode is based on id', () {
        const user = SignedInUser(id: 'hash-test', displayName: 'Name');

        expect(user.hashCode, equals('hash-test'.hashCode));
      });

      test('equal users have equal hashCode', () {
        const user1 = SignedInUser(id: 'same', displayName: 'Name 1');
        const user2 = SignedInUser(id: 'same', displayName: 'Name 2');

        expect(user1.hashCode, equals(user2.hashCode));
      });

      test('can be used in Set', () {
        const user1 = SignedInUser(id: 'set-test', displayName: 'Name 1');
        const user2 = SignedInUser(id: 'set-test', displayName: 'Name 2');
        const user3 =
            SignedInUser(id: 'different', displayName: 'Name 3');

        final userSet = {user1, user2, user3};

        // user1 and user2 have same id, so set should have 2 items
        expect(userSet.length, equals(2));
      });

      test('can be used as Map key', () {
        const user1 = SignedInUser(id: 'map-key', displayName: 'Name');
        const user2 =
            SignedInUser(id: 'map-key', displayName: 'Different');

        final map = <AuthUser, String>{};
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
      const user =
          SignedOutUser(id: 'signed-out-123', displayName: 'Ex User');

      expect(user.id, equals('signed-out-123'));
      expect(user.displayName, equals('Ex User'));
    });

    test('extends AuthUser', () {
      const user = SignedOutUser(id: 'test', displayName: 'Test');

      expect(user, isA<AuthUser>());
      expect(user, isA<User>());
    });

    test('inherits equality from AuthUser', () {
      const signedOut1 = SignedOutUser(id: 'user-1', displayName: 'A');
      const signedOut2 = SignedOutUser(id: 'user-1', displayName: 'B');

      expect(signedOut1, equals(signedOut2));
    });

    test('can be distinguished from SignedInUser by type', () {
      const AuthUser signedIn =
          SignedInUser(id: 'test', displayName: 'Test');
      const AuthUser signedOut =
          SignedOutUser(id: 'test', displayName: 'Test');

      expect(signedIn is SignedOutUser, isFalse);
      expect(signedOut is SignedOutUser, isTrue);
      expect(signedOut, isA<AuthUser>());
    });
  });

  group('PlaceholderUser', () {
    test('creates placeholder with default empty values', () {
      const user = PlaceholderUser();

      expect(user.id, equals(''));
      expect(user.displayName, equals(''));
    });

    test('creates placeholder with custom values', () {
      const user =
          PlaceholderUser(id: 'custom-id', displayName: 'Custom Name');

      expect(user.id, equals('custom-id'));
      expect(user.displayName, equals('Custom Name'));
    });

    test('extends AuthUser', () {
      const user = PlaceholderUser();

      expect(user, isA<AuthUser>());
      expect(user, isA<User>());
    });

    test('can be distinguished from SignedInUser by type', () {
      const AuthUser signedIn =
          SignedInUser(id: '', displayName: '');
      const AuthUser placeholder = PlaceholderUser();

      expect(signedIn is PlaceholderUser, isFalse);
      expect(placeholder is PlaceholderUser, isTrue);
      expect(placeholder, isA<AuthUser>());
    });

    test('placeholder equals another placeholder with same id', () {
      const placeholder1 = PlaceholderUser();
      const placeholder2 = PlaceholderUser();

      // Both have empty id
      expect(placeholder1, equals(placeholder2));
    });

    test('placeholder equals SignedInUser with same (empty) id', () {
      const placeholder = PlaceholderUser();
      const signedIn = SignedInUser(id: '', displayName: 'Some Name');

      expect(placeholder, equals(signedIn));
    });
  });

  group('AuthUser type checking', () {
    test('can distinguish between user types at runtime', () {
      const signedIn = SignedInUser(id: '1', displayName: 'Auth');
      const signedOut = SignedOutUser(id: '2', displayName: 'SignedOut');
      const placeholder = PlaceholderUser();

      bool isSignedIn(AuthUser user) {
        return user is SignedInUser;
      }

      expect(isSignedIn(signedIn), isTrue);
      expect(isSignedIn(signedOut), isFalse);
      expect(isSignedIn(placeholder), isFalse);
    });

    test('exhaustive switch covers all summands', () {
      final users = <AuthUser>[
        const SignedInUser(id: '1', displayName: 'A'),
        const SignedOutUser(id: '2', displayName: 'B'),
        const PlaceholderUser(),
      ];

      for (final user in users) {
        final label = switch (user) {
          SignedInUser() => 'signed_in',
          SignedOutUser() => 'signed_out',
          PlaceholderUser() => 'placeholder',
        };
        expect(label, isNotEmpty);
      }
    });
  });
}
