import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/prompt/cast_result.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/prompt/spell_school.dart';

void main() {
  group('SpellSchool', () {
    test('has six values', () {
      expect(SpellSchool.values.length, equals(6));
    });

    test('has correct values', () {
      expect(SpellSchool.values, contains(SpellSchool.evocation));
      expect(SpellSchool.values, contains(SpellSchool.divination));
      expect(SpellSchool.values, contains(SpellSchool.transmutation));
      expect(SpellSchool.values, contains(SpellSchool.illusion));
      expect(SpellSchool.values, contains(SpellSchool.enchantment));
      expect(SpellSchool.values, contains(SpellSchool.conjuration));
    });
  });

  group('EvaluationTier', () {
    test('has three values', () {
      expect(EvaluationTier.values.length, equals(3));
    });

    test('has correct values', () {
      expect(EvaluationTier.values, contains(EvaluationTier.deterministic));
      expect(EvaluationTier.values, contains(EvaluationTier.structural));
      expect(EvaluationTier.values, contains(EvaluationTier.behavioral));
    });
  });

  group('CastFeedback', () {
    test('has four values', () {
      expect(CastFeedback.values.length, equals(4));
    });

    test('values are ordered worst to best', () {
      expect(CastFeedback.unclear.index, lessThan(CastFeedback.fizzled.index));
      expect(
          CastFeedback.fizzled.index, lessThan(CastFeedback.backfired.index));
      expect(
          CastFeedback.backfired.index, lessThan(CastFeedback.resonates.index));
    });
  });

  group('CastResult', () {
    test('creates with required fields', () {
      const result = CastResult(
        passed: true,
        feedback: CastFeedback.resonates,
      );

      expect(result.passed, isTrue);
      expect(result.feedback, equals(CastFeedback.resonates));
      expect(result.judgeReasoning, isNull);
    });

    test('creates with judge reasoning', () {
      const result = CastResult(
        passed: false,
        feedback: CastFeedback.fizzled,
        judgeReasoning: 'The response was close but missed the key criterion.',
      );

      expect(result.passed, isFalse);
      expect(result.feedback, equals(CastFeedback.fizzled));
      expect(result.judgeReasoning,
          equals('The response was close but missed the key criterion.'));
    });
  });

  group('PromptChallenge', () {
    test('creates with all required fields', () {
      const challenge = PromptChallenge(
        id: 'test_challenge',
        title: 'Test Challenge',
        description: 'A test challenge description.',
        school: SpellSchool.evocation,
        difficulty: Difficulty.beginner,
        generationSystemPrompt: 'You are a helpful assistant.',
        evaluationCriteria: 'The response should say hello.',
        evaluationPrompt: 'Does this response say hello?',
        tier: EvaluationTier.deterministic,
      );

      expect(challenge.id, equals('test_challenge'));
      expect(challenge.title, equals('Test Challenge'));
      expect(challenge.description, equals('A test challenge description.'));
      expect(challenge.school, equals(SpellSchool.evocation));
      expect(challenge.difficulty, equals(Difficulty.beginner));
      expect(
          challenge.generationSystemPrompt, equals('You are a helpful assistant.'));
      expect(challenge.evaluationCriteria,
          equals('The response should say hello.'));
      expect(
          challenge.evaluationPrompt, equals('Does this response say hello?'));
      expect(challenge.tier, equals(EvaluationTier.deterministic));
    });

    test('is const-constructible', () {
      const challenge = PromptChallenge(
        id: 'const_test',
        title: 'Const',
        description: 'Const desc',
        school: SpellSchool.conjuration,
        difficulty: Difficulty.advanced,
        generationSystemPrompt: 'sys',
        evaluationCriteria: 'criteria',
        evaluationPrompt: 'prompt',
        tier: EvaluationTier.behavioral,
      );

      expect(challenge.id, equals('const_test'));
    });

    test('reuses Difficulty enum from editor/challenge.dart', () {
      const challenge = PromptChallenge(
        id: 'difficulty_test',
        title: 'Difficulty',
        description: 'Tests difficulty reuse',
        school: SpellSchool.illusion,
        difficulty: Difficulty.intermediate,
        generationSystemPrompt: 'sys',
        evaluationCriteria: 'criteria',
        evaluationPrompt: 'prompt',
        tier: EvaluationTier.structural,
      );

      // The Difficulty enum is the same one used by code challenges.
      expect(challenge.difficulty, equals(Difficulty.intermediate));
      expect(Difficulty.values.length, equals(3));
    });
  });
}
