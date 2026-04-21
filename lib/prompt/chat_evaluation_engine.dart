import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/prompt/cast_result.dart';
import 'package:tech_world/prompt/evaluation_engine.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';

/// Evaluates prompt challenges by sending formatted messages to the bot
/// via [ChatService] and parsing the response for PASS/FAIL markers.
///
/// MVP approach: single round-trip where the bot both responds to the
/// player's prompt AND evaluates whether the response meets criteria.
/// The two-call separation (generation → judge) comes later.
class ChatEvaluationEngine extends EvaluationEngine {
  ChatEvaluationEngine(this._chatService);

  final ChatService _chatService;

  @override
  Future<(String, CastResult)> evaluate(
    PromptChallenge challenge,
    String playerPrompt,
  ) async {
    final message = formatChallengeMessage(challenge, playerPrompt);
    final response = await _chatService.sendMessage(
      message,
      metadata: {
        'promptChallengeId': challenge.id,
        'promptChallengeType': 'cast',
      },
    );

    // Extract the bot's text response from the chat response payload.
    final responseText = response?['text'] as String? ?? '';
    if (responseText.isEmpty) {
      return (
        '',
        const CastResult(
          passed: false,
          feedback: CastFeedback.unclear,
          judgeReasoning: 'No response received from the agent.',
        ),
      );
    }

    return (responseText, parseResponse(responseText));
  }

  /// Format the challenge + player prompt into a message for the bot.
  ///
  /// Visible for testing.
  static String formatChallengeMessage(
    PromptChallenge challenge,
    String playerPrompt,
  ) {
    return '[PROMPT CHALLENGE: ${challenge.title}]\n'
        'Context: ${challenge.generationSystemPrompt}\n'
        'Challenge: ${challenge.description}\n'
        'Criteria: ${challenge.evaluationCriteria}\n'
        '\n'
        "Player's incantation:\n"
        '$playerPrompt\n'
        '\n'
        'Instructions: First, respond to the player\'s prompt following '
        'the context above. Then evaluate your own response against the '
        'criteria.\n'
        'End with exactly one of: RESULT:PASS or RESULT:FAIL\n'
        'If FAIL, also include one of: FEEDBACK:unclear FEEDBACK:fizzled '
        'FEEDBACK:backfired';
  }

  /// Parse the bot's response text for RESULT and FEEDBACK markers.
  ///
  /// Visible for testing.
  static CastResult parseResponse(String responseText) {
    // Match RESULT: only at line start (or start of string) to reduce
    // the risk of a player embedding RESULT:PASS in their prompt text.
    final resultPattern = RegExp(r'(^|\n)\s*RESULT:', caseSensitive: false);
    final hasResult = resultPattern.hasMatch(responseText);
    final upper = responseText.toUpperCase();
    final passed = hasResult && upper.contains('RESULT:PASS');

    if (passed) {
      return CastResult(
        passed: true,
        feedback: CastFeedback.resonates,
        judgeReasoning: _extractReasoning(responseText),
      );
    }

    // Determine feedback category from FEEDBACK: marker.
    final CastFeedback feedback;
    if (upper.contains('FEEDBACK:BACKFIRED')) {
      feedback = CastFeedback.backfired;
    } else if (upper.contains('FEEDBACK:FIZZLED')) {
      feedback = CastFeedback.fizzled;
    } else if (upper.contains('FEEDBACK:UNCLEAR')) {
      feedback = CastFeedback.unclear;
    } else {
      // No explicit marker — default to fizzled (close but not quite).
      feedback = CastFeedback.fizzled;
    }

    return CastResult(
      passed: false,
      feedback: feedback,
      judgeReasoning: _extractReasoning(responseText),
    );
  }

  /// Extract the agent's actual response (before the RESULT marker).
  static String? _extractReasoning(String text) {
    // Take everything before the first RESULT: marker as the reasoning.
    final resultIndex = text.toUpperCase().indexOf('RESULT:');
    if (resultIndex > 0) {
      return text.substring(0, resultIndex).trim();
    }
    return null;
  }
}
