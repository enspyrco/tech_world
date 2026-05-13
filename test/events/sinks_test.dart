import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/sinks/console_sink.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

void main() {
  tearDown(clearSinks);

  group('consoleSink', () {
    late List<String> logs;
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      logs = [];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
    });

    test('prints WordLearned with word and challenge', () {
      consoleSink(WordLearned(
        wordId: WordId.ignis,
        challengeId: PromptChallengeId.evocationFizzbuzz,
      ));

      expect(logs, hasLength(1));
      expect(logs[0], contains('WordLearned'));
      expect(logs[0], contains('ignis'));
      expect(logs[0], contains('evocation_fizzbuzz'));
    });

    test('prints ChallengeCompleted with challengeId', () {
      consoleSink(ChallengeCompleted(challengeId: PromptRef(PromptChallengeId.divinationColor)));

      expect(logs, hasLength(1));
      expect(logs[0], contains('ChallengeCompleted'));
      expect(logs[0], contains('divination_color'));
    });

    test('prints DoorUnlocked with coordinates', () {
      consoleSink(DoorUnlocked(doorX: 12, doorY: 8));

      expect(logs, hasLength(1));
      expect(logs[0], contains('DoorUnlocked'));
      expect(logs[0], contains('12'));
      expect(logs[0], contains('8'));
    });

    test('prints BotSpoke with truncated text', () {
      consoleSink(BotSpoke(
        text: 'A' * 100,
        context: BotSpokeContext.group,
      ));

      expect(logs, hasLength(1));
      expect(logs[0], contains('BotSpoke'));
      expect(logs[0], contains('[group]'));
      expect(logs[0], contains('...'));
    });

    test('short BotSpoke text is not truncated', () {
      consoleSink(BotSpoke(
        text: 'Hello wizard',
        context: BotSpokeContext.help,
      ));

      expect(logs, hasLength(1));
      expect(logs[0], contains('Hello wizard'));
      expect(logs[0].contains('...'), isFalse);
    });

    test('works as registered sink via dispatch', () {
      registerSink(consoleSink);
      dispatch([DoorUnlocked(doorX: 5, doorY: 10)]);

      expect(logs, hasLength(1));
      expect(logs[0], contains('DoorUnlocked'));
    });
  });

  group('AppEvent.toJson', () {
    test('WordLearned serializes correctly', () {
      final event = WordLearned(
        wordId: WordId.ignis,
        challengeId: PromptChallengeId.evocationFizzbuzz,
        timestamp: DateTime(2026, 5, 8, 12, 0),
      );
      final json = event.toJson();

      expect(json['type'], 'word_learned');
      expect(json['wordId'], 'ignis');
      expect(json['challengeId'], 'evocation_fizzbuzz');
      expect(json['timestamp'], '2026-05-08T12:00:00.000');
    });

    test('ChallengeCompleted serializes correctly', () {
      final json = ChallengeCompleted(
        challengeId: PromptRef(PromptChallengeId.divinationColor),
        timestamp: DateTime(2026, 5, 8),
      ).toJson();

      expect(json['type'], 'challenge_completed');
      expect(json['challengeId'], 'divination_color');
    });

    test('DoorUnlocked serializes correctly', () {
      final json = DoorUnlocked(doorX: 12, doorY: 8).toJson();

      expect(json['type'], 'door_unlocked');
      expect(json['doorX'], 12);
      expect(json['doorY'], 8);
    });

    test('BotSpoke serializes correctly', () {
      final json = BotSpoke(
        text: 'The aether listens',
        context: BotSpokeContext.help,
      ).toJson();

      expect(json['type'], 'bot_spoke');
      expect(json['text'], 'The aether listens');
      expect(json['context'], 'help');
    });
  });
}
