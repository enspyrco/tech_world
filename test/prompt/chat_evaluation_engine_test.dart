import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/prompt/cast_result.dart';
import 'package:tech_world/prompt/chat_evaluation_engine.dart';
import 'package:tech_world/prompt/predefined_prompt_challenges.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';

void main() {
  group('buildMetadata', () {
    // Regression contract: the metadata payload that accompanies a
    // cast evaluation MUST be JSON-encodable, and `promptChallengeId`
    // MUST be the wire-format String — never a typed enum.
    //
    // Defends against a class of bug where `Map<String, dynamic>` lets
    // an enum value silently land in the payload, then either fails
    // `jsonEncode` (`JsonUnsupportedObjectError`) or stringifies to
    // `PromptChallengeId.evocationFizzbuzz` instead of
    // `'evocation_fizzbuzz'`. Found in PR #306 review (Kelvin).
    test('metadata is JSON-encodable for every PromptChallengeId', () {
      for (final challenge in allPromptChallenges) {
        final metadata = ChatEvaluationEngine.buildMetadata(challenge);
        expect(() => jsonEncode(metadata), returnsNormally,
            reason: 'metadata for ${challenge.id.name} should '
                'jsonEncode without throwing');
      }
    });

    test('promptChallengeId is the wireName String, not the typed enum',
        () {
      for (final challenge in allPromptChallenges) {
        final metadata = ChatEvaluationEngine.buildMetadata(challenge);
        expect(metadata['promptChallengeId'], isA<String>(),
            reason: 'enum value leaked into the wire payload');
        expect(metadata['promptChallengeId'], challenge.id.wireName);
      }
    });

    test('round-trips cleanly through JSON', () {
      // The bot side will jsonDecode this — verify the round-trip
      // preserves every field as a plain String.
      final challenge =
          allPromptChallenges.firstWhere((c) => c.id == PromptChallengeId.evocationFizzbuzz);
      final metadata = ChatEvaluationEngine.buildMetadata(challenge);
      final encoded = jsonEncode(metadata);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded['promptChallengeId'], 'evocation_fizzbuzz');
      expect(decoded['promptChallengeType'], 'cast');
    });
  });

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
