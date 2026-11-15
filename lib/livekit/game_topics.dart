import 'package:flame/components.dart' show Vector2;
import 'package:logging/logging.dart';
import 'package:tech_world/avatar/avatar_spec.dart';
import 'package:tech_world/chat/chat_message.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/emote.dart';
import 'package:tech_world/flame/shared/player_path.dart';
import 'package:tech_world/livekit/agent_hello.dart';
import 'package:tech_world/livekit/data_channel.dart';
import 'package:tech_world/livekit/livekit_topic.dart';
import 'package:tech_world/timer/room_timer_message.dart';

final _log = Logger('GameTopics');

/// A parsed avatar update from the `avatar` data channel topic.
class AvatarUpdate {
  const AvatarUpdate({required this.playerId, required this.spec});

  final String playerId;

  /// What to render. Always valid — see [AvatarSpec.parse].
  final AvatarSpec spec;

  /// Try to parse an [AvatarUpdate]. Returns null **only** when the message
  /// can't be attributed to a player.
  ///
  /// The split matters: [AvatarSpec.parse] is total, because a malformed
  /// appearance should render as the default rather than kill the stream. But
  /// an update with no usable `playerId` isn't a bad avatar — it's a message
  /// about nobody, and applying it would mean picking a victim. So attribution
  /// failure drops the whole message, and everything else falls back to a
  /// bundled asset.
  ///
  /// This replaced a `spriteAsset` whitelist. The whitelist was doing real
  /// work — it stopped path traversal and cache-miss crashes reaching the
  /// renderer — and closed enums do the same job structurally: a peer can only
  /// name ids that exist in our own enums, and an unknown one degrades or
  /// falls back. No filename ever crosses the wire now.
  static AvatarUpdate? tryParse(Map<String, dynamic>? json) {
    if (json case {'playerId': String playerId} when playerId.isNotEmpty) {
      return AvatarUpdate(playerId: playerId, spec: AvatarSpec.parse(json));
    }
    return null;
  }
}

/// A reliable position heartbeat from another participant.
///
/// Carries a single grid position with reliable delivery to correct stale
/// positions caused by dropped unreliable path updates.
class PositionHeartbeat {
  const PositionHeartbeat({
    required this.playerId,
    required this.x,
    required this.y,
  });

  final String playerId;
  final int x;
  final int y;

  /// Try to parse a [PositionHeartbeat] from a JSON map. Returns null if
  /// required fields are missing or have wrong types.
  ///
  /// Uses `is` checks rather than `as` casts so a malformed packet from
  /// any participant returns null rather than throwing.
  static PositionHeartbeat? tryParse(Map<String, dynamic>? json) {
    if (json == null) return null;
    final playerId = json['playerId'];
    final x = json['x'];
    final y = json['y'];
    if (playerId is! String || x is! int || y is! int) return null;
    // 2× grid bounds: negative coords valid for off-origin maps. Units: grid cells.
    const maxCoord = gridSize * 2;
    return PositionHeartbeat(
      playerId: playerId,
      x: x.clamp(-maxCoord, maxCoord),
      y: y.clamp(-maxCoord, maxCoord),
    );
  }
}

/// A bot asking the client to (re)send the current map. Carries nothing.
final class MapInfoRequest {
  const MapInfoRequest();
}

/// A map switch. [senderId] is self-reported in the payload, not
/// transport-verified.
typedef MapSwitch = ({String senderId, String mapId});

/// An emote, attributed to the transport-verified sender.
typedef RemoteEmote = ({String senderId, EmoteId emote});

/// A mention acknowledgement, attributed to the transport sender.
typedef MentionAck = ({String ackerId, String messageId});

/// The local player's own acknowledgement of a mention.
typedef OutgoingMentionAck = ({String messageId, DateTime at});

/// The local player entering or leaving Dreamfinder's range.
typedef DfProximity = ({String playerId, bool near});

/// The local player opening or closing the code editor.
typedef TerminalActivity = ({
  String action,
  String playerId,
  String playerName,
  DateTime at,
  String? challengeId,
  String? challengeTitle,
  String? challengeDescription,
  int? terminalX,
  int? terminalY,
});

final class PositionTopic
    with JsonEncoding<PlayerPath>, JsonDecoding<PlayerPath>
    implements TopicCodec<PlayerPath> {
  const PositionTopic();

  @override
  String get wireName => LiveKitTopic.position.wire;

  /// Positions update often; a dropped one is corrected by the next.
  @override
  bool get reliable => false;

  @override
  Map<String, dynamic> toJson(PlayerPath path) => {
        'playerId': path.playerId,
        'points': path.largeGridPoints.map((p) => {'x': p.x, 'y': p.y}).toList(),
        'directions': path.directions.map((d) => d.name).toList(),
      };

  @override
  PlayerPath? fromJson(Map<String, dynamic> json, DataChannelMessage message) {
    try {
      final playerId = json['playerId'] as String?;
      final pointsJson = json['points'] as List<dynamic>?;
      final directionsJson = json['directions'] as List<dynamic>?;

      if (playerId == null || pointsJson == null || directionsJson == null) {
        return null;
      }

      // Clamp at parse boundary — a malformed or hostile peer could
      // otherwise push huge coordinates into Flame movement/rendering.
      // 2× world bounds: path interpolation can briefly overshoot.
      // Units: world-space pixels.
      final maxCoord = (gridSize * gridSquareSize * 2).toDouble();
      final points = pointsJson
          .map((p) => Vector2(
                (p['x'] as num).toDouble().clamp(-maxCoord, maxCoord),
                (p['y'] as num).toDouble().clamp(-maxCoord, maxCoord),
              ))
          .toList();

      final directions = directionsJson
          .map((d) => Direction.values.asNameMap()[d] ?? Direction.none)
          .toList();

      return PlayerPath(
        playerId: playerId,
        largeGridPoints: points,
        directions: directions,
      );
    } catch (e) {
      _log.warning('Failed to parse player path', e);
      return null;
    }
  }
}

final class PositionHeartbeatTopic
    with JsonEncoding<PositionHeartbeat>, JsonDecoding<PositionHeartbeat>
    implements TopicCodec<PositionHeartbeat> {
  const PositionHeartbeatTopic();

  @override
  String get wireName => LiveKitTopic.positionHeartbeat.wire;

  @override
  bool get reliable => true;

  @override
  Map<String, dynamic> toJson(PositionHeartbeat hb) => {
        'playerId': hb.playerId,
        'x': hb.x,
        'y': hb.y,
        'type': 'heartbeat',
      };

  @override
  PositionHeartbeat? fromJson(
          Map<String, dynamic> json, DataChannelMessage message) =>
      PositionHeartbeat.tryParse(json);
}

/// Sent by bots; the client only receives it, and any message on the topic
/// counts, whatever its payload.
final class MapInfoRequestTopic implements TopicDecoder<MapInfoRequest> {
  const MapInfoRequestTopic();

  @override
  String get wireName => LiveKitTopic.mapInfoRequest.wire;

  @override
  MapInfoRequest decode(DataChannelMessage message) => const MapInfoRequest();
}

final class MapSwitchTopic
    with JsonEncoding<MapSwitch>, JsonDecoding<MapSwitch>
    implements TopicCodec<MapSwitch> {
  const MapSwitchTopic();

  @override
  String get wireName => LiveKitTopic.mapSwitch.wire;

  /// A missed switch leaves players on different worlds.
  @override
  bool get reliable => true;

  @override
  Map<String, dynamic> toJson(MapSwitch s) =>
      {'senderId': s.senderId, 'mapId': s.mapId};

  @override
  MapSwitch? fromJson(Map<String, dynamic> json, DataChannelMessage message) {
    if (json case {'senderId': String senderId, 'mapId': String mapId}) {
      return (senderId: senderId, mapId: mapId);
    }
    return null;
  }
}

final class AvatarTopic
    with JsonEncoding<AvatarUpdate>, JsonDecoding<AvatarUpdate>
    implements TopicCodec<AvatarUpdate> {
  const AvatarTopic();

  @override
  String get wireName => LiveKitTopic.avatar.wire;

  /// Reliable so late-joiners' catch-up works.
  @override
  bool get reliable => true;

  @override
  Map<String, dynamic> toJson(AvatarUpdate u) =>
      {'playerId': u.playerId, ...u.spec.toWire()};

  @override
  AvatarUpdate? fromJson(
          Map<String, dynamic> json, DataChannelMessage message) =>
      AvatarUpdate.tryParse(json);
}

/// Sends only the emote kind; the receiver attributes it to the transport
/// sender, so a peer can only ever wave its own avatar.
final class EmoteTopic
    with JsonEncoding<EmoteId>, JsonDecoding<RemoteEmote>
    implements TopicEncoder<EmoteId>, TopicDecoder<RemoteEmote> {
  const EmoteTopic();

  @override
  String get wireName => LiveKitTopic.emote.wire;

  /// A dropped flourish is better than one replayed after its moment.
  @override
  bool get reliable => false;

  @override
  Map<String, dynamic> toJson(EmoteId emote) => {'kind': emote.wireName};

  /// An unknown `kind` is dropped rather than defaulted: a future emote from a
  /// newer client must render as nothing, not as the wrong animation.
  @override
  RemoteEmote? fromJson(Map<String, dynamic> json, DataChannelMessage message) {
    final kind = json['kind'];
    if (kind is! String) return null;
    final emote = EmoteId.parse(kind);
    if (emote == null) return null;
    final senderId = message.senderId;
    if (senderId == null) return null;
    return (senderId: senderId, emote: emote);
  }
}

/// The acker is the transport sender, so a peer can only ack its own mention.
final class MentionAckTopic
    with JsonEncoding<OutgoingMentionAck>, JsonDecoding<MentionAck>
    implements TopicEncoder<OutgoingMentionAck>, TopicDecoder<MentionAck> {
  const MentionAckTopic();

  @override
  String get wireName => LiveKitTopic.mentionAck.wire;

  @override
  bool get reliable => true;

  @override
  Map<String, dynamic> toJson(OutgoingMentionAck ack) => {
        'type': LiveKitTopic.mentionAck.wire,
        'messageId': ack.messageId,
        'timestamp': ack.at.toIso8601String(),
      };

  @override
  MentionAck? fromJson(Map<String, dynamic> json, DataChannelMessage message) {
    final messageId = ChatMessage.asStringOrNull(json['messageId']);
    if (messageId == null) return null;
    return (ackerId: message.senderId ?? 'unknown', messageId: messageId);
  }
}

final class RoomTimerTopic
    with JsonEncoding<RoomTimerMessage>, JsonDecoding<RoomTimerMessage>
    implements TopicCodec<RoomTimerMessage> {
  const RoomTimerTopic();

  @override
  String get wireName => LiveKitTopic.roomTimer.wire;

  /// A missed start or cancel desyncs the timer across clients.
  @override
  bool get reliable => true;

  @override
  Map<String, dynamic> toJson(RoomTimerMessage m) => m.toJson();

  @override
  RoomTimerMessage? fromJson(
          Map<String, dynamic> json, DataChannelMessage message) =>
      RoomTimerMessage.tryParse(json);
}

/// Sent to the bot only; the client never receives map info.
final class MapInfoTopic
    with JsonEncoding<GameMap>
    implements TopicEncoder<GameMap> {
  const MapInfoTopic();

  @override
  String get wireName => LiveKitTopic.mapInfo.wire;

  @override
  bool get reliable => true;

  @override
  Map<String, dynamic> toJson(GameMap map) => {
        'mapId': map.id,
        'barriers': map.barriers.map((p) => [p.x, p.y]).toList(),
        'terminals': map.terminals.map((p) => [p.x, p.y]).toList(),
        'spawnPoint': [map.spawnPoint.x, map.spawnPoint.y],
        'gridSize': gridSize,
        'cellSize': gridSquareSize,
        // Dreamfinder's square, resolved to a concrete cell rect [minX,minY,maxX,
        // maxY]. Resolved once here so the bot's wander bound + audio gate read
        // the same box the client draws.
        'dreamfinderTerritory':
            map.resolveDreamfinderTerritory(gridSize).toWire(),
      };
}

/// Sent to the bot only.
final class DfProximityTopic
    with JsonEncoding<DfProximity>
    implements TopicEncoder<DfProximity> {
  const DfProximityTopic();

  @override
  String get wireName => LiveKitTopic.dfProximity.wire;

  /// A missed enter leaves DF deaf to a nearby player; a missed exit leaves him
  /// listening to someone who walked away.
  @override
  bool get reliable => true;

  @override
  Map<String, dynamic> toJson(DfProximity p) =>
      {'playerId': p.playerId, 'near': p.near};
}

/// Sent to the bot only.
final class TerminalActivityTopic
    with JsonEncoding<TerminalActivity>
    implements TopicEncoder<TerminalActivity> {
  const TerminalActivityTopic();

  @override
  String get wireName => LiveKitTopic.terminalActivity.wire;

  @override
  bool get reliable => true;

  @override
  Map<String, dynamic> toJson(TerminalActivity a) => {
        'type': 'terminal-activity',
        'action': a.action,
        'playerId': a.playerId,
        'playerName': a.playerName,
        'timestamp': a.at.toIso8601String(),
        if (a.challengeId != null) 'challengeId': a.challengeId,
        if (a.challengeTitle != null) 'challengeTitle': a.challengeTitle,
        if (a.challengeDescription != null)
          'challengeDescription': a.challengeDescription,
        if (a.terminalX != null) 'terminalX': a.terminalX,
        if (a.terminalY != null) 'terminalY': a.terminalY,
      };
}

/// Sent once on connect. Deliberately NOT version-stamped: it goes out as
/// [encodeAgentHelloPayload]'s bytes, unchanged.
final class AgentHelloTopic implements TopicEncoder<Map<String, Object?>> {
  const AgentHelloTopic();

  @override
  String get wireName => LiveKitTopic.agentHello.wire;

  @override
  bool get reliable => true;

  @override
  List<int> encode(Map<String, Object?> payload) =>
      encodeAgentHelloPayload(payload);
}

const positionTopic = PositionTopic();
const positionHeartbeatTopic = PositionHeartbeatTopic();
const mapInfoRequestTopic = MapInfoRequestTopic();
const mapSwitchTopic = MapSwitchTopic();
const avatarTopic = AvatarTopic();
const emoteTopic = EmoteTopic();
const mentionAckTopic = MentionAckTopic();
const roomTimerTopic = RoomTimerTopic();
const mapInfoTopic = MapInfoTopic();
const dfProximityTopic = DfProximityTopic();
const terminalActivityTopic = TerminalActivityTopic();
const agentHelloTopic = AgentHelloTopic();
