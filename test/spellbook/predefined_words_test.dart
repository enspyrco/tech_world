import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/prompt/predefined_prompt_challenges.dart';
import 'package:tech_world/prompt/spell_school.dart';
import 'package:tech_world/spellbook/predefined_words.dart';

void main() {
  group('predefined_words bijection', () {
    test('every prompt challenge has exactly one word', () {
      for (final challenge in allPromptChallenges) {
        expect(
          challengeToWord.containsKey(challenge.id),
          isTrue,
          reason: 'No word found for challenge "${challenge.id}"',
        );
      }
    });

    test('every word maps back to a real prompt challenge', () {
      final challengeIds = {for (final c in allPromptChallenges) c.id};
      for (final word in allWords) {
        expect(
          challengeIds.contains(word.challengeId),
          isTrue,
          reason:
              'Word ${word.id} references unknown challenge ${word.challengeId}',
        );
      }
    });

    test('exactly 18 words and 18 challenges', () {
      expect(allPromptChallenges.length, 18);
      expect(allWords.length, 18);
    });

    test('word ids are unique', () {
      final ids = allWords.map((w) => w.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('display names are unique', () {
      final names = allWords.map((w) => w.displayName).toList();
      expect(names.toSet().length, names.length);
    });

    test('display name is uppercase of id', () {
      for (final w in allWords) {
        expect(w.displayName, w.id.toUpperCase());
      }
    });

    test('intensity is 1, 2, or 3', () {
      for (final w in allWords) {
        expect(w.intensity, inInclusiveRange(1, 3));
      }
    });

    test('element matches schoolElement mapping', () {
      for (final w in allWords) {
        expect(
          w.element,
          schoolElement[w.school],
          reason: 'Word ${w.id} school/element mismatch',
        );
      }
    });

    test('schoolElement covers every school', () {
      for (final school in SpellSchool.values) {
        expect(schoolElement.containsKey(school), isTrue);
      }
    });

    test('wordById round-trips every word', () {
      for (final w in allWords) {
        expect(wordById[w.id], same(w));
      }
    });

    test('three words per school', () {
      final counts = <SpellSchool, int>{};
      for (final w in allWords) {
        counts[w.school] = (counts[w.school] ?? 0) + 1;
      }
      for (final school in SpellSchool.values) {
        expect(counts[school], 3, reason: 'school $school');
      }
    });

    test('word intensity matches challenge difficulty', () {
      // The plan: intensity mirrors Difficulty.beginner=1, intermediate=2,
      // advanced=3. Verify any drift between table and source.
      final challengeById = {for (final c in allPromptChallenges) c.id: c};
      for (final w in allWords) {
        final c = challengeById[w.challengeId]!;
        final expected = c.difficulty.index + 1;
        expect(
          w.intensity,
          expected,
          reason: 'Word ${w.id} intensity ${w.intensity} '
              'vs challenge ${c.id} difficulty ${c.difficulty}',
        );
      }
    });
  });
}
