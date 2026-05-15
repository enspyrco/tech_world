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
  // ---------------------------------------------------------------------
  // Exhaustive sealed-class switch — the compiler-enforced gate.
  //
  // The hand-enumerated tests below are belt; this is braces. Because
  // `AppEvent` is sealed, adding a new subtype WITHOUT an arm here makes
  // this switch a compile error — the build fails before the test can
  // even run. That's the property we want: a new event cannot ship
  // without an explicit PII classification AND an explicit test arm.
  //
  // If you add a new `AppEvent` subtype, add an arm below with the
  // expected `containsPii` value. The analyzer will name the missing
  // subtype in the error message.
  // ---------------------------------------------------------------------
  group('AppEvent.containsPii (exhaustive sealed switch)', () {
    // Helper: assert the expected value AND prove the compiler walked
    // every subtype. `event` is bound by the case pattern, so each arm
    // asserts on a known concrete type.
    void check(AppEvent event) {
      final expected = switch (event) {
        // PII subtypes (15)
        SpellCastFailed() => true,
        RoomJoined() => true,
        UserSignedIn() => true,
        ProfileUpdated() => true,
        PlayerEnteredProximity() => true,
        PlayerLeftProximity() => true,
        MapEditorEntered() => true,
        RoomCreated() => true,
        RoomMapSaved() => true,
        RoomDeleted() => true,
        LiveKitConnected() => true,
        BotSpoke() => true,
        GroupMessageSent() => true,
        DmSent() => true,
        AppLogRecord() => true,
        // Non-PII subtypes (19)
        WordLearned() => false,
        ChallengeCompleted() => false,
        DoorUnlocked() => false,
        PlayerMoved() => false,
        TerminalOpened() => false,
        TerminalClosed() => false,
        RoomLeft() => false,
        UserSignedOut() => false,
        MapEdited() => false,
        BotJoined() => false,
        BotLeft() => false,
        ScreenShareToggled() => false,
        AvatarSelected() => false,
        MapEditorExited() => false,
        CodeSubmitted() => false,
        LiveKitDisconnected() => false,
        HelpRequested() => false,
        MediaEnabled() => false,
        RemoteDoorUnlocked() => false,
      };
      expect(
        event.containsPii,
        expected,
        reason: '${event.runtimeType}.containsPii disagrees with the '
            'classification declared in this exhaustive switch. Either '
            'fix the override in lib/events/types.dart or update the '
            'arm above (and think carefully about which is correct — '
            'PII leaks here become remote-sink leaks).',
      );
    }

    test('every AppEvent subtype is classified', () {
      // One representative instance of each of the 34 subtypes. Adding a
      // new subtype without an entry here trips the switch above at
      // compile time — Dart's exhaustiveness check will name the missing
      // subtype.
      final events = <AppEvent>[
        // PII (15)
        SpellCastFailed(
          reason: CastFailureReason.noMatch,
          transcript: 'ignis',
        ),
        RoomJoined(roomId: 'r', roomName: 'X'),
        UserSignedIn(userId: 'u', displayName: 'Alice'),
        ProfileUpdated(displayName: 'Alice'),
        PlayerEnteredProximity(playerId: 'p'),
        PlayerLeftProximity(playerId: 'p'),
        MapEditorEntered(mapId: 'm', mapName: 'X'),
        RoomCreated(roomId: 'r', roomName: 'X'),
        RoomMapSaved(roomId: 'r', roomName: 'X'),
        RoomDeleted(roomId: 'r', roomName: 'X'),
        LiveKitConnected(roomName: 'X'),
        BotSpoke(text: 'hi', context: BotSpokeContext.group),
        GroupMessageSent(messageId: 'm'),
        DmSent(peerId: 'p', conversationId: 'c'),
        AppLogRecord(
          loggerName: 'L',
          severity: LogSeverity.info,
          message: 'm',
        ),
        // Non-PII (19)
        WordLearned(
          wordId: WordId.values.first,
          challengeId: PromptChallengeId.values.first,
        ),
        ChallengeCompleted(
          challengeId: CodeRef(CodeChallengeId.values.first),
        ),
        DoorUnlocked(doorX: 0, doorY: 0),
        PlayerMoved(destX: 0, destY: 0),
        TerminalOpened(
          challengeId: CodeRef(CodeChallengeId.values.first),
          terminalX: 0,
          terminalY: 0,
        ),
        TerminalClosed(),
        RoomLeft(),
        UserSignedOut(),
        MapEdited(action: MapEditAction.paintTile, x: 0, y: 0),
        BotJoined(identity: 'bot-claude'),
        BotLeft(),
        ScreenShareToggled(started: true),
        AvatarSelected(avatarId: 'wizard'),
        MapEditorExited(applied: true),
        CodeSubmitted(
          challengeId: CodeChallengeId.values.first,
          result: CodeSubmitResult.pass,
        ),
        LiveKitDisconnected(),
        HelpRequested(challengeId: CodeRef(CodeChallengeId.values.first)),
        MediaEnabled(),
        RemoteDoorUnlocked(doorX: 0, doorY: 0),
      ];

      // Cardinality assertion: if a new subtype is added, the switch
      // above will refuse to compile until it's classified, AND this
      // count must be bumped to match — keeping representatives in sync
      // with the declared subtypes. This is a tripwire, not a proof.
      expect(events.length, 34);

      for (final event in events) {
        check(event);
      }
    });
  });

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

  // ---------------------------------------------------------------------
  // Async variant — same gate, same invariant. Carnot caught the
  // coverage gap on PR #459: the sync helper had three tests, the
  // async helper had zero. A future edit could invert the async
  // `if (event.containsPii) return;` and the test file would still
  // pass. Mirror the sync coverage here.
  // ---------------------------------------------------------------------

  group('registerRemoteAsyncSink', () {
    tearDown(clearSinks);

    test('drops PII events before they reach the wrapped async sink',
        () async {
      final received = <AppEvent>[];
      registerRemoteAsyncSink((event) async => received.add(event));

      dispatch([
        DmSent(peerId: 'p', conversationId: 'c'),
        BotSpoke(text: 'hi', context: BotSpokeContext.group),
        SpellCastFailed(
          reason: CastFailureReason.noMatch,
          transcript: 'leaked',
        ),
      ]);
      // Drain pending microtasks so the async sinks have run.
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
    });

    test('passes non-PII events through to the wrapped async sink',
        () async {
      final received = <AppEvent>[];
      registerRemoteAsyncSink((event) async => received.add(event));

      final ev1 = DoorUnlocked(doorX: 1, doorY: 2);
      final ev2 = MediaEnabled();
      dispatch([ev1, ev2]);
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(2));
      expect(received[0], same(ev1));
      expect(received[1], same(ev2));
    });

    test('mixed stream: only non-PII events reach the wrapped async sink',
        () async {
      final received = <AppEvent>[];
      registerRemoteAsyncSink((event) async => received.add(event));

      final keep = DoorUnlocked(doorX: 0, doorY: 0);
      dispatch([
        DmSent(peerId: 'p', conversationId: 'c'),
        keep,
        BotSpoke(text: 'x', context: BotSpokeContext.help),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single, same(keep));
    });
  });
}
