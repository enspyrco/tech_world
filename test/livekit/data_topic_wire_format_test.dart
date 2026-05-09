import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/data_topic.dart';

/// Pin every [DataTopic] enum value to its exact wire string.
///
/// **Why this test exists:** when both producer and consumer share the same
/// enum, a typo in [DataTopic.wireName] passes round-trip tests on both
/// sides — the publisher sends the wrong value and the matching consumer
/// reads the wrong value, but they still see each other. External clients
/// (the bot worker, written in TypeScript with hard-coded literals like
/// `'chat-response'`) silently stop seeing messages.
///
/// This fixture is the bridge between "internally consistent enum" (which
/// the round-trip test gives us) and "matches the protocol the external
/// bots expect" (what we actually need at the wire boundary).
///
/// **Maintenance:** if a wire string changes here, that's a wire-format
/// version bump — it must be coordinated with all external consumers
/// (tech_world_bot at `/Users/nick/git/orgs/enspyrco/adventures-in/tech_world_bot`).
void main() {
  group('DataTopic wire-format fixture', () {
    test('every enum value maps to its exact wire string', () {
      const expected = <DataTopic, String>{
        DataTopic.position: 'position',
        DataTopic.positionHeartbeat: 'position-heartbeat',
        DataTopic.avatar: 'avatar',
        DataTopic.chat: 'chat',
        DataTopic.chatResponse: 'chat-response',
        DataTopic.dm: 'dm',
        DataTopic.dmResponse: 'dm-response',
        DataTopic.helpRequest: 'help-request',
        DataTopic.helpResponse: 'help-response',
        DataTopic.mapInfo: 'map-info',
        DataTopic.mapInfoRequest: 'map-info-request',
        DataTopic.mapSwitch: 'map-switch',
        DataTopic.mapEdit: 'map-edit',
        DataTopic.mapEditSync: 'map-edit-sync',
        DataTopic.terminalActivity: 'terminal-activity',
        DataTopic.doorUnlock: 'door-unlock',
        DataTopic.speechTranscript: 'speech-transcript',
        DataTopic.ping: 'ping',
        DataTopic.pong: 'pong',
        DataTopic.infraHealth: 'infra-health',
        DataTopic.infraHeal: 'infra-heal',
        DataTopic.infraHealResult: 'infra-heal-result',
        DataTopic.infraBoot: 'infra-boot',
        DataTopic.oracleRequest: 'oracle-request',
        DataTopic.oracleResponse: 'oracle-response',
        DataTopic.dreamfinderAudio: 'dreamfinder-audio',
        DataTopic.dreamfinderMood: 'dreamfinder-mood',
      };

      // Every enum value is in the fixture (catches a new enum value being
      // added without a corresponding wire-string pin).
      expect(expected.keys.toSet(), equals(DataTopic.values.toSet()),
          reason:
              'Fixture must enumerate every DataTopic value. If a new value '
              'was added, also add its expected wire string here.');

      // Every value's wireName matches the pinned literal.
      for (final entry in expected.entries) {
        expect(entry.key.wireName, equals(entry.value),
            reason:
                '${entry.key} wireName diverged from its pinned wire string. '
                'A change here is a protocol-version bump; coordinate with '
                'tech_world_bot before merging.');
      }
    });

    test('every wire string is unique', () {
      final wireNames = DataTopic.values.map((t) => t.wireName).toList();
      final uniqueWireNames = wireNames.toSet();
      expect(uniqueWireNames.length, equals(wireNames.length),
          reason: 'Two DataTopic values share the same wireName — '
              'producers/consumers cannot disambiguate. Wire names must be '
              'globally unique across the enum.');
    });
  });
}
