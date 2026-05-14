import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Verifies the `AppEvent.containsPii` type-system gate.
///
/// Why a test, not just a marker: the value of `containsPii` is the gate
/// to remote sinks. Forgetting to override on a new PII-carrying event
/// silently re-introduces the leak the gate exists to prevent. This test
/// is the dual-control invariant — every PII event must announce itself
/// here AND in the type definition.
void main() {
  group('AppEvent.containsPii', () {
    // -------------------------------------------------------------------
    // Positive cases — events that MUST be marked PII=true.
    // Add a case here when you add a new PII-carrying event.
    // -------------------------------------------------------------------

    test('SpellCastFailed (raw STT transcript) is PII', () {
      expect(
        SpellCastFailed(
          reason: CastFailureReason.noMatch,
          transcript: 'ignis maxima',
        ).containsPii,
        isTrue,
      );
    });

    test('BotSpoke (bot reply text) is PII', () {
      expect(
        BotSpoke(text: 'Try a for loop', context: BotSpokeContext.help)
            .containsPii,
        isTrue,
      );
    });

    test('UserSignedIn (userId + displayName) is PII', () {
      expect(
        UserSignedIn(userId: 'u1', displayName: 'Alice').containsPii,
        isTrue,
      );
    });

    test('ProfileUpdated (displayName) is PII', () {
      expect(ProfileUpdated(displayName: 'Alice').containsPii, isTrue);
    });

    test('DmSent (peerId + conversationId) is PII', () {
      expect(
        DmSent(peerId: 'peer1', conversationId: 'c1').containsPii,
        isTrue,
      );
    });

    test('GroupMessageSent (references user-typed content) is PII', () {
      expect(GroupMessageSent(messageId: 'm1').containsPii, isTrue);
    });

    test('PlayerEnteredProximity (player identity) is PII', () {
      expect(PlayerEnteredProximity(playerId: 'p1').containsPii, isTrue);
    });

    test('PlayerLeftProximity (player identity) is PII', () {
      expect(PlayerLeftProximity(playerId: 'p1').containsPii, isTrue);
    });

    test('AppLogRecord (free-form message) is PII', () {
      expect(
        AppLogRecord(
          loggerName: 'X',
          severity: LogSeverity.info,
          message: 'anything could be in here',
        ).containsPii,
        isTrue,
      );
    });

    test('RoomJoined (user-named room) is PII', () {
      expect(RoomJoined(roomId: 'r', roomName: 'Alice\'s room').containsPii,
          isTrue);
    });

    test('RoomCreated (user-named room) is PII', () {
      expect(RoomCreated(roomId: 'r', roomName: 'X').containsPii, isTrue);
    });

    test('RoomMapSaved (user-named room) is PII', () {
      expect(RoomMapSaved(roomId: 'r', roomName: 'X').containsPii, isTrue);
    });

    test('RoomDeleted (user-named room) is PII', () {
      expect(RoomDeleted(roomId: 'r', roomName: 'X').containsPii, isTrue);
    });

    test('LiveKitConnected (user-named room) is PII', () {
      expect(LiveKitConnected(roomName: 'X').containsPii, isTrue);
    });

    test('MapEditorEntered (user-named map) is PII', () {
      expect(
        MapEditorEntered(mapId: 'm', mapName: 'X').containsPii,
        isTrue,
      );
    });

    // -------------------------------------------------------------------
    // Negative cases — events that MUST be marked PII=false.
    // No user identity, no user-typed content, no transcripts.
    // -------------------------------------------------------------------

    test('WordLearned is not PII', () {
      expect(
        WordLearned(
          wordId: WordId.values.first,
          challengeId: PromptChallengeId.values.first,
        ).containsPii,
        isFalse,
      );
    });

    test('ChallengeCompleted is not PII', () {
      expect(
        ChallengeCompleted(
          challengeId: CodeRef(CodeChallengeId.values.first),
        ).containsPii,
        isFalse,
      );
    });

    test('DoorUnlocked is not PII', () {
      expect(DoorUnlocked(doorX: 1, doorY: 2).containsPii, isFalse);
    });

    test('RemoteDoorUnlocked is not PII', () {
      expect(RemoteDoorUnlocked(doorX: 1, doorY: 2).containsPii, isFalse);
    });

    test('PlayerMoved is not PII', () {
      expect(PlayerMoved(destX: 1, destY: 2).containsPii, isFalse);
    });

    test('TerminalOpened is not PII', () {
      expect(
        TerminalOpened(
          challengeId: CodeRef(CodeChallengeId.values.first),
          terminalX: 0,
          terminalY: 0,
        ).containsPii,
        isFalse,
      );
    });

    test('TerminalClosed is not PII', () {
      expect(TerminalClosed().containsPii, isFalse);
    });

    test('RoomLeft is not PII', () {
      expect(RoomLeft().containsPii, isFalse);
    });

    test('UserSignedOut is not PII', () {
      expect(UserSignedOut().containsPii, isFalse);
    });

    test('MapEdited is not PII', () {
      expect(
        MapEdited(action: MapEditAction.paintTile, x: 0, y: 0).containsPii,
        isFalse,
      );
    });

    test('BotJoined is not PII', () {
      expect(BotJoined(identity: 'bot-claude').containsPii, isFalse);
    });

    test('BotLeft is not PII', () {
      expect(BotLeft().containsPii, isFalse);
    });

    test('ScreenShareToggled is not PII', () {
      expect(ScreenShareToggled(started: true).containsPii, isFalse);
    });

    test('AvatarSelected is not PII', () {
      expect(AvatarSelected(avatarId: 'wizard').containsPii, isFalse);
    });

    test('MapEditorExited is not PII', () {
      expect(MapEditorExited(applied: true).containsPii, isFalse);
    });

    test('CodeSubmitted is not PII', () {
      expect(
        CodeSubmitted(
          challengeId: CodeChallengeId.values.first,
          result: CodeSubmitResult.pass,
        ).containsPii,
        isFalse,
      );
    });

    test('LiveKitDisconnected is not PII', () {
      expect(LiveKitDisconnected().containsPii, isFalse);
    });

    test('HelpRequested is not PII', () {
      expect(
        HelpRequested(challengeId: CodeRef(CodeChallengeId.values.first))
            .containsPii,
        isFalse,
      );
    });

    test('MediaEnabled is not PII', () {
      expect(MediaEnabled().containsPii, isFalse);
    });
  });

  // ---------------------------------------------------------------------
  // Remote-sink filter integration. `registerRemoteSink` is the single
  // entry point for any sink that sends data off-device (Crashlytics,
  // analytics, telemetry). It MUST drop PII events before the wrapped
  // sink sees them — making the gate impossible to forget.
  // ---------------------------------------------------------------------

  group('registerRemoteSink', () {
    tearDown(clearSinks);

    test('drops PII events before they reach the wrapped sink', () {
      final received = <AppEvent>[];
      registerRemoteSink(received.add);

      dispatch([
        DmSent(peerId: 'p', conversationId: 'c'),
        BotSpoke(text: 'hi', context: BotSpokeContext.group),
        SpellCastFailed(
          reason: CastFailureReason.noMatch,
          transcript: 'leaked',
        ),
      ]);

      expect(received, isEmpty);
    });

    test('passes non-PII events through to the wrapped sink', () {
      final received = <AppEvent>[];
      registerRemoteSink(received.add);

      final ev1 = DoorUnlocked(doorX: 1, doorY: 2);
      final ev2 = MediaEnabled();
      dispatch([ev1, ev2]);

      expect(received, hasLength(2));
      expect(received[0], same(ev1));
      expect(received[1], same(ev2));
    });

    test('mixed stream: only non-PII events reach the wrapped sink', () {
      final received = <AppEvent>[];
      registerRemoteSink(received.add);

      final keep = DoorUnlocked(doorX: 0, doorY: 0);
      dispatch([
        DmSent(peerId: 'p', conversationId: 'c'),
        keep,
        BotSpoke(text: 'x', context: BotSpokeContext.help),
      ]);

      expect(received, hasLength(1));
      expect(received.single, same(keep));
    });
  });
}
