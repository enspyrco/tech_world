import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/bots/bot_config.dart';

/// Tests for the sender-identity helpers used by the door-unlock guard in
/// [TechWorld._handleRemoteDoorUnlock].
///
/// The guard rejects door-unlock messages whose [DataChannelMessage.senderId]
/// is null, belongs to a bot, or is not a known room participant. These tests
/// verify that [isBotIdentity] classifies senders correctly so the guard
/// behaves as expected.
void main() {
  group('isBotIdentity', () {
    test('returns true for the Clawd bot', () {
      expect(isBotIdentity('bot-claude'), isTrue);
    });

    test('returns true for the Gremlin bot', () {
      expect(isBotIdentity('bot-gremlin'), isTrue);
    });

    test('returns true for the Dreamfinder bot', () {
      expect(isBotIdentity('bot-dreamfinder'), isTrue);
    });

    test('returns true for agent- prefixed LiveKit agents identities', () {
      expect(isBotIdentity('agent-abc123'), isTrue);
      expect(isBotIdentity('agent-'), isTrue);
    });

    test('returns false for a regular human participant identity', () {
      expect(isBotIdentity('firebase-uid-abc123'), isFalse);
    });

    test('returns false for an empty string', () {
      expect(isBotIdentity(''), isFalse);
    });

    test('returns false for a string that contains bot name but is not a bot',
        () {
      // Ensure prefix-match only applies to 'agent-', not arbitrary strings.
      expect(isBotIdentity('not-bot-claude'), isFalse);
      expect(isBotIdentity('xbot-claude'), isFalse);
    });

    test(
        'door-unlock sender guard: bot identities must be rejected, '
        'human identities must be accepted', () {
      // Regression: any participant could previously broadcast door-unlock and
      // unlock doors for everyone without completing the required challenge.
      // The guard now rejects null senders, bots, and unknown participants.
      // Here we verify the bot-classification half of that guard.
      const botIdentities = ['bot-claude', 'bot-gremlin', 'bot-dreamfinder'];
      for (final id in botIdentities) {
        expect(
          isBotIdentity(id),
          isTrue,
          reason: '$id should be rejected by the door-unlock sender guard',
        );
      }

      const humanIdentities = [
        'firebase-uid-abc',
        'user-12345',
        'google-oauth-uid',
      ];
      for (final id in humanIdentities) {
        expect(
          isBotIdentity(id),
          isFalse,
          reason: '$id should pass the bot-identity check in the guard',
        );
      }
    });
  });

  group('getBotConfig', () {
    test('returns clawdBot for bot-claude', () {
      expect(getBotConfig('bot-claude'), equals(clawdBot));
    });

    test('returns gremlinBot for bot-gremlin', () {
      expect(getBotConfig('bot-gremlin'), equals(gremlinBot));
    });

    test('returns dreamfinderBot for bot-dreamfinder', () {
      expect(getBotConfig('bot-dreamfinder'), equals(dreamfinderBot));
    });

    test('maps agent- prefixed identities to dreamfinderBot', () {
      expect(getBotConfig('agent-xyz'), equals(dreamfinderBot));
    });

    test('returns clawdBot as fallback for unknown identities', () {
      expect(getBotConfig('unknown-identity'), equals(clawdBot));
    });
  });

  group('isDreamfinderIdentity', () {
    test('returns true for bot-dreamfinder', () {
      expect(isDreamfinderIdentity('bot-dreamfinder'), isTrue);
    });

    test('returns true for agent- prefixed identities', () {
      expect(isDreamfinderIdentity('agent-12345'), isTrue);
    });

    test('returns false for bot-claude', () {
      expect(isDreamfinderIdentity('bot-claude'), isFalse);
    });

    test('returns false for bot-gremlin', () {
      expect(isDreamfinderIdentity('bot-gremlin'), isFalse);
    });

    test('returns false for human identities', () {
      expect(isDreamfinderIdentity('human-uid-abc'), isFalse);
    });
  });
}
