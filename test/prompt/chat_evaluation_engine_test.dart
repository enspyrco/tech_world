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

  group('evaluateDeterministic — FizzBuzz', () {
    test('correct FizzBuzz output passes', () {
      final lines = <String>[];
      for (var i = 1; i <= 20; i++) {
        if (i % 15 == 0) {
          lines.add('FizzBuzz');
        } else if (i % 3 == 0) {
          lines.add('Fizz');
        } else if (i % 5 == 0) {
          lines.add('Buzz');
        } else {
          lines.add('$i');
        }
      }
      final response = lines.join('\n');
      final result = ChatEvaluationEngine.evaluateDeterministic(
        PromptChallengeId.evocationFizzbuzz,
        response,
      );
      expect(result.passed, isTrue);
      expect(result.feedback, CastFeedback.resonates);
    });

    test('wrong line content fails', () {
      final lines = List.generate(20, (i) => '${i + 1}');
      // Line 3 should be "fizz" but is "3".
      final response = lines.join('\n');
      final result = ChatEvaluationEngine.evaluateDeterministic(
        PromptChallengeId.evocationFizzbuzz,
        response,
      );
      expect(result.passed, isFalse);
      expect(result.feedback, CastFeedback.fizzled);
      expect(result.judgeReasoning, contains('Line 3'));
    });

    test('wrong line count fails', () {
      const response = '1\n2\nfizz';
      final result = ChatEvaluationEngine.evaluateDeterministic(
        PromptChallengeId.evocationFizzbuzz,
        response,
      );
      expect(result.passed, isFalse);
      expect(result.judgeReasoning, contains('Expected 20 lines'));
    });
  });

  group('evaluateDeterministic — Countdown', () {
    test('correct zero-padded countdown passes', () {
      const response = '10\n09\n08\n07\n06\n05\n04\n03\n02\n01';
      final result = ChatEvaluationEngine.evaluateDeterministic(
        PromptChallengeId.evocationCountdown,
        response,
      );
      expect(result.passed, isTrue);
      expect(result.feedback, CastFeedback.resonates);
    });

    test('non-padded countdown fails', () {
      const response = '10\n9\n8\n7\n6\n5\n4\n3\n2\n1';
      final result = ChatEvaluationEngine.evaluateDeterministic(
        PromptChallengeId.evocationCountdown,
        response,
      );
      expect(result.passed, isFalse);
      expect(result.judgeReasoning, contains('expected "09"'));
    });

    test('wrong line count fails', () {
      const response = '10\n09\n08';
      final result = ChatEvaluationEngine.evaluateDeterministic(
        PromptChallengeId.evocationCountdown,
        response,
      );
      expect(result.passed, isFalse);
      expect(result.judgeReasoning, contains('Expected 10 lines'));
    });
  });

  group('evaluateDeterministic — JSON', () {
    test('valid 3-object JSON passes', () {
      const response = '''
[
  {"title": "The Great Gatsby", "author": "F. Scott Fitzgerald", "year": 1925},
  {"title": "1984", "author": "George Orwell", "year": 1949},
  {"title": "Dune", "author": "Frank Herbert", "year": 1965}
]
''';
      final result = ChatEvaluationEngine.evaluateDeterministic(
        PromptChallengeId.transmutationJson,
        response,
      );
      expect(result.passed, isTrue);
      expect(result.feedback, CastFeedback.resonates);
    });

    test('missing keys fails', () {
      const response = '''
[
  {"title": "The Great Gatsby"},
  {"title": "1984", "author": "George Orwell", "year": 1949},
  {"title": "Dune", "author": "Frank Herbert", "year": 1965}
]
''';
      final result = ChatEvaluationEngine.evaluateDeterministic(
        PromptChallengeId.transmutationJson,
        response,
      );
      expect(result.passed, isFalse);
      expect(result.judgeReasoning, contains('missing keys'));
    });

    test('non-JSON response fails', () {
      const response = 'Here are three books I recommend.';
      final result = ChatEvaluationEngine.evaluateDeterministic(
        PromptChallengeId.transmutationJson,
        response,
      );
      expect(result.passed, isFalse);
      expect(result.judgeReasoning, contains('No valid JSON'));
    });
  });

  group('evaluateDeterministic — Brevity', () {
    test('under word limit passes', () {
      const response = 'Blue sky today.';
      final result = ChatEvaluationEngine.evaluateDeterministic(
        PromptChallengeId.enchantmentBrevity,
        response,
      );
      expect(result.passed, isTrue);
      expect(result.feedback, CastFeedback.resonates);
    });

    test('over word limit fails', () {
      const response =
          'This is a very long response that has more than ten words '
          'and should definitely fail the word budget check.';
      final result = ChatEvaluationEngine.evaluateDeterministic(
        PromptChallengeId.enchantmentBrevity,
        response,
      );
      expect(result.passed, isFalse);
      expect(result.judgeReasoning, contains('words'));
    });
  });

  group('evaluateDeterministic — Divination Color', () {
    test('response with correct color reveal passes', () {
      const response = 'Yes\nNo\nYes\nThe color is: blue';
      final result = ChatEvaluationEngine.evaluateDeterministic(
        PromptChallengeId.divinationColor,
        response,
      );
      expect(result.passed, isTrue);
      expect(result.feedback, CastFeedback.resonates);
    });

    test('case-insensitive color reveal passes', () {
      const response = 'Yes\nNo\nTHE COLOR IS: BLUE';
      final result = ChatEvaluationEngine.evaluateDeterministic(
        PromptChallengeId.divinationColor,
        response,
      );
      expect(result.passed, isTrue);
    });

    test('wrong color fails', () {
      const response = 'Yes\nNo\nThe color is: red';
      final result = ChatEvaluationEngine.evaluateDeterministic(
        PromptChallengeId.divinationColor,
        response,
      );
      expect(result.passed, isFalse);
      expect(result.judgeReasoning, contains('The color is: blue'));
    });

    test('missing color reveal fails', () {
      const response = 'Yes\nNo\nYes\nI think it might be blue.';
      final result = ChatEvaluationEngine.evaluateDeterministic(
        PromptChallengeId.divinationColor,
        response,
      );
      expect(result.passed, isFalse);
    });
  });

  group('evaluateDeterministic — fallback', () {
    test('unhandled deterministic challenge returns fizzled', () {
      // Use an ID that is not deterministic but exercise the fallback.
      final result = ChatEvaluationEngine.evaluateDeterministic(
        PromptChallengeId.evocationDiamond,
        'some response',
      );
      expect(result.passed, isFalse);
      expect(result.feedback, CastFeedback.fizzled);
      expect(result.judgeReasoning, contains('No local evaluator'));
    });
  });
}
