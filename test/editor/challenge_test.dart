import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/editor/predefined_challenges.dart';

void main() {
  group('Challenge', () {
    test('creates challenge with required fields', () {
      const challenge = Challenge(
        id: 'test',
        title: 'Test Challenge',
        description: 'A test description.',
        starterCode: 'void main() {}',
      );

      expect(challenge.id, equals('test'));
      expect(challenge.title, equals('Test Challenge'));
      expect(challenge.description, equals('A test description.'));
      expect(challenge.starterCode, equals('void main() {}'));
    });

    test('defaults to beginner difficulty', () {
      const challenge = Challenge(
        id: 'test',
        title: 'Test',
        description: 'Desc',
        starterCode: '',
      );

      expect(challenge.difficulty, equals(Difficulty.beginner));
    });

    test('accepts explicit difficulty', () {
      const challenge = Challenge(
        id: 'test',
        title: 'Test',
        description: 'Desc',
        starterCode: '',
        difficulty: Difficulty.advanced,
      );

      expect(challenge.difficulty, equals(Difficulty.advanced));
    });

    test('is const-constructible', () {
      const challenge = Challenge(
        id: 'const_test',
        title: 'Const',
        description: 'Const desc',
        starterCode: '',
      );

      expect(challenge.id, equals('const_test'));
    });
  });

  group('Difficulty', () {
    test('has three values', () {
      expect(Difficulty.values.length, equals(3));
    });

    test('has correct values', () {
      expect(Difficulty.values, contains(Difficulty.beginner));
      expect(Difficulty.values, contains(Difficulty.intermediate));
      expect(Difficulty.values, contains(Difficulty.advanced));
    });
  });

  group('Predefined Challenges', () {
    test('has 23 total challenges', () {
      expect(allChallenges.length, equals(23));
    });

    test('has 10 beginner challenges', () {
      final beginnerChallenges =
          allChallenges.where((c) => c.difficulty == Difficulty.beginner);
      expect(beginnerChallenges.length, equals(10));
    });

    test('has 7 intermediate challenges', () {
      final intermediateChallenges =
          allChallenges.where((c) => c.difficulty == Difficulty.intermediate);
      expect(intermediateChallenges.length, equals(7));
    });

    test('has 6 advanced challenges', () {
      final advancedChallenges =
          allChallenges.where((c) => c.difficulty == Difficulty.advanced);
      expect(advancedChallenges.length, equals(6));
    });

    test('allChallenges contains original challenges', () {
      expect(allChallenges, contains(helloDart));
      expect(allChallenges, contains(sumList));
      expect(allChallenges, contains(fizzbuzz));
    });

    test('all challenges have non-empty fields', () {
      for (final challenge in allChallenges) {
        expect(challenge.id, isNotEmpty,
            reason: '${challenge.title} should have a non-empty id');
        expect(challenge.title, isNotEmpty,
            reason: '${challenge.id} should have a non-empty title');
        expect(challenge.description, isNotEmpty,
            reason: '${challenge.id} should have a non-empty description');
        expect(challenge.starterCode, isNotEmpty,
            reason: '${challenge.id} should have non-empty starter code');
      }
    });

    test('all challenges have unique ids', () {
      final ids = allChallenges.map((c) => c.id).toSet();
      expect(ids.length, equals(allChallenges.length));
    });

    test('all challenges have unique titles', () {
      final titles = allChallenges.map((c) => c.title).toSet();
      expect(titles.length, equals(allChallenges.length));
    });

    test('challenges are ordered by difficulty', () {
      var lastDifficulty = Difficulty.beginner;
      for (final challenge in allChallenges) {
        expect(challenge.difficulty.index,
            greaterThanOrEqualTo(lastDifficulty.index),
            reason:
                '${challenge.id} (${challenge.difficulty}) should not come '
                'after a $lastDifficulty challenge');
        lastDifficulty = challenge.difficulty;
      }
    });

    test('all starter code contains a main function', () {
      for (final challenge in allChallenges) {
        expect(challenge.starterCode, contains('main()'),
            reason: '${challenge.id} starter code should contain main()');
      }
    });

    test('all starter code contains a TODO comment', () {
      for (final challenge in allChallenges) {
        expect(challenge.starterCode, contains('// TODO'),
            reason: '${challenge.id} starter code should contain a TODO');
      }
    });
  });
}
