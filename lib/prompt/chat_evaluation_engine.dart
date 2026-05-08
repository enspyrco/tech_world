import 'dart:convert';

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
///
/// For [EvaluationTier.deterministic] challenges, the bot still generates
/// a response but evaluation is done locally with programmatic checks
/// rather than relying on the bot's self-judgment. This is faster, more
/// reliable, and degrades gracefully when the bot is slow or offline.
class ChatEvaluationEngine extends EvaluationEngine {
  ChatEvaluationEngine(this._chatService);

  final ChatService _chatService;

  /// Match the chat service's own 30-second response timeout so a hung bot
  /// cannot block the UI indefinitely.
  static const _evaluationTimeout = Duration(seconds: 30);

  @override
  Future<(String, CastResult)> evaluate(
    PromptChallenge challenge,
    String playerPrompt,
  ) async {
    return _evaluate(challenge, playerPrompt).timeout(
      _evaluationTimeout,
      onTimeout: () => (
        '',
        const CastResult(
          passed: false,
          feedback: CastFeedback.unclear,
          judgeReasoning: 'Evaluation timed out.',
        ),
      ),
    );
  }

  Future<(String, CastResult)> _evaluate(
    PromptChallenge challenge,
    String playerPrompt,
  ) async {
    final message = formatChallengeMessage(challenge, playerPrompt);
    final response = await _chatService.sendMessage(
      message,
      metadata: buildMetadata(challenge),
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

    // Deterministic challenges are evaluated locally — no RESULT:PASS/FAIL
    // parsing needed. This is faster, more reliable, and works even when
    // the bot's self-evaluation is inconsistent.
    if (challenge.tier == EvaluationTier.deterministic) {
      return (responseText, evaluateDeterministic(challenge.id, responseText));
    }

    return (responseText, parseResponse(responseText));
  }

  /// Build the wire-format metadata payload that accompanies the chat
  /// message to the bot.
  ///
  /// Extracted as a pure static method so the wire-format contract can
  /// be tested without mocking [ChatService]. Critical that
  /// `promptChallengeId` is the [PromptChallengeId.wireName] (a `String`)
  /// — passing the enum value directly would round-trip through
  /// `Object.toString()` and break the bot-side parser, since
  /// `Map<String, dynamic>` swallows the type at compile time.
  static Map<String, dynamic> buildMetadata(PromptChallenge challenge) => {
        'promptChallengeId': challenge.id.wireName,
        'promptChallengeType': 'cast',
      };

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
    // Anchor RESULT:PASS and RESULT:FAIL to line start to prevent prompt
    // injection — a player embedding "RESULT:PASS" mid-text must not
    // trigger a spurious pass.
    final passPattern = RegExp(
      r'^\s*RESULT:PASS\s*$',
      caseSensitive: false,
      multiLine: true,
    );
    final passed = passPattern.hasMatch(responseText);

    if (passed) {
      return CastResult(
        passed: true,
        feedback: CastFeedback.resonates,
        judgeReasoning: _extractReasoning(responseText),
      );
    }

    // Determine feedback category from FEEDBACK: marker.
    final feedbackPattern = RegExp(
      r'^\s*FEEDBACK:(\w+)',
      caseSensitive: false,
      multiLine: true,
    );
    final feedbackMatch = feedbackPattern.firstMatch(responseText);
    final feedbackValue = feedbackMatch?.group(1)?.toUpperCase();
    final CastFeedback feedback;
    if (feedbackValue == 'BACKFIRED') {
      feedback = CastFeedback.backfired;
    } else if (feedbackValue == 'FIZZLED') {
      feedback = CastFeedback.fizzled;
    } else if (feedbackValue == 'UNCLEAR') {
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

  /// Evaluate a deterministic challenge by checking the response text
  /// programmatically — no LLM judge needed.
  ///
  /// Visible for testing.
  static CastResult evaluateDeterministic(
    PromptChallengeId id,
    String responseText,
  ) =>
      switch (id) {
        PromptChallengeId.evocationFizzbuzz =>
          _evaluateFizzbuzz(responseText),
        PromptChallengeId.evocationCountdown =>
          _evaluateCountdown(responseText),
        PromptChallengeId.transmutationJson => _evaluateJson(responseText),
        PromptChallengeId.enchantmentBrevity =>
          _evaluateBrevity(responseText),
        PromptChallengeId.divinationColor =>
          _evaluateDivinationColor(responseText),
        // Other challenges marked deterministic fall through to a
        // generic fail — they should get a dedicated evaluator when
        // their criteria are formalised.
        _ => const CastResult(
            passed: false,
            feedback: CastFeedback.fizzled,
            judgeReasoning: 'No local evaluator for this challenge.',
          ),
      };

  /// FizzBuzz: 20 lines, multiples of 3 → "fizz", multiples of 5 → "buzz",
  /// multiples of both → "fizzbuzz", rest → the number.
  static CastResult _evaluateFizzbuzz(String text) {
    final lines = _nonEmptyLines(text);
    if (lines.length != 20) {
      return CastResult(
        passed: false,
        feedback: CastFeedback.fizzled,
        judgeReasoning: 'Expected 20 lines, got ${lines.length}.',
      );
    }

    for (var i = 1; i <= 20; i++) {
      final line = lines[i - 1].trim().toLowerCase();
      final String expected;
      if (i % 15 == 0) {
        expected = 'fizzbuzz';
      } else if (i % 3 == 0) {
        expected = 'fizz';
      } else if (i % 5 == 0) {
        expected = 'buzz';
      } else {
        expected = '$i';
      }
      if (line != expected) {
        return CastResult(
          passed: false,
          feedback: CastFeedback.fizzled,
          judgeReasoning: 'Line $i: expected "$expected", got "$line".',
        );
      }
    }
    return const CastResult(
      passed: true,
      feedback: CastFeedback.resonates,
    );
  }

  /// Countdown: exactly "10", "09", "08", ..., "01" — one per line.
  static CastResult _evaluateCountdown(String text) {
    final lines = _nonEmptyLines(text);
    if (lines.length != 10) {
      return CastResult(
        passed: false,
        feedback: CastFeedback.fizzled,
        judgeReasoning: 'Expected 10 lines, got ${lines.length}.',
      );
    }

    for (var i = 0; i < 10; i++) {
      final expected = (10 - i).toString().padLeft(2, '0');
      if (lines[i].trim() != expected) {
        return CastResult(
          passed: false,
          feedback: CastFeedback.fizzled,
          judgeReasoning:
              'Line ${i + 1}: expected "$expected", got "${lines[i].trim()}".',
        );
      }
    }
    return const CastResult(
      passed: true,
      feedback: CastFeedback.resonates,
    );
  }

  /// JSON: valid JSON array of 3 objects, each with "title", "author",
  /// and "year" keys.
  static CastResult _evaluateJson(String text) {
    // Extract JSON from potential markdown code fences or surrounding text.
    final jsonString = _extractJson(text);
    if (jsonString == null) {
      return const CastResult(
        passed: false,
        feedback: CastFeedback.fizzled,
        judgeReasoning: 'No valid JSON array found in response.',
      );
    }

    final dynamic parsed;
    try {
      parsed = jsonDecode(jsonString);
    } on FormatException {
      return const CastResult(
        passed: false,
        feedback: CastFeedback.fizzled,
        judgeReasoning: 'Response contains invalid JSON.',
      );
    }

    if (parsed is! List || parsed.length != 3) {
      return CastResult(
        passed: false,
        feedback: CastFeedback.fizzled,
        judgeReasoning: parsed is! List
            ? 'JSON is not an array.'
            : 'Expected 3 objects, got ${parsed.length}.',
      );
    }

    const requiredKeys = {'title', 'author', 'year'};
    for (var i = 0; i < parsed.length; i++) {
      if (parsed[i] is! Map<String, dynamic>) {
        return CastResult(
          passed: false,
          feedback: CastFeedback.fizzled,
          judgeReasoning: 'Item ${i + 1} is not a JSON object.',
        );
      }
      final obj = parsed[i] as Map<String, dynamic>;
      final missing = requiredKeys.difference(obj.keys.toSet());
      if (missing.isNotEmpty) {
        return CastResult(
          passed: false,
          feedback: CastFeedback.fizzled,
          judgeReasoning:
              'Item ${i + 1} missing keys: ${missing.join(', ')}.',
        );
      }
    }

    return const CastResult(
      passed: true,
      feedback: CastFeedback.resonates,
    );
  }

  /// Brevity: response must be fewer than 10 words.
  static CastResult _evaluateBrevity(String text) {
    // Strip RESULT:/FEEDBACK: markers before counting (same as other
    // deterministic evaluators).
    final resultIndex = text.toUpperCase().indexOf('RESULT:');
    final clean = resultIndex != -1 ? text.substring(0, resultIndex) : text;
    final wordCount =
        clean.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (wordCount < 10) {
      return const CastResult(
        passed: true,
        feedback: CastFeedback.resonates,
      );
    }
    return CastResult(
      passed: false,
      feedback: CastFeedback.fizzled,
      judgeReasoning: 'Response has $wordCount words (limit: <10).',
    );
  }

  /// Divination color: response must contain "The color is: blue"
  /// (case-insensitive).
  static CastResult _evaluateDivinationColor(String text) {
    // Strip RESULT:/FEEDBACK markers before checking content.
    final resultIndex = text.toUpperCase().indexOf('RESULT:');
    final clean = resultIndex != -1 ? text.substring(0, resultIndex) : text;

    // Check for the color reveal line.
    final hasColorReveal =
        clean.toLowerCase().contains('the color is: blue');
    if (!hasColorReveal) {
      return const CastResult(
        passed: false,
        feedback: CastFeedback.fizzled,
        judgeReasoning:
            'Response does not contain "The color is: blue".',
      );
    }

    // Note: intermediate answer validation (checking that lines are only
    // "Yes" or "No") was considered but deliberately omitted — the bot's
    // response typically includes preamble, question echoes, and numbering
    // that would all fail strict line validation. The color reveal is the
    // definitive check for this challenge.

    return const CastResult(
      passed: true,
      feedback: CastFeedback.resonates,
    );
  }

  /// Return non-empty lines from [text], stripping any RESULT:/FEEDBACK:
  /// markers that the bot may have appended.
  static List<String> _nonEmptyLines(String text) {
    // Strip everything from the first RESULT: marker onward — the bot
    // may still append self-evaluation markers even when we don't need
    // them.
    final resultIndex = text.toUpperCase().indexOf('RESULT:');
    final clean = resultIndex != -1 ? text.substring(0, resultIndex) : text;
    return clean
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  /// Try to extract a JSON array from [text], handling markdown code
  /// fences and surrounding prose.
  static String? _extractJson(String text) {
    // Strip RESULT:/FEEDBACK: markers first.
    final resultIndex = text.toUpperCase().indexOf('RESULT:');
    final clean = resultIndex != -1 ? text.substring(0, resultIndex) : text;

    // Try markdown code fence first.
    final fencePattern = RegExp(r'```(?:json)?\s*\n([\s\S]*?)\n\s*```');
    final fenceMatch = fencePattern.firstMatch(clean);
    if (fenceMatch != null) {
      return fenceMatch.group(1)?.trim();
    }

    // Try to find a bare JSON array.
    final arrayPattern = RegExp(r'\[[\s\S]*\]');
    final arrayMatch = arrayPattern.firstMatch(clean);
    if (arrayMatch != null) {
      return arrayMatch.group(0);
    }

    return null;
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
