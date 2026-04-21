import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/prompt/cast_result.dart';
import 'package:tech_world/prompt/evaluation_engine.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/prompt/spell_school.dart';

void main() {
  const testChallenge = PromptChallenge(
    id: 'test',
    title: 'Test',
    description: 'Test challenge',
    school: SpellSchool.evocation,
    difficulty: Difficulty.beginner,
    generationSystemPrompt: 'You are a test assistant.',
    evaluationCriteria: 'Say hello.',
    evaluationPrompt: 'Did it say hello?',
    tier: EvaluationTier.deterministic,
  );

  group('MockEvaluationEngine', () {
    test('returns default passing result', () async {
      final engine = MockEvaluationEngine();

      final (response, result) =
          await engine.evaluate(testChallenge, 'Say hello');

      expect(response, equals('Mock agent response.'));
      expect(result.passed, isTrue);
      expect(result.feedback, equals(CastFeedback.resonates));
      expect(result.judgeReasoning, isNull);
    });

    test('returns custom response text', () async {
      final engine =
          MockEvaluationEngine(responseText: 'Custom response.');

      final (response, _) =
          await engine.evaluate(testChallenge, 'anything');

      expect(response, equals('Custom response.'));
    });

    test('cycles through provided results', () async {
      final engine = MockEvaluationEngine(
        results: [
          const CastResult(passed: true, feedback: CastFeedback.resonates),
          const CastResult(passed: false, feedback: CastFeedback.fizzled),
          const CastResult(
            passed: false,
            feedback: CastFeedback.backfired,
            judgeReasoning: 'Opposite effect.',
          ),
        ],
      );

      final (_, result1) = await engine.evaluate(testChallenge, 'prompt 1');
      expect(result1.passed, isTrue);
      expect(result1.feedback, equals(CastFeedback.resonates));

      final (_, result2) = await engine.evaluate(testChallenge, 'prompt 2');
      expect(result2.passed, isFalse);
      expect(result2.feedback, equals(CastFeedback.fizzled));

      final (_, result3) = await engine.evaluate(testChallenge, 'prompt 3');
      expect(result3.passed, isFalse);
      expect(result3.feedback, equals(CastFeedback.backfired));
      expect(result3.judgeReasoning, equals('Opposite effect.'));
    });

    test('wraps around when results are exhausted', () async {
      final engine = MockEvaluationEngine(
        results: [
          const CastResult(passed: true, feedback: CastFeedback.resonates),
          const CastResult(passed: false, feedback: CastFeedback.unclear),
        ],
      );

      // Consume both results
      await engine.evaluate(testChallenge, 'prompt 1');
      await engine.evaluate(testChallenge, 'prompt 2');

      // Should wrap back to first result
      final (_, result3) = await engine.evaluate(testChallenge, 'prompt 3');
      expect(result3.passed, isTrue);
      expect(result3.feedback, equals(CastFeedback.resonates));
    });

    test('tracks call count', () async {
      final engine = MockEvaluationEngine();

      expect(engine.callCount, equals(0));
      await engine.evaluate(testChallenge, 'prompt 1');
      expect(engine.callCount, equals(1));
      await engine.evaluate(testChallenge, 'prompt 2');
      expect(engine.callCount, equals(2));
    });

    test('returns each feedback category correctly', () async {
      for (final feedback in CastFeedback.values) {
        final passed = feedback == CastFeedback.resonates;
        final engine = MockEvaluationEngine(
          results: [CastResult(passed: passed, feedback: feedback)],
        );

        final (_, result) = await engine.evaluate(testChallenge, 'test');
        expect(result.feedback, equals(feedback));
        expect(result.passed, equals(passed));
      }
    });
  });
}
