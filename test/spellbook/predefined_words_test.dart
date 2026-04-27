import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/prompt/predefined_prompt_challenges.dart';
import 'package:tech_world/prompt/spell_school.dart';
import 'package:tech_world/spellbook/predefined_words.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

void main() {
  group('predefined_words bijection', () {
    // Most uniqueness/exhaustiveness invariants are now compiler-enforced
    // by `enum WordId`. What remains: the bijection between the *enum*
    // and the *runtime* prompt-challenge list, plus per-word metadata.
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
          reason: 'Word ${word.id.name} references unknown challenge '
              '${word.challengeId}',
        );
      }
    });

    test('|allWords| == |WordId.values| == |allPromptChallenges|', () {
      expect(allWords.length, WordId.values.length);
      expect(allWords.length, allPromptChallenges.length);
    });

    test('wordById is total over WordId.values', () {
      for (final id in WordId.values) {
        expect(wordById[id], isNotNull,
            reason: 'wordById missing entry for $id');
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
          reason: 'Word ${w.id.name} school/element mismatch',
        );
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
      final challengeById = {for (final c in allPromptChallenges) c.id: c};
      for (final w in allWords) {
        final c = challengeById[w.challengeId]!;
        final expected = c.difficulty.index + 1;
        expect(
          w.intensity,
          expected,
          reason: 'Word ${w.id.name} intensity ${w.intensity} '
              'vs challenge ${c.id} difficulty ${c.difficulty}',
        );
      }
    });
  });

  group('WordId', () {
    test('parse round-trips every WordId', () {
      for (final id in WordId.values) {
        expect(WordId.parse(id.name), id);
      }
    });

    test('parse returns null for unknown wire format', () {
      expect(WordId.parse('not_a_word'), isNull);
      expect(WordId.parse(''), isNull);
      expect(WordId.parse('IGNIS'), isNull); // case-sensitive on wire
    });

    test('displayName is uppercase of name', () {
      for (final id in WordId.values) {
        expect(id.displayName, id.name.toUpperCase());
      }
    });
  });
}
