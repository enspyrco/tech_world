import 'package:flutter/foundation.dart';
import 'package:tech_world/events/types.dart';

/// Dev-mode console sink — pattern-matches on [AppEvent] and prints
/// a human-readable summary via [debugPrint].
///
/// Register in debug mode only:
/// ```dart
/// if (kDebugMode) {
///   registerSink(consoleSink);
/// }
/// ```
void consoleSink(AppEvent event) {
  final label = switch (event) {
    // Cast / spellbook
    WordLearned(:final wordId, :final challengeId) =>
      'WordLearned: ${wordId.name} (${challengeId.wireName})',
    ChallengeCompleted(:final challengeId) =>
      'ChallengeCompleted: ${challengeId.wireName}',
    SpellCastFailed(:final reason, :final transcript) =>
      'SpellCastFailed: ${reason.name}${transcript != null ? ' "$transcript"' : ''}',
    // Game world
    DoorUnlocked(:final doorX, :final doorY) =>
      'DoorUnlocked: ($doorX, $doorY)',
    PlayerMoved(:final destX, :final destY) =>
      'PlayerMoved: → ($destX, $destY)',
    TerminalOpened(:final challengeId, :final terminalX, :final terminalY) =>
      'TerminalOpened: ${challengeId.wireName} at ($terminalX, $terminalY)',
    TerminalClosed() => 'TerminalClosed',
    AvatarSelected(:final avatarId) => 'AvatarSelected: $avatarId',
    MapEditorEntered(:final mapId, :final mapName) =>
      'MapEditorEntered: "$mapName" ($mapId)',
    MapEditorExited(:final applied) =>
      'MapEditorExited: ${applied ? 'applied' : 'discarded'}',
    // Room
    RoomJoined(:final roomId, :final roomName) =>
      'RoomJoined: "$roomName" ($roomId)',
    RoomLeft(:final roomId) =>
      'RoomLeft${roomId != null ? ': $roomId' : ''}',
    RoomCreated(:final roomId, :final roomName) =>
      'RoomCreated: "$roomName" ($roomId)',
    RoomMapSaved(:final roomId, :final roomName) =>
      'RoomMapSaved: "$roomName" ($roomId)',
    RoomDeleted(:final roomId, :final roomName) =>
      'RoomDeleted: "$roomName" ($roomId)',
    // Auth
    UserSignedIn(:final userId, :final displayName) =>
      'UserSignedIn: $displayName ($userId)',
    UserSignedOut() => 'UserSignedOut',
    ProfileUpdated(:final displayName) =>
      'ProfileUpdated: $displayName',
    // Code
    CodeSubmitted(:final challengeId, :final result) =>
      'CodeSubmitted: ${challengeId.wireName} → ${result.name}',
    // Map editor
    MapEdited(:final action, :final x, :final y) =>
      'MapEdited: ${action.name} at ($x, $y)',
    // Multiplayer
    PlayerEnteredProximity(:final playerId) =>
      'PlayerEnteredProximity: $playerId',
    PlayerLeftProximity(:final playerId) =>
      'PlayerLeftProximity: $playerId',
    BotJoined(:final identity) => 'BotJoined: $identity',
    BotLeft() => 'BotLeft',
    ScreenShareToggled(:final started) =>
      'ScreenShare: ${started ? 'started' : 'stopped'}',
    LiveKitConnected(:final roomName) => 'LiveKitConnected: $roomName',
    LiveKitDisconnected(:final reason) =>
      'LiveKitDisconnected${reason != null ? ': $reason' : ''}',
    HelpRequested(:final challengeId) =>
      'HelpRequested: ${challengeId.wireName}',
    MediaEnabled() => 'MediaEnabled',
    RemoteDoorUnlocked(:final doorX, :final doorY) =>
      'RemoteDoorUnlocked: ($doorX, $doorY)',
    // Chat
    GroupMessageSent(:final messageId, :final challengeId) =>
      'GroupMessageSent: $messageId${challengeId != null ? ' (challenge: ${challengeId.wireName})' : ''}',
    DmSent(:final peerId) => 'DmSent: → $peerId',
    BotSpoke(:final text, :final context) =>
      'BotSpoke [${context.name}]: "${text.length > 60 ? '${text.substring(0, 60)}...' : text}"',
    // AV pipeline diagnostics
    AvPipelineSnapshot(:final participant, :final hasVideoTrack, :final captureMethod, :final bubbleType, :final audioEnabled, :final distance) =>
      'AvSnapshot: $participant track=${hasVideoTrack ? 'VIDEO' : 'NONE'} capture=${captureMethod?.name ?? 'NONE'} bubble=${bubbleType?.name ?? 'NONE'} audio=${audioEnabled ? 'ON' : 'OFF'} dist=$distance',
    AvTrackSubscribed(:final participant) =>
      'AvTrackSubscribed: $participant',
    AvTrackUnsubscribed(:final participant) =>
      'AvTrackUnsubscribed: $participant',
    AvCaptureInitialized(:final participant, :final method, :final retryCount) =>
      'AvCaptureInit: $participant method=${method.name} retries=$retryCount',
    AvCaptureInitFailed(:final participant, :final maxRetries) =>
      'AvCaptureInitFailed: $participant after $maxRetries retries',
    AvBubbleCreated(:final participant, :final bubbleType) =>
      'AvBubbleCreated: $participant type=${bubbleType.name}',
    AvBubbleRemoved(:final participant) =>
      'AvBubbleRemoved: $participant',
    AvAudioGateChanged(:final participant, :final enabled, :final distance) =>
      'AvAudioGate: $participant ${enabled ? 'ENABLED' : 'DISABLED'} dist=$distance',
    AvFrameDecodeError(:final participant, :final error) =>
      'AvFrameDecodeError: $participant $error',
    AvSpeakingChanged(:final participant, :final speaking) =>
      'AvSpeaking: $participant ${speaking ? 'START' : 'STOP'}',
    // Log bridge
    AppLogRecord(:final loggerName, :final severity, :final message) =>
      '${severity.name.toUpperCase()} $loggerName: $message',
  };
  debugPrint('[event] $label');
}
