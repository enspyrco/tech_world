import 'package:flutter/foundation.dart';
import 'package:tech_world/events/types.dart';

/// Whether the console sink should be registered for a build with these flags.
///
/// `debug || web`, and the `web` half is the whole point.
///
/// On native, the durable record is `events.jsonl` — the console is a developer
/// convenience and release builds do not need it. On **web there is no file
/// sink at all**: `path_provider` has no app-documents directory in a browser,
/// so `main.dart`'s `if (!kIsWeb)` branch never runs there. Before this,
/// a release web client had NO sink of any kind — every `_log.*` call, every
/// dispatched [AppEvent], went nowhere. That is the one platform anybody can
/// reach from a URL, and it was undebuggable from the only tool every user
/// already has. (claude-tasks#4472.)
///
/// **Split from its binding so the RULE is testable.** The call site is
/// `consoleSinkEnabledFor(debug: kDebugMode, web: kIsWeb)` and both are
/// compile-time constants; `flutter test` only ever runs debug-native, so no
/// test can observe this guard from outside — the mode it would need to run in
/// is the mode that cannot host the test. Same reason `Autopilot.allowedIn`
/// takes its flag as a parameter.
///
/// **Why this stays a local sink.** [registerSink], not [registerRemoteSink]:
/// `print` reaches the browser console on the user's own machine and nothing
/// leaves the device, so the PII gate — which exists to stop events going
/// off-device — does not apply. Gating it on [PiiPolicy] instead was
/// considered and rejected: 34 of the event types are `PiiPolicy.pii`,
/// including every [AppLogRecord] (marked conservatively because a free-form
/// message *might* carry user content), so a policy-filtered console would
/// print `[redacted]` for most of the timeline — present but uninformative,
/// which trains readers to ignore it.
///
/// The one way this IS wider than a native file: a browser extension holding
/// host permission for this origin can read the console. Such an extension can
/// already read the DOM, storage and network traffic for the same origin, so
/// the console grants no reach it does not have — but the distinction is real
/// and is why this comment exists rather than a bare "it's local".
bool consoleSinkEnabledFor({required bool debug, required bool web}) =>
    debug || web;

/// Console sink — pattern-matches on [AppEvent] and prints a human-readable
/// summary via [debugPrint].
///
/// Registered when [consoleSinkEnabledFor] says so:
/// ```dart
/// if (consoleSinkEnabledFor(debug: kDebugMode, web: kIsWeb)) {
///   registerSink(consoleSink);
/// }
/// ```
///
/// [debugPrint] is NOT stripped in release — `debugPrint` defaults to
/// `debugPrintThrottled`, which calls `print` with no build-mode guard
/// (`flutter/lib/src/foundation/print.dart`). Verified before relying on it,
/// because a sink that silently prints nothing in release is worse than no
/// sink: it reports success while doing nothing.
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
    RemotePlayerMoved(:final playerId, :final destX, :final destY) =>
      'RemotePlayerMoved: $playerId → ($destX, $destY)',
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
    BubblesMerged(:final participantIds) =>
      'BubblesMerged: ${participantIds.join(" + ")}',
    BubblesUnmerged(:final participantIds) =>
      'BubblesUnmerged: ${participantIds.join(" + ")}',
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
    PlayersMentioned(:final mentionedUids, :final mentionerUid) =>
      'PlayersMentioned: $mentionerUid → ${mentionedUids.join(', ')}',
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
