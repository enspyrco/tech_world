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

    test('wordById has no silent duplicate-id collisions', () {
      // Catches: two WordOfPower instances accidentally sharing a WordId,
      // which would silently overwrite in the map literal and leave one
      // word unreachable. Cardinality (|values| == |allWords|) follows
      // from the two bijection tests above; this is the one extra failure
      // mode they don't cover.
      expect(wordById.length, WordId.values.length,
          reason: 'wordById is missing entries — a duplicate id in '
              'allWords would collapse two entries into one');
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

    test('displayName is non-empty uppercase for every WordId '
        '(incantation contract)', () {
      // The spellbook panel and speech-cast overlay both render this
      // string. The widget tests in spellbook_panel_test.dart only
      // exercise IGNIS — they would not catch a per-value regression
      // (e.g. a special case that returns the lowercase `name` for some
      // particular WordId). This pins the *contract* — uppercase
      // incantation form, non-empty — for every value, without locking
      // the implementation to `name.toUpperCase()` (so a future
      // localization or pronunciation pass can change how it's computed
      // without breaking this test).
      for (final id in WordId.values) {
        expect(id.displayName, isNotEmpty,
            reason: '${id.name} displayName must not be empty');
        expect(id.displayName, equals(id.displayName.toUpperCase()),
            reason: '${id.name} displayName must be all uppercase');
      }
    });
  });
}
