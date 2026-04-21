import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/prompt/cast_result.dart';
import 'package:tech_world/prompt/chat_evaluation_engine.dart';
import 'package:tech_world/prompt/predefined_prompt_challenges.dart';

void main() {
  group('formatChallengeMessage', () {
    test('includes challenge metadata and player prompt', () {
      final challenge = allPromptChallenges.first;
      const prompt = 'List the numbers with replacements.';

      final message =
          ChatEvaluationEngine.formatChallengeMessage(challenge, prompt);

      expect(message, contains('[PROMPT CHALLENGE: ${challenge.title}]'));
      expect(message, contains('Context: ${challenge.generationSystemPrompt}'));
      expect(message, contains('Criteria: ${challenge.evaluationCriteria}'));
      expect(message, contains("Player's incantation:"));
      expect(message, contains(prompt));
      expect(message, contains('RESULT:PASS'));
      expect(message, contains('RESULT:FAIL'));
    });
  });

  group('parseResponse', () {
    test('RESULT:PASS returns passing result with resonates feedback', () {
      const response = 'Here is the output:\n1\n2\nfizz\nRESULT:PASS';
      final result = ChatEvaluationEngine.parseResponse(response);

      expect(result.passed, isTrue);
      expect(result.feedback, CastFeedback.resonates);
    });

    test('RESULT:FAIL with FEEDBACK:unclear', () {
      const response = 'I did not understand.\nRESULT:FAIL\nFEEDBACK:unclear';
      final result = ChatEvaluationEngine.parseResponse(response);

      expect(result.passed, isFalse);
      expect(result.feedback, CastFeedback.unclear);
    });

    test('RESULT:FAIL with FEEDBACK:fizzled', () {
      const response = 'Close but wrong.\nRESULT:FAIL\nFEEDBACK:fizzled';
      final result = ChatEvaluationEngine.parseResponse(response);

      expect(result.passed, isFalse);
      expect(result.feedback, CastFeedback.fizzled);
    });

    test('RESULT:FAIL with FEEDBACK:backfired', () {
      const response = 'Opposite effect.\nRESULT:FAIL\nFEEDBACK:backfired';
      final result = ChatEvaluationEngine.parseResponse(response);

      expect(result.passed, isFalse);
      expect(result.feedback, CastFeedback.backfired);
    });

    test('RESULT:FAIL without feedback marker defaults to fizzled', () {
      const response = 'Not quite right.\nRESULT:FAIL';
      final result = ChatEvaluationEngine.parseResponse(response);

      expect(result.passed, isFalse);
      expect(result.feedback, CastFeedback.fizzled);
    });

    test('case insensitive parsing', () {
      const response = 'All good!\nresult:pass';
      final result = ChatEvaluationEngine.parseResponse(response);

      expect(result.passed, isTrue);
      expect(result.feedback, CastFeedback.resonates);
    });

    test('extracts reasoning before RESULT marker', () {
      const response =
          'The agent produced 10, 09, 08... correctly.\nRESULT:PASS';
      final result = ChatEvaluationEngine.parseResponse(response);

      expect(result.judgeReasoning, isNotNull);
      expect(
        result.judgeReasoning,
        contains('The agent produced 10, 09, 08'),
      );
    });

    test('no RESULT marker defaults to fail with fizzled', () {
      const response = 'Just some text with no markers.';
      final result = ChatEvaluationEngine.parseResponse(response);

      expect(result.passed, isFalse);
      expect(result.feedback, CastFeedback.fizzled);
    });
  });
}
