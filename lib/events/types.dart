import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Return type for business functions that produce events alongside a result.
typedef WithEvents<T> = (T, List<AppEvent>);

/// Sealed wrapper for the union of code and prompt challenge identifiers.
///
/// Both [CodeChallengeId] and [PromptChallengeId] serialize to disjoint
/// wire names in the same Firestore `completedChallenges` array
/// (disjointness pinned by `code_challenge_id_test.dart`). The sealed
/// wrapper lets event consumers pattern-match on which kind they have
/// instead of stringly-comparing wire names.
///
/// Wire format unchanged — serialize via [wireName].
sealed class ChallengeRef {
  const ChallengeRef();
  String get wireName;

  /// Parse a wire-format challenge ID. Tries code first (23 entries) then
  /// prompt (18). Returns null for unknown wire values — caller decides
  /// whether to drop, log, or treat as a soft error.
  static ChallengeRef? parse(String wire) {
    final code = CodeChallengeId.parse(wire);
    if (code != null) return CodeRef(code);
    final prompt = PromptChallengeId.parse(wire);
    if (prompt != null) return PromptRef(prompt);
    return null;
  }
}

final class CodeRef extends ChallengeRef {
  const CodeRef(this.id);
  final CodeChallengeId id;
  @override
  String get wireName => id.wireName;
  @override
  bool operator ==(Object other) => other is CodeRef && other.id == id;
  @override
  int get hashCode => Object.hash('CodeRef', id);
  @override
  String toString() => 'CodeRef(${id.name})';
}

final class PromptRef extends ChallengeRef {
  const PromptRef(this.id);
  final PromptChallengeId id;
  @override
  String get wireName => id.wireName;
  @override
  bool operator ==(Object other) => other is PromptRef && other.id == id;
  @override
  int get hashCode => Object.hash('PromptRef', id);
  @override
  String toString() => 'PromptRef(${id.name})';
}

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

  /// Whether this event carries personally-identifiable information
  /// (user identifiers, display names, raw transcripts, free-form user
  /// content, bot reply text, etc.).
  ///
  /// The default is `false` — events must explicitly opt in by
  /// overriding `=> true;`. This is the type-system gate used by
  /// [registerRemoteSink] (see `lib/events/dispatch.dart`) to drop
  /// PII events before they reach any off-device sink (Crashlytics,
  /// analytics, telemetry).
  ///
  /// Be conservative: when in doubt, return `true`. The cost of marking
  /// a non-PII event as PII is a missing remote-sink line; the cost of
  /// missing a PII event is a leak.
  ///
  /// Invariant: every PII override is pinned by a positive case in
  /// `test/events/pii_marker_test.dart` (dual control).
  bool get containsPii => false;
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

  /// Typed challenge ID. Serializes to wire name (matches Firestore
  /// `completedChallenges` array) — the union of [CodeChallengeId] and
  /// [PromptChallengeId] is expressed via [ChallengeRef], not String.
  final ChallengeRef challengeId;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'challenge_completed',
        'challengeId': challengeId.wireName,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Reason a door-cast failed.
enum CastFailureReason { noMatch, notLearned, wrongDoor }

/// A voice-cast at a door failed.
///
/// Note: [transcript] contains STT output of what the user spoke.
/// Marked [containsPii] — `registerRemoteSink` will drop this event
/// before it reaches any off-device sink.
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

  /// PII: raw STT transcript of what the user spoke.
  @override
  bool get containsPii => true;
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

  final ChallengeRef challengeId;
  final int terminalX;
  final int terminalY;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'terminal_opened',
        'challengeId': challengeId.wireName,
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

  /// PII: room names are user-typed free text.
  @override
  bool get containsPii => true;
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

  /// PII: user identifier + display name.
  @override
  bool get containsPii => true;
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

  /// PII: display name.
  @override
  bool get containsPii => true;
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

  /// PII: player identifier.
  @override
  bool get containsPii => true;
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

  /// PII: player identifier.
  @override
  bool get containsPii => true;
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

  /// PII: map names are user-typed free text.
  @override
  bool get containsPii => true;
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

  /// PII: room names are user-typed free text.
  @override
  bool get containsPii => true;
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

  /// PII: room names are user-typed free text.
  @override
  bool get containsPii => true;
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

  /// PII: room names are user-typed free text.
  @override
  bool get containsPii => true;
}

/// Outcome of a code submission evaluation.
enum CodeSubmitResult {
  pass,
  fail,
  timeout;

  /// Parse a bot response string into a typed result. Case-insensitive
  /// at the boundary — the bot's exact casing has shifted historically.
  static CodeSubmitResult fromWire(String? wire) => switch (wire?.toLowerCase()) {
        'pass' => CodeSubmitResult.pass,
        'fail' => CodeSubmitResult.fail,
        _ => CodeSubmitResult.timeout,
      };
}

/// Player submitted code for a challenge.
///
/// [challengeId] is [CodeChallengeId] (not [ChallengeRef]) because code
/// submission is strictly a code-challenge concern — prompt challenges
/// fire [ChallengeCompleted] from `cast_effects`, never this event.
final class CodeSubmitted extends AppEvent {
  CodeSubmitted({
    required this.challengeId,
    required this.result,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final CodeChallengeId challengeId;
  final CodeSubmitResult result;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'code_submitted',
        'challengeId': challengeId.wireName,
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

  /// PII: room names are user-typed free text.
  @override
  bool get containsPii => true;
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

  /// PII: free-form bot reply text (may quote or reference user input).
  @override
  bool get containsPii => true;
}

/// Player requested a hint from Clawd.
final class HelpRequested extends AppEvent {
  HelpRequested({required this.challengeId, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  final ChallengeRef challengeId;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'help_requested',
        'challengeId': challengeId.wireName,
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
  final ChallengeRef? challengeId;
  @override
  final DateTime timestamp;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'group_message_sent',
        'messageId': messageId,
        if (challengeId != null) 'challengeId': challengeId!.wireName,
        'timestamp': timestamp.toIso8601String(),
      };

  /// PII: references a user-authored chat message (and the sender).
  @override
  bool get containsPii => true;
}

/// Player sent a DM to another player.
///
/// Note: [peerId] and [conversationId] are written to the local JSONL log.
/// Marked [containsPii] — `registerRemoteSink` will drop this event
/// before it reaches any off-device sink.
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

  /// PII: peer identifier and conversation identifier.
  @override
  bool get containsPii => true;
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

  /// PII: free-form log message may contain transcripts, oracle replies,
  /// user names, or anything else a `_log.*` call passes in. Mark all log
  /// records as PII conservatively — remote sinks must scrub or route
  /// through Crashlytics' own redaction layer, not the JSONL pipeline.
  @override
  bool get containsPii => true;
}
