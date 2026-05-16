import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Verifies the `AppEvent.piiPolicy` type-system gate.
///
/// Why a test, not just a marker: the value of `piiPolicy` is the gate
/// to remote sinks. Forgetting to override on a new PII-carrying event
/// silently re-introduces the leak the gate exists to prevent. This test
/// is the dual-control invariant — every PII event must announce itself
/// here AND in the type definition.
///
/// Graduated from `bool containsPii` to `PiiPolicy` enum to apply
/// `feedback_typed_primitives_at_boundary` — a 2-element closed set is
/// still a closed set, and naming it now means future cases (`redact`,
/// `offDeviceAllowed`, retention-tier) land as one enum value plus
/// compile errors at every exhaustive switch, rather than touching
/// every callsite.
void main() {
  // ---------------------------------------------------------------------
  // Exhaustive sealed-class switch — the compiler-enforced classification.
  //
  // Two distinct properties are enforced here. Be precise about which is
  // which, because Carnot's #462 review caught the prior wording
  // conflating them:
  //
  //   (1) COMPILE-TIME, by the analyzer:
  //       Adding a new `AppEvent` subtype WITHOUT an arm in the `check`
  //       switch below makes this file a compile error. The build fails
  //       before tests run. The analyzer names the missing subtype.
  //
  //   (2) RUN-TIME, by the test:
  //       For every representative instance in the `events` list, this
  //       test asserts `event.piiPolicy` matches the value declared by
  //       the switch arm for that runtime type.
  //
  // What is NOT proven: that the `events` list contains a representative
  // of every subtype. A future subtype could land with a switch arm
  // added AND the `piiPolicy` override added AND the representative
  // forgotten — the build would succeed and this test would pass while
  // the new subtype's override goes uncompared. The runtimeType-dedup
  // assertion below catches at least the "two entries of the same type"
  // failure mode; it does NOT catch the "missing type" mode. Dart sealed
  // classes do not expose their subtypes for runtime enumeration, so a
  // true exhaustiveness check at runtime would need code generation.
  //
  // For the foreseeable scale (34 subtypes, low churn) the
  // compile-time gate is the load-bearing property; this test makes the
  // runtime classification of representatives explicit and pins them to
  // the declared switch values.
  // ---------------------------------------------------------------------
  group('AppEvent.piiPolicy (exhaustive sealed switch)', () {
    // Helper: assert the expected value AND prove the compiler walked
    // every subtype. `event` is bound by the case pattern, so each arm
    // asserts on a known concrete type.
    void check(AppEvent event, PiiPolicy expected) {
      final declared = switch (event) {
        // PII subtypes (15)
        SpellCastFailed() => PiiPolicy.pii,
        RoomJoined() => PiiPolicy.pii,
        UserSignedIn() => PiiPolicy.pii,
        ProfileUpdated() => PiiPolicy.pii,
        PlayerEnteredProximity() => PiiPolicy.pii,
        PlayerLeftProximity() => PiiPolicy.pii,
        MapEditorEntered() => PiiPolicy.pii,
        RoomCreated() => PiiPolicy.pii,
        RoomMapSaved() => PiiPolicy.pii,
        RoomDeleted() => PiiPolicy.pii,
        LiveKitConnected() => PiiPolicy.pii,
        BotSpoke() => PiiPolicy.pii,
        GroupMessageSent() => PiiPolicy.pii,
        DmSent() => PiiPolicy.pii,
        AppLogRecord() => PiiPolicy.pii,
        // Non-PII subtypes (19)
        WordLearned() => PiiPolicy.none,
        ChallengeCompleted() => PiiPolicy.none,
        DoorUnlocked() => PiiPolicy.none,
        PlayerMoved() => PiiPolicy.none,
        TerminalOpened() => PiiPolicy.none,
        TerminalClosed() => PiiPolicy.none,
        RoomLeft() => PiiPolicy.none,
        UserSignedOut() => PiiPolicy.none,
        MapEdited() => PiiPolicy.none,
        BotJoined() => PiiPolicy.none,
        BotLeft() => PiiPolicy.none,
        ScreenShareToggled() => PiiPolicy.none,
        AvatarSelected() => PiiPolicy.none,
        MapEditorExited() => PiiPolicy.none,
        CodeSubmitted() => PiiPolicy.none,
        LiveKitDisconnected() => PiiPolicy.none,
        HelpRequested() => PiiPolicy.none,
        MediaEnabled() => PiiPolicy.none,
        RemoteDoorUnlocked() => PiiPolicy.none,
      };
      // Cross-check: the caller's expectation, the exhaustive switch,
      // and the live override must all agree.
      expect(declared, expected,
          reason: 'Test bug: expected vs switch arm disagree for '
              '${event.runtimeType}.');
      expect(
        event.piiPolicy,
        expected,
        reason: '${event.runtimeType}.piiPolicy disagrees with the '
            'classification declared in this exhaustive switch. Either '
            'fix the override in lib/events/types.dart or update the '
            'arm above (and think carefully about which is correct — '
            'PII leaks here become remote-sink leaks).',
      );
    }

    test('every representative is classified by the switch', () {
      // One representative instance per known subtype. If a new subtype
      // is added to `lib/events/types.dart`, the analyzer-enforced
      // exhaustiveness on the `check` switch above will fail the build
      // until an arm is added. The representative MUST then be added
      // here for the runtime classification to be pinned — see the
      // group comment above for what this list does and does not prove.
      final piiEvents = <AppEvent>[
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
      ];
      final nonPiiEvents = <AppEvent>[
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

      final events = [...piiEvents, ...nonPiiEvents];

      // Dedup check: no two representatives share a runtime type.
      // Catches the "copy-paste a representative line and forget to
      // change the type" failure mode. Does NOT catch a missing type;
      // see the group comment on why runtime exhaustiveness is not
      // achievable without code generation.
      final types = events.map((e) => e.runtimeType).toSet();
      expect(
        types.length,
        events.length,
        reason: 'Duplicate representatives in the events list — every '
            'AppEvent subtype should appear exactly once.',
      );

      // Cardinality cross-check: keeps this list and the switch above
      // honest against the same expected subtype count. Bump together
      // when adding a new subtype.
      expect(events.length, 34);
      expect(piiEvents.length, 15);
      expect(nonPiiEvents.length, 19);

      for (final event in piiEvents) {
        check(event, PiiPolicy.pii);
      }
      for (final event in nonPiiEvents) {
        check(event, PiiPolicy.none);
      }
    });
  });

  group('AppEvent.piiPolicy', () {
    // -------------------------------------------------------------------
    // Positive cases — events that MUST be classified PiiPolicy.pii.
    // Add a case here when you add a new PII-carrying event.
    // -------------------------------------------------------------------

    test('SpellCastFailed (raw STT transcript) is PII', () {
      expect(
        SpellCastFailed(
          reason: CastFailureReason.noMatch,
          transcript: 'ignis maxima',
        ).piiPolicy,
        PiiPolicy.pii,
      );
    });

    test('BotSpoke (bot reply text) is PII', () {
      expect(
        BotSpoke(text: 'Try a for loop', context: BotSpokeContext.help)
            .piiPolicy,
        PiiPolicy.pii,
      );
    });

    test('UserSignedIn (userId + displayName) is PII', () {
      expect(
        UserSignedIn(userId: 'u1', displayName: 'Alice').piiPolicy,
        PiiPolicy.pii,
      );
    });

    test('ProfileUpdated (displayName) is PII', () {
      expect(ProfileUpdated(displayName: 'Alice').piiPolicy, PiiPolicy.pii);
    });

    test('DmSent (peerId + conversationId) is PII', () {
      expect(
        DmSent(peerId: 'peer1', conversationId: 'c1').piiPolicy,
        PiiPolicy.pii,
      );
    });

    test('GroupMessageSent (references user-typed content) is PII', () {
      expect(GroupMessageSent(messageId: 'm1').piiPolicy, PiiPolicy.pii);
    });

    test('PlayerEnteredProximity (player identity) is PII', () {
      expect(
          PlayerEnteredProximity(playerId: 'p1').piiPolicy, PiiPolicy.pii);
    });

    test('PlayerLeftProximity (player identity) is PII', () {
      expect(PlayerLeftProximity(playerId: 'p1').piiPolicy, PiiPolicy.pii);
    });

    test('AppLogRecord (free-form message) is PII', () {
      expect(
        AppLogRecord(
          loggerName: 'X',
          severity: LogSeverity.info,
          message: 'anything could be in here',
        ).piiPolicy,
        PiiPolicy.pii,
      );
    });

    test('RoomJoined (user-named room) is PII', () {
      expect(
        RoomJoined(roomId: 'r', roomName: 'Alice\'s room').piiPolicy,
        PiiPolicy.pii,
      );
    });

    test('RoomCreated (user-named room) is PII', () {
      expect(
        RoomCreated(roomId: 'r', roomName: 'X').piiPolicy, PiiPolicy.pii);
    });

    test('RoomMapSaved (user-named room) is PII', () {
      expect(
        RoomMapSaved(roomId: 'r', roomName: 'X').piiPolicy, PiiPolicy.pii);
    });

    test('RoomDeleted (user-named room) is PII', () {
      expect(
        RoomDeleted(roomId: 'r', roomName: 'X').piiPolicy, PiiPolicy.pii);
    });

    test('LiveKitConnected (user-named room) is PII', () {
      expect(LiveKitConnected(roomName: 'X').piiPolicy, PiiPolicy.pii);
    });

    test('MapEditorEntered (user-named map) is PII', () {
      expect(
        MapEditorEntered(mapId: 'm', mapName: 'X').piiPolicy,
        PiiPolicy.pii,
      );
    });

    // -------------------------------------------------------------------
    // Negative cases — events that MUST be classified PiiPolicy.none.
    // No user identity, no user-typed content, no transcripts.
    // -------------------------------------------------------------------

    test('WordLearned is not PII', () {
      expect(
        WordLearned(
          wordId: WordId.values.first,
          challengeId: PromptChallengeId.values.first,
        ).piiPolicy,
        PiiPolicy.none,
      );
    });

    test('ChallengeCompleted is not PII', () {
      expect(
        ChallengeCompleted(
          challengeId: CodeRef(CodeChallengeId.values.first),
        ).piiPolicy,
        PiiPolicy.none,
      );
    });

    test('DoorUnlocked is not PII', () {
      expect(DoorUnlocked(doorX: 1, doorY: 2).piiPolicy, PiiPolicy.none);
    });

    test('RemoteDoorUnlocked is not PII', () {
      expect(
        RemoteDoorUnlocked(doorX: 1, doorY: 2).piiPolicy, PiiPolicy.none);
    });

    test('PlayerMoved is not PII', () {
      expect(PlayerMoved(destX: 1, destY: 2).piiPolicy, PiiPolicy.none);
    });

    test('TerminalOpened is not PII', () {
      expect(
        TerminalOpened(
          challengeId: CodeRef(CodeChallengeId.values.first),
          terminalX: 0,
          terminalY: 0,
        ).piiPolicy,
        PiiPolicy.none,
      );
    });

    test('TerminalClosed is not PII', () {
      expect(TerminalClosed().piiPolicy, PiiPolicy.none);
    });

    test('RoomLeft is not PII', () {
      expect(RoomLeft().piiPolicy, PiiPolicy.none);
    });

    test('UserSignedOut is not PII', () {
      expect(UserSignedOut().piiPolicy, PiiPolicy.none);
    });

    test('MapEdited is not PII', () {
      expect(
        MapEdited(action: MapEditAction.paintTile, x: 0, y: 0).piiPolicy,
        PiiPolicy.none,
      );
    });

    test('BotJoined is not PII', () {
      expect(BotJoined(identity: 'bot-claude').piiPolicy, PiiPolicy.none);
    });

    test('BotLeft is not PII', () {
      expect(BotLeft().piiPolicy, PiiPolicy.none);
    });

    test('ScreenShareToggled is not PII', () {
      expect(ScreenShareToggled(started: true).piiPolicy, PiiPolicy.none);
    });

    test('AvatarSelected is not PII', () {
      expect(AvatarSelected(avatarId: 'wizard').piiPolicy, PiiPolicy.none);
    });

    test('MapEditorExited is not PII', () {
      expect(MapEditorExited(applied: true).piiPolicy, PiiPolicy.none);
    });

    test('CodeSubmitted is not PII', () {
      expect(
        CodeSubmitted(
          challengeId: CodeChallengeId.values.first,
          result: CodeSubmitResult.pass,
        ).piiPolicy,
        PiiPolicy.none,
      );
    });

    test('LiveKitDisconnected is not PII', () {
      expect(LiveKitDisconnected().piiPolicy, PiiPolicy.none);
    });

    test('HelpRequested is not PII', () {
      expect(
        HelpRequested(challengeId: CodeRef(CodeChallengeId.values.first))
            .piiPolicy,
        PiiPolicy.none,
      );
    });

    test('MediaEnabled is not PII', () {
      expect(MediaEnabled().piiPolicy, PiiPolicy.none);
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
  // gate's drop-condition and the test file would still pass.
  // Mirror the sync coverage here.
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
