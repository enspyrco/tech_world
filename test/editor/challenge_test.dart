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

  group('Predefined Challenges', () {
    test('helloDart has correct id', () {
      expect(helloDart.id, equals('hello_dart'));
    });

    test('sumList has correct id', () {
      expect(sumList.id, equals('sum_list'));
    });

    test('fizzbuzz has correct id', () {
      expect(fizzbuzz.id, equals('fizzbuzz'));
    });

    test('allChallenges contains all challenges', () {
      expect(allChallenges, contains(helloDart));
      expect(allChallenges, contains(sumList));
      expect(allChallenges, contains(fizzbuzz));
      expect(allChallenges.length, equals(3));
    });

    test('all challenges have non-empty fields', () {
      for (final challenge in allChallenges) {
        expect(challenge.id, isNotEmpty);
        expect(challenge.title, isNotEmpty);
        expect(challenge.description, isNotEmpty);
        expect(challenge.starterCode, isNotEmpty);
      }
    });

    test('all challenges have unique ids', () {
      final ids = allChallenges.map((c) => c.id).toSet();
      expect(ids.length, equals(allChallenges.length));
    });
  });
}
