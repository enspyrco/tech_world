import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/prompt/predefined_prompt_challenges.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/prompt/spell_school.dart';

void main() {
  group('Predefined Prompt Challenges', () {
    test('has 18 total challenges', () {
      expect(allPromptChallenges.length, equals(18));
    });

    // `id` non-empty + uniqueness are now compile-time facts of
    // `enum PromptChallengeId` — no runtime check needed.
    test('all challenges have non-empty text fields', () {
      for (final challenge in allPromptChallenges) {
        expect(challenge.title, isNotEmpty,
            reason: '${challenge.id.name} should have a non-empty title');
        expect(challenge.description, isNotEmpty,
            reason: '${challenge.id.name} should have a non-empty description');
        expect(challenge.generationSystemPrompt, isNotEmpty,
            reason:
                '${challenge.id.name} should have a non-empty generationSystemPrompt');
        expect(challenge.evaluationCriteria, isNotEmpty,
            reason:
                '${challenge.id.name} should have non-empty evaluationCriteria');
        expect(challenge.evaluationPrompt, isNotEmpty,
            reason:
                '${challenge.id.name} should have a non-empty evaluationPrompt');
      }
    });

    test('all challenges have unique titles', () {
      final titles = allPromptChallenges.map((c) => c.title).toSet();
      expect(titles.length, equals(allPromptChallenges.length));
    });

    test('all spell schools are represented', () {
      final schools =
          allPromptChallenges.map((c) => c.school).toSet();
      expect(schools, equals(SpellSchool.values.toSet()));
    });

    test('each school has at least 2 challenges', () {
      for (final school in SpellSchool.values) {
        final count =
            allPromptChallenges.where((c) => c.school == school).length;
        expect(count, greaterThanOrEqualTo(2),
            reason: '${school.name} should have at least 2 challenges, '
                'found $count');
      }
    });

    test('each school has exactly 3 challenges', () {
      for (final school in SpellSchool.values) {
        final count =
            allPromptChallenges.where((c) => c.school == school).length;
        expect(count, equals(3),
            reason:
                '${school.name} should have 3 challenges, found $count');
      }
    });

    test('all evaluation tiers are used', () {
      final tiers =
          allPromptChallenges.map((c) => c.tier).toSet();
      expect(tiers, equals(EvaluationTier.values.toSet()));
    });

    test('all difficulty levels are used', () {
      final difficulties =
          allPromptChallenges.map((c) => c.difficulty).toSet();
      expect(difficulties.length, equals(3));
    });

    test('challenge wireName starts with the school name', () {
      // The naming-convention regex (^[a-z]+_[a-z]+$) is now enforced at
      // the wireName layer — verified once per id by
      // `prompt_challenge_id_test.dart`. What stays repo-specific is the
      // semantic link "wire form starts with school".
      for (final challenge in allPromptChallenges) {
        expect(challenge.id.wireName, startsWith(challenge.school.name),
            reason:
                '${challenge.id.name} wireName=${challenge.id.wireName} '
                'should start with school name ${challenge.school.name}');
      }
    });

    test('evaluation prompts end with PASS/FAIL instruction', () {
      for (final challenge in allPromptChallenges) {
        expect(
          challenge.evaluationPrompt.toLowerCase(),
          contains('pass or fail'),
          reason:
              '${challenge.id} evaluation prompt should ask for PASS/FAIL',
        );
      }
    });
  });
}
