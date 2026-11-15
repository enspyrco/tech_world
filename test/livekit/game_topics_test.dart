import 'dart:convert';

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/avatar/avatar_spec.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/emote.dart';
import 'package:tech_world/flame/shared/player_path.dart';
import 'package:tech_world/livekit/data_channel.dart';
import 'package:tech_world/livekit/game_topics.dart';
import 'package:tech_world/livekit/livekit_topic.dart';

Map<String, dynamic> _wire(List<int> bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

DataChannelMessage _msg(String topic, Object payload, {String? sender}) =>
    DataChannelMessage(
      senderId: sender,
      topic: topic,
      data: payload is List<int> ? payload : utf8.encode(jsonEncode(payload)),
    );

void main() {
  final at = DateTime.utc(2026, 11, 15, 8, 30);

  // Pins every encoder's payload. Each expectation is the map the pre-codec
  // publish method built (read from livekit_service.dart at be7e4619), so a
  // codec change can't quietly alter what the bot and other clients receive.
  group('wire format', () {
    test('position: stamped, unreliable', () {
      final bytes = positionTopic.encode(PlayerPath(
        playerId: 'p1',
        largeGridPoints: [Vector2(1, 2)],
        directions: [Direction.up],
      ));
      expect(_wire(bytes), {
        'v': kProtocolVersion,
        'playerId': 'p1',
        'points': [
          {'x': 1.0, 'y': 2.0}
        ],
        'directions': ['up'],
      });
      expect(positionTopic.reliable, isFalse);
    });

    test('heartbeat', () {
      expect(
        _wire(positionHeartbeatTopic
            .encode(const PositionHeartbeat(playerId: 'p1', x: 3, y: 4))),
        {'v': 1, 'playerId': 'p1', 'x': 3, 'y': 4, 'type': 'heartbeat'},
      );
      expect(positionHeartbeatTopic.reliable, isTrue);
    });

    test('map switch', () {
      expect(_wire(mapSwitchTopic.encode((senderId: 'p1', mapId: 'm1'))),
          {'v': 1, 'senderId': 'p1', 'mapId': 'm1'});
    });

    test('avatar', () {
      const spec = AvatarSpec.fallback;
      expect(
        _wire(avatarTopic.encode(const AvatarUpdate(playerId: 'p1', spec: spec))),
        {'v': 1, 'playerId': 'p1', ...spec.toWire()},
      );
    });

    test('emote: kind only, unreliable', () {
      expect(_wire(emoteTopic.encode(EmoteId.wave)), {'v': 1, 'kind': 'wave'});
      expect(emoteTopic.reliable, isFalse);
    });

    test('mention ack', () {
      expect(_wire(mentionAckTopic.encode((messageId: 'm1', at: at))), {
        'v': 1,
        'type': 'mention-ack',
        'messageId': 'm1',
        'timestamp': at.toIso8601String(),
      });
    });

    test('df proximity', () {
      expect(_wire(dfProximityTopic.encode((playerId: 'p1', near: true))),
          {'v': 1, 'playerId': 'p1', 'near': true});
    });

    test('terminal activity omits absent optional fields', () {
      final base = (
        action: 'open',
        playerId: 'p1',
        playerName: 'Pat',
        at: at,
        challengeId: null,
        challengeTitle: null,
        challengeDescription: null,
        terminalX: null,
        terminalY: null,
      );
      expect(_wire(terminalActivityTopic.encode(base)), {
        'v': 1,
        'type': 'terminal-activity',
        'action': 'open',
        'playerId': 'p1',
        'playerName': 'Pat',
        'timestamp': at.toIso8601String(),
      });
      final full = (
        action: 'open',
        playerId: 'p1',
        playerName: 'Pat',
        at: at,
        challengeId: 'c1',
        challengeTitle: 't',
        challengeDescription: 'd',
        terminalX: 5,
        terminalY: 6,
      );
      expect(_wire(terminalActivityTopic.encode(full)), {
        'v': 1,
        'type': 'terminal-activity',
        'action': 'open',
        'playerId': 'p1',
        'playerName': 'Pat',
        'timestamp': at.toIso8601String(),
        'challengeId': 'c1',
        'challengeTitle': 't',
        'challengeDescription': 'd',
        'terminalX': 5,
        'terminalY': 6,
      });
    });

    test('agent hello is NOT version-stamped', () {
      final payload = <String, Object?>{'sdk': '2.7.0', 'adaptiveStream': false};
      expect(_wire(agentHelloTopic.encode(payload)), payload);
    });

    test('each topic uses its LiveKitTopic wire name', () {
      expect(positionTopic.wireName, LiveKitTopic.position.wire);
      expect(positionHeartbeatTopic.wireName,
          LiveKitTopic.positionHeartbeat.wire);
      expect(mapInfoRequestTopic.wireName, LiveKitTopic.mapInfoRequest.wire);
      expect(mapSwitchTopic.wireName, LiveKitTopic.mapSwitch.wire);
      expect(avatarTopic.wireName, LiveKitTopic.avatar.wire);
      expect(emoteTopic.wireName, LiveKitTopic.emote.wire);
      expect(mentionAckTopic.wireName, LiveKitTopic.mentionAck.wire);
      expect(roomTimerTopic.wireName, LiveKitTopic.roomTimer.wire);
      expect(mapInfoTopic.wireName, LiveKitTopic.mapInfo.wire);
      expect(dfProximityTopic.wireName, LiveKitTopic.dfProximity.wire);
      expect(terminalActivityTopic.wireName,
          LiveKitTopic.terminalActivity.wire);
      expect(agentHelloTopic.wireName, LiveKitTopic.agentHello.wire);
    });
  });

  group('sender attribution', () {
    test('emote takes the TRANSPORT sender, ignoring payload claims', () {
      final e = emoteTopic.decode(_msg(
        'emote',
        {'kind': 'wave', 'senderId': 'forged', 'playerId': 'forged'},
        sender: 'real',
      ));
      expect(e, (senderId: 'real', emote: EmoteId.wave));
    });

    test('emote without a transport sender is dropped', () {
      expect(emoteTopic.decode(_msg('emote', {'kind': 'wave'})), isNull);
    });

    test('unknown emote kind is dropped, not defaulted', () {
      expect(
          emoteTopic.decode(_msg('emote', {'kind': 'moonwalk'}, sender: 'p1')),
          isNull);
    });

    test('mention ack takes the TRANSPORT sender, ignoring payload claims', () {
      final ack = mentionAckTopic.decode(_msg(
        'mention-ack',
        {'messageId': 'm1', 'ackerId': 'forged'},
        sender: 'real',
      ));
      expect(ack, (ackerId: 'real', messageId: 'm1'));
    });

    test('mention ack without a transport sender keeps the legacy "unknown"',
        () {
      expect(mentionAckTopic.decode(_msg('mention-ack', {'messageId': 'm1'})),
          (ackerId: 'unknown', messageId: 'm1'));
    });
  });

  group('decoding', () {
    test('position clamps hostile coordinates', () {
      final path = positionTopic.decode(_msg('position', {
        'playerId': 'p1',
        'points': [
          {'x': 1e12, 'y': -1e12}
        ],
        'directions': ['up'],
      }))!;
      expect(path.largeGridPoints.single.x, lessThan(1e12));
      expect(path.largeGridPoints.single.y, greaterThan(-1e12));
    });

    test('map switch needs both fields', () {
      expect(mapSwitchTopic.decode(_msg('map-switch', {'mapId': 'm1'})), isNull);
    });

    test('map info request fires on any payload, even non-JSON', () {
      expect(
        mapInfoRequestTopic.decode(_msg('map-info-request', <int>[0xff, 0x00])),
        isA<MapInfoRequest>(),
      );
    });

    test('a non-JSON payload is dropped by JSON topics', () {
      expect(avatarTopic.decode(_msg('avatar', <int>[0xff, 0x00])), isNull);
    });
  });

  group('decodeTopic', () {
    test('only passes messages on its own topic', () async {
      final source = Stream.fromIterable([
        _msg('emote', {'kind': 'wave'}, sender: 'a'),
        _msg('chat', {'kind': 'wave'}, sender: 'b'),
      ]);
      expect(await decodeTopic(source, emoteTopic).toList(),
          [(senderId: 'a', emote: EmoteId.wave)]);
    });

    test('a throwing decoder drops that message and keeps the stream alive',
        () async {
      final errors = <Object>[];
      final source = Stream.fromIterable([
        _msg('t', {'n': 1}),
        _msg('t', {'boom': true}),
        _msg('t', {'n': 2}),
      ]);
      final out = await decodeTopic(
        source,
        const _ThrowsOnBoom(),
        onError: (e, _) => errors.add(e),
      ).toList();
      expect(out, [1, 2]);
      expect(errors, hasLength(1));
    });
  });
}

final class _ThrowsOnBoom implements TopicDecoder<int> {
  const _ThrowsOnBoom();

  @override
  String get wireName => 't';

  @override
  int? decode(DataChannelMessage m) {
    final json = m.json!;
    if (json['boom'] == true) throw StateError('boom');
    return json['n'] as int;
  }
}
