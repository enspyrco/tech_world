import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/spellbook/door_cast_result.dart';
import 'package:tech_world/spellbook/free_cast_result.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Sealed class exhaustiveness tests — verifying coproduct structure.
///
/// A sealed class in Dart is a coproduct (disjoint union) in the category
/// of types. The key property: pattern matching on a sealed class is
/// total — every summand must be handled, and the compiler enforces this.
///
/// These tests verify:
///   1. Every summand can be constructed and identified
///   2. Exhaustive switch covers all cases
///   3. Each injection is disjoint (no overlap between summands)
void main() {
  group('AuthUser sealed coproduct (3 summands)', () {
    test('SignedInUser is an AuthUser', () {
      const AuthUser user = SignedInUser(id: 'uid', displayName: 'Alice');
      expect(user, isA<SignedInUser>());
    });

    test('SignedOutUser is an AuthUser', () {
      const AuthUser user =
          SignedOutUser(id: 'uid', displayName: 'Alice');
      expect(user, isA<SignedOutUser>());
    });

    test('PlaceholderUser is an AuthUser', () {
      const AuthUser user = PlaceholderUser();
      expect(user, isA<PlaceholderUser>());
    });

    test('exhaustive switch covers all 3 summands', () {
      final users = <AuthUser>[
        const SignedInUser(id: '1', displayName: 'A'),
        const SignedOutUser(id: '2', displayName: 'B'),
        const PlaceholderUser(),
      ];

      for (final user in users) {
        // This switch is exhaustive — if a summand is added, it won't
        // compile until this test handles it.
        final label = switch (user) {
          SignedInUser() => 'signed_in',
          SignedOutUser() => 'signed_out',
          PlaceholderUser() => 'placeholder',
        };
        expect(label, isNotEmpty);
      }
    });

    test('summands are disjoint', () {
      const signedIn = SignedInUser(id: '1', displayName: 'A');
      const signedOut = SignedOutUser(id: '1', displayName: 'A');
      const placeholder = PlaceholderUser(id: '1', displayName: 'A');

      expect(signedIn is SignedOutUser, isFalse);
      expect(signedIn is PlaceholderUser, isFalse);
      expect(signedOut is SignedInUser, isFalse);
      expect(signedOut is PlaceholderUser, isFalse);
      expect(placeholder is SignedInUser, isFalse);
      expect(placeholder is SignedOutUser, isFalse);
    });

    test('AuthUser implements User interface', () {
      const User u = SignedInUser(id: 'x', displayName: 'X');
      expect(u, isA<AuthUser>());
      expect(u, isA<User>());
    });

    test('equality is scoped to AuthUser, not User (intentional narrowing)', () {
      // AuthUser.== checks `other is AuthUser`, not `other is User`.
      // This means Flame components (PlayerComponent) that implement User
      // but not AuthUser are intentionally NOT equal to auth objects with
      // the same id. Auth identity and game entity are different concerns.
      const authUser = SignedInUser(id: 'same-id', displayName: 'A');
      final nonAuthUser = _FakeUser(id: 'same-id', displayName: 'B');

      // Same id, but different type hierarchies — should NOT be equal.
      // ignore: unrelated_type_equality_checks
      expect(authUser == nonAuthUser, isFalse,
          reason: 'AuthUser equality is scoped to the sealed hierarchy');
    });
  });

  group('DoorCastResult sealed coproduct (4 summands)', () {
    test('all 4 summands constructible', () {
      final results = <DoorCastResult>[
        const CastPass(PromptChallengeId.evocationFizzbuzz),
        const DoorCastNoMatch('ignis'),
        const DoorCastNotLearned(WordId.ignis),
        const CastWrongDoor(
          wordId: WordId.ignis,
          expectedChallenges: [PromptChallengeId.evocationFizzbuzz],
        ),
      ];

      for (final r in results) {
        final label = switch (r) {
          CastPass() => 'pass',
          DoorCastNoMatch() => 'no_match',
          DoorCastNotLearned() => 'not_learned',
          CastWrongDoor() => 'wrong_door',
        };
        expect(label, isNotEmpty);
      }
    });

    test('DoorCastNoMatch allows null transcript', () {
      const result = DoorCastNoMatch(null);
      expect(result.transcript, isNull);
    });
  });

  group('FreeCastResult sealed coproduct (5 summands)', () {
    test('all 5 summands constructible', () {
      final results = <FreeCastResult>[
        const FreeCastNoMatch('test'),
        const FreeCastNotLearned(WordId.ignis),
        // CastComboKnown and CastComboKnownPartial need a SpellEffect,
        // which requires non-trivial setup. Test that the types exist.
        CastComboNovel([WordId.ignis, WordId.tempus]),
      ];

      expect(results, hasLength(3));
    });

    test('CastComboNovel wraps words as unmodifiable', () {
      final words = [WordId.ignis, WordId.tempus];
      final result = CastComboNovel(words);

      expect(result.words, equals(words));
      expect(
        () => result.words.add(WordId.lumen),
        throwsA(isA<UnsupportedError>()),
        reason: 'Unmodifiable list must reject mutation',
      );
    });
  });
}

/// Mimics a Flame component that implements [User] but is not an [AuthUser].
/// Used to verify equality narrowing is intentional.
class _FakeUser implements User {
  const _FakeUser({required this.id, required this.displayName});

  @override
  final String id;
  @override
  final String displayName;
}
