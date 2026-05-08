import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Return type for business functions that produce events alongside a result.
typedef WithEvents<T> = (T, List<AppEvent>);

/// Base type for all application events — sealed for exhaustive matching
/// in sinks.
///
/// Events are past tense (facts about what happened), immutable, and carry
/// only the data needed for sinks to act. The dispatch system fans each
/// event to all registered sinks; sinks filter by type via pattern matching.
sealed class AppEvent {
  DateTime get timestamp;

  /// Serialize to JSON for JSONL file sinks. Each subclass contributes
  /// its own fields; the `type` and `timestamp` are always present.
  Map<String, dynamic> toJson();
}

// ---------------------------------------------------------------------------
// Cast / spellbook events
// ---------------------------------------------------------------------------

/// A player earned a word of power by completing a prompt challenge.
final class WordLearned extends AppEvent {
  WordLearned({
    required this.wordId,
    required this.challengeId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final WordId wordId;
  final PromptChallengeId challengeId;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'word_learned',
        'wordId': wordId.name,
        'challengeId': challengeId.wireName,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// A player completed a challenge (code or prompt).
final class ChallengeCompleted extends AppEvent {
  ChallengeCompleted({
    required this.challengeId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Wire-format challenge ID (matches Firestore `completedChallenges` array).
  /// String because this is a union of CodeChallengeId and PromptChallengeId
  /// — both serialize to disjoint wire names in the same Firestore array.
  final String challengeId;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'challenge_completed',
        'challengeId': challengeId,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Reason a door-cast failed.
enum CastFailureReason { noMatch, notLearned, wrongDoor }

/// A voice-cast at a door failed.
///
/// Note: [transcript] contains STT output of what the user spoke.
/// Local-only — scrub before routing to any remote sink.
final class SpellCastFailed extends AppEvent {
  SpellCastFailed({
    required this.reason,
    this.transcript,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final CastFailureReason reason;
  final String? transcript;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'spell_cast_failed',
        'reason': reason.name,
        if (transcript != null) 'transcript': transcript,
        'timestamp': timestamp.toIso8601String(),
      };
}

// ---------------------------------------------------------------------------
// Game world events
// ---------------------------------------------------------------------------

/// A door was unlocked (all required challenges satisfied).
final class DoorUnlocked extends AppEvent {
  DoorUnlocked({
    required this.doorX,
    required this.doorY,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final int doorX;
  final int doorY;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'door_unlocked',
        'doorX': doorX,
        'doorY': doorY,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Player clicked to move to a destination.
final class PlayerMoved extends AppEvent {
  PlayerMoved({
    required this.destX,
    required this.destY,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final int destX;
  final int destY;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'player_moved',
        'destX': destX,
        'destY': destY,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Player opened a code or prompt terminal.
final class TerminalOpened extends AppEvent {
  TerminalOpened({
    required this.challengeId,
    required this.terminalX,
    required this.terminalY,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String challengeId;
  final int terminalX;
  final int terminalY;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'terminal_opened',
        'challengeId': challengeId,
        'terminalX': terminalX,
        'terminalY': terminalY,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Player closed the terminal editor.
final class TerminalClosed extends AppEvent {
  TerminalClosed({DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'terminal_closed',
        'timestamp': timestamp.toIso8601String(),
      };
}

// ---------------------------------------------------------------------------
// Room events
// ---------------------------------------------------------------------------

/// Player joined a room.
final class RoomJoined extends AppEvent {
  RoomJoined({
    required this.roomId,
    required this.roomName,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String roomId;
  final String roomName;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'room_joined',
        'roomId': roomId,
        'roomName': roomName,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Player left a room.
final class RoomLeft extends AppEvent {
  RoomLeft({this.roomId, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  final String? roomId;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'room_left',
        if (roomId != null) 'roomId': roomId,
        'timestamp': timestamp.toIso8601String(),
      };
}

// ---------------------------------------------------------------------------
// Auth events
// ---------------------------------------------------------------------------

/// User signed in.
final class UserSignedIn extends AppEvent {
  UserSignedIn({
    required this.userId,
    required this.displayName,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String userId;
  final String displayName;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'user_signed_in',
        'userId': userId,
        'displayName': displayName,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// User signed out.
final class UserSignedOut extends AppEvent {
  UserSignedOut({DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'user_signed_out',
        'timestamp': timestamp.toIso8601String(),
      };
}

/// User updated their profile (display name or picture).
final class ProfileUpdated extends AppEvent {
  ProfileUpdated({required this.displayName, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  final String displayName;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'profile_updated',
        'displayName': displayName,
        'timestamp': timestamp.toIso8601String(),
      };
}

// ---------------------------------------------------------------------------
// Map editor events
// ---------------------------------------------------------------------------

/// The kind of map edit operation performed.
enum MapEditAction {
  paintTile,
  paintWall,
  eraseWall,
  paintTerrain,
  eraseTerrain,
  paintTileRef,
  undo,
  redo,
}

/// Player edited the map via the CRDT editor.
final class MapEdited extends AppEvent {
  MapEdited({
    required this.action,
    required this.x,
    required this.y,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final MapEditAction action;
  final int x;
  final int y;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'map_edited',
        'action': action.name,
        'x': x,
        'y': y,
        'timestamp': timestamp.toIso8601String(),
      };
}

// ---------------------------------------------------------------------------
// Multiplayer events
// ---------------------------------------------------------------------------

/// Another player entered proximity range.
final class PlayerEnteredProximity extends AppEvent {
  PlayerEnteredProximity({required this.playerId, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  final String playerId;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'player_entered_proximity',
        'playerId': playerId,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Another player left proximity range.
final class PlayerLeftProximity extends AppEvent {
  PlayerLeftProximity({required this.playerId, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  final String playerId;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'player_left_proximity',
        'playerId': playerId,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// A bot joined the room.
final class BotJoined extends AppEvent {
  BotJoined({required this.identity, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  final String identity;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'bot_joined',
        'identity': identity,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// All bots left the room.
final class BotLeft extends AppEvent {
  BotLeft({DateTime? timestamp}) : timestamp = timestamp ?? DateTime.now();

  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'bot_left',
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Player toggled screen sharing.
final class ScreenShareToggled extends AppEvent {
  ScreenShareToggled({required this.started, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  final bool started;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'screen_share_toggled',
        'started': started,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Player selected an avatar.
final class AvatarSelected extends AppEvent {
  AvatarSelected({required this.avatarId, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  final String avatarId;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'avatar_selected',
        'avatarId': avatarId,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Player entered the map editor.
final class MapEditorEntered extends AppEvent {
  MapEditorEntered({required this.mapId, required this.mapName, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  final String mapId;
  final String mapName;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'map_editor_entered',
        'mapId': mapId,
        'mapName': mapName,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Player exited the map editor.
final class MapEditorExited extends AppEvent {
  MapEditorExited({required this.applied, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  /// Whether changes were applied (`true`) or discarded (`false`).
  final bool applied;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'map_editor_exited',
        'applied': applied,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// A room was created in Firestore.
final class RoomCreated extends AppEvent {
  RoomCreated({required this.roomId, required this.roomName, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  final String roomId;
  final String roomName;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'room_created',
        'roomId': roomId,
        'roomName': roomName,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// A room's map was saved to Firestore.
final class RoomMapSaved extends AppEvent {
  RoomMapSaved({required this.roomId, required this.roomName, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  final String roomId;
  final String roomName;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'room_map_saved',
        'roomId': roomId,
        'roomName': roomName,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// A room was deleted by its owner.
final class RoomDeleted extends AppEvent {
  RoomDeleted({required this.roomId, required this.roomName, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  final String roomId;
  final String roomName;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'room_deleted',
        'roomId': roomId,
        'roomName': roomName,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Outcome of a code submission evaluation.
enum CodeSubmitResult {
  pass,
  fail,
  timeout;

  /// Parse a bot response string into a typed result.
  /// Case-folds the wire value so `'PASS'` and `'Pass'` both match.
  static CodeSubmitResult fromWire(String? wire) =>
      switch (wire?.toString().toLowerCase()) {
        'pass' => CodeSubmitResult.pass,
        'fail' => CodeSubmitResult.fail,
        _ => CodeSubmitResult.timeout,
      };
}

/// Player submitted code for a challenge.
final class CodeSubmitted extends AppEvent {
  CodeSubmitted({
    required this.challengeId,
    required this.result,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String challengeId;
  final CodeSubmitResult result;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'code_submitted',
        'challengeId': challengeId,
        'result': result.name,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// LiveKit connected to a room.
final class LiveKitConnected extends AppEvent {
  LiveKitConnected({required this.roomName, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  final String roomName;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'livekit_connected',
        'roomName': roomName,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// LiveKit disconnected from a room.
final class LiveKitDisconnected extends AppEvent {
  LiveKitDisconnected({this.reason, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  final String? reason;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'livekit_disconnected',
        if (reason != null) 'reason': reason,
        'timestamp': timestamp.toIso8601String(),
      };
}

// ---------------------------------------------------------------------------
// Chat events
// ---------------------------------------------------------------------------

/// The bot produced speech (TTS was invoked or should be invoked).
final class BotSpoke extends AppEvent {
  BotSpoke({
    required this.text,
    required this.context,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String text;

  /// Where this speech originated: `group` for chat-response, `help` for
  /// help-response.
  final BotSpokeContext context;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'bot_spoke',
        'text': text,
        'context': context.name,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Player requested a hint from Clawd.
final class HelpRequested extends AppEvent {
  HelpRequested({required this.challengeId, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  final String challengeId;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'help_requested',
        'challengeId': challengeId,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Camera and microphone were enabled for the room.
final class MediaEnabled extends AppEvent {
  MediaEnabled({DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'media_enabled',
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Another player unlocked a door (received via LiveKit).
final class RemoteDoorUnlocked extends AppEvent {
  RemoteDoorUnlocked({
    required this.doorX,
    required this.doorY,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final int doorX;
  final int doorY;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'remote_door_unlocked',
        'doorX': doorX,
        'doorY': doorY,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Player sent a group chat message.
final class GroupMessageSent extends AppEvent {
  GroupMessageSent({
    required this.messageId,
    this.challengeId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String messageId;

  /// Non-null when this message is a challenge submission.
  final String? challengeId;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'group_message_sent',
        'messageId': messageId,
        if (challengeId != null) 'challengeId': challengeId,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Player sent a DM to another player.
///
/// Note: [peerId] and [conversationId] are written to the local JSONL log.
/// If this event is ever routed to a remote sink, scrub PII first.
final class DmSent extends AppEvent {
  DmSent({
    required this.peerId,
    required this.conversationId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String peerId;
  final String conversationId;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'dm_sent',
        'peerId': peerId,
        'conversationId': conversationId,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Discriminator for [BotSpoke] origin.
enum BotSpokeContext { group, help }

// ---------------------------------------------------------------------------
// Log bridge events
// ---------------------------------------------------------------------------

/// Severity levels for log records routed through the event system.
enum LogSeverity {
  /// [Level.FINE] and below — verbose debug tracing.
  fine,

  /// [Level.INFO] — normal operational messages.
  info,

  /// [Level.WARNING] — recoverable problems.
  warning,

  /// [Level.SEVERE] and above — errors that need attention.
  severe;
}

/// A log record from the `logging` package, routed through the event
/// system so it reaches all registered sinks (JSONL file, Crashlytics,
/// console).
///
/// This bridges the existing `_log.info/warning/severe` calls to the
/// event-sink pipeline without requiring every log site to be rewritten.
final class AppLogRecord extends AppEvent {
  AppLogRecord({
    required this.loggerName,
    required this.severity,
    required this.message,
    this.error,
    this.stackTrace,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String loggerName;
  final LogSeverity severity;
  final String message;
  final String? error;
  final String? stackTrace;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'log',
        'logger': loggerName,
        'severity': severity.name,
        'message': message,
        if (error != null) 'error': error,
        if (stackTrace != null) 'stackTrace': stackTrace,
        'timestamp': timestamp.toIso8601String(),
      };
}
