import 'dart:convert';
import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/progress/progress_service.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/proximity/proximity_service.dart';
import 'package:tech_world/spellbook/cast_effects.dart';
import 'package:tech_world/spellbook/door_cast_result.dart';
import 'package:tech_world/spellbook/spellbook_service.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// One sample instance of every [AppEvent] subtype, for smoke-testing the pipeline.
///
/// **When adding a new event type:**
/// 1. Add one sample instance here.
/// 2. The count assertions below derive from this list — they update automatically.
/// 3. Add a `group('<NewType>')` per-type serialization test below.
List<AppEvent> allSampleEvents() => [
      // Cast / spellbook
      WordLearned(
        wordId: WordId.ignis,
        challengeId: PromptChallengeId.evocationFizzbuzz,
      ),
      ChallengeCompleted(challengeId: 'evocation_fizzbuzz'),
      SpellCastFailed(
        reason: CastFailureReason.noMatch,
        transcript: 'flambe',
      ),
      // Game world
      DoorUnlocked(doorX: 12, doorY: 8),
      RemoteDoorUnlocked(doorX: 30, doorY: 15),
      PlayerMoved(destX: 25, destY: 10),
      TerminalOpened(
        challengeId: 'evocation_fizzbuzz',
        terminalX: 15,
        terminalY: 10,
      ),
      TerminalClosed(),
      AvatarSelected(avatarId: 'wizard_blue'),
      MediaEnabled(),
      // Room
      RoomJoined(roomId: 'room_01', roomName: "The Wizard's Tower"),
      RoomLeft(roomId: 'room_01'),
      RoomCreated(roomId: 'room_02', roomName: "Test Lab"),
      RoomMapSaved(roomId: 'room_01', roomName: "The Wizard's Tower"),
      RoomDeleted(roomId: 'room_02', roomName: "Test Lab"),
      // Auth
      UserSignedIn(userId: 'user_abc', displayName: 'Alice'),
      UserSignedOut(),
      ProfileUpdated(displayName: 'Alice the Magnificent'),
      // Code
      CodeSubmitted(
        challengeId: 'evocation_fizzbuzz',
        result: CodeSubmitResult.pass,
      ),
      // Map editor
      MapEditorEntered(mapId: 'wizards_tower', mapName: "The Wizard's Tower"),
      MapEditorExited(applied: true),
      MapEdited(action: MapEditAction.paintWall, x: 25, y: 12),
      // Multiplayer
      PlayerEnteredProximity(playerId: 'user_456'),
      PlayerLeftProximity(playerId: 'user_456'),
      BotJoined(identity: 'bot-claude'),
      BotLeft(),
      ScreenShareToggled(started: true),
      LiveKitConnected(roomName: 'l_room'),
      LiveKitDisconnected(reason: 'network_error'),
      // Chat
      GroupMessageSent(messageId: '1715178785123456'),
      DmSent(peerId: 'user_456', conversationId: 'user_abc_user_456'),
      HelpRequested(challengeId: 'evocation_countdown'),
      BotSpoke(text: 'Welcome, wizard!', context: BotSpokeContext.group),
      // Log bridge
      AppLogRecord(
        loggerName: 'ChatService',
        severity: LogSeverity.info,
        message: 'Sent message: "hello"',
      ),
    ];

void main() {
  late List<AppEvent> captured;

  setUp(() {
    captured = [];
    registerSink(captured.add);
  });

  tearDown(clearSinks);

  // ===========================================================================
  // Pipeline smoke tests — every event type dispatches and serializes
  // ===========================================================================

  group('pipeline smoke', () {
    test('all event types dispatch and serialize to valid JSON', () {
      final events = allSampleEvents();
      final types = events.map((e) => e.runtimeType).toSet();
      // Count derives from allSampleEvents() — add a new entry there when
      // adding a new AppEvent subtype, and this assertion auto-updates.
      expect(types.length, events.length,
          reason: 'every entry in allSampleEvents() must be a distinct type');

      dispatch(events);
      expect(captured.length, events.length);

      for (final event in captured) {
        final json = event.toJson();
        expect(json['type'], isA<String>());
        expect(json['timestamp'], isA<String>());
        final encoded = jsonEncode(json);
        final decoded = jsonDecode(encoded) as Map<String, dynamic>;
        expect(decoded['type'], json['type']);
      }
    });

    test('all type strings are unique', () {
      final events = allSampleEvents();
      final typeStrings =
          events.map((e) => e.toJson()['type'] as String).toSet();
      expect(typeStrings.length, events.length,
          reason: 'every AppEvent subtype must have a distinct JSON type string');
    });

    test('JSONL lines contain no embedded newlines', () {
      dispatch(allSampleEvents());
      for (final event in captured) {
        final line = jsonEncode(event.toJson());
        expect(line.contains('\n'), isFalse);
      }
    });
  });

  // ===========================================================================
  // Per-type serialization — every field round-trips correctly
  // ===========================================================================

  group('WordLearned', () {
    test('serializes wordId and challengeId', () {
      dispatch([WordLearned(
        wordId: WordId.lumen,
        challengeId: PromptChallengeId.divinationColor,
      )]);
      final json = captured[0].toJson();
      expect(json['type'], 'word_learned');
      expect(json['wordId'], 'lumen');
      expect(json['challengeId'], 'divination_color');
    });
  });

  group('ChallengeCompleted', () {
    test('serializes wire-format challengeId', () {
      dispatch([ChallengeCompleted(challengeId: 'conjuration_sort')]);
      expect(captured[0].toJson()['challengeId'], 'conjuration_sort');
    });
  });

  group('SpellCastFailed', () {
    for (final reason in CastFailureReason.values) {
      test('serializes reason=${reason.name}', () {
        dispatch([SpellCastFailed(reason: reason, transcript: 'test')]);
        final json = captured[0].toJson();
        expect(json['type'], 'spell_cast_failed');
        expect(json['reason'], reason.name);
        expect(json['transcript'], 'test');
      });
    }

    test('null transcript omitted from JSON', () {
      dispatch([SpellCastFailed(reason: CastFailureReason.noMatch)]);
      expect(captured[0].toJson().containsKey('transcript'), isFalse);
    });
  });

  group('DoorUnlocked', () {
    test('serializes coordinates', () {
      dispatch([DoorUnlocked(doorX: 5, doorY: 10)]);
      final json = captured[0].toJson();
      expect(json['doorX'], 5);
      expect(json['doorY'], 10);
    });
  });

  group('RemoteDoorUnlocked', () {
    test('serializes coordinates', () {
      dispatch([RemoteDoorUnlocked(doorX: 30, doorY: 15)]);
      final json = captured[0].toJson();
      expect(json['type'], 'remote_door_unlocked');
      expect(json['doorX'], 30);
    });
  });

  group('PlayerMoved', () {
    test('serializes destination', () {
      dispatch([PlayerMoved(destX: 42, destY: 7)]);
      final json = captured[0].toJson();
      expect(json['destX'], 42);
      expect(json['destY'], 7);
    });
  });

  group('TerminalOpened', () {
    test('serializes challengeId and position', () {
      dispatch([TerminalOpened(
        challengeId: 'evocation_countdown',
        terminalX: 20,
        terminalY: 5,
      )]);
      final json = captured[0].toJson();
      expect(json['challengeId'], 'evocation_countdown');
      expect(json['terminalX'], 20);
      expect(json['terminalY'], 5);
    });
  });

  group('TerminalClosed', () {
    test('serializes with type and timestamp only', () {
      dispatch([TerminalClosed()]);
      final json = captured[0].toJson();
      expect(json['type'], 'terminal_closed');
      expect(json.keys.toSet(), {'type', 'timestamp'});
    });
  });

  group('AvatarSelected', () {
    test('serializes avatarId', () {
      dispatch([AvatarSelected(avatarId: 'cat_purple')]);
      expect(captured[0].toJson()['avatarId'], 'cat_purple');
    });
  });

  group('MediaEnabled', () {
    test('serializes with type and timestamp only', () {
      dispatch([MediaEnabled()]);
      final json = captured[0].toJson();
      expect(json['type'], 'media_enabled');
      expect(json.keys.toSet(), {'type', 'timestamp'});
    });
  });

  group('RoomJoined', () {
    test('serializes roomId and roomName', () {
      dispatch([RoomJoined(roomId: 'r1', roomName: 'Test Room')]);
      final json = captured[0].toJson();
      expect(json['roomId'], 'r1');
      expect(json['roomName'], 'Test Room');
    });
  });

  group('RoomLeft', () {
    test('serializes roomId when present', () {
      dispatch([RoomLeft(roomId: 'r1')]);
      expect(captured[0].toJson()['roomId'], 'r1');
    });

    test('omits roomId when null', () {
      dispatch([RoomLeft()]);
      expect(captured[0].toJson().containsKey('roomId'), isFalse);
    });
  });

  group('RoomCreated', () {
    test('serializes roomId and roomName', () {
      dispatch([RoomCreated(roomId: 'new_r', roomName: 'New Room')]);
      final json = captured[0].toJson();
      expect(json['type'], 'room_created');
      expect(json['roomId'], 'new_r');
    });
  });

  group('RoomMapSaved', () {
    test('serializes roomId and roomName', () {
      dispatch([RoomMapSaved(roomId: 'r1', roomName: 'Saved Room')]);
      final json = captured[0].toJson();
      expect(json['type'], 'room_map_saved');
      expect(json['roomId'], 'r1');
      expect(json['roomName'], 'Saved Room');
    });
  });

  group('RoomDeleted', () {
    test('serializes roomId and roomName', () {
      dispatch([RoomDeleted(roomId: 'r1', roomName: 'Deleted Room')]);
      final json = captured[0].toJson();
      expect(json['type'], 'room_deleted');
      expect(json['roomName'], 'Deleted Room');
    });
  });

  group('UserSignedIn', () {
    test('serializes userId and displayName', () {
      dispatch([UserSignedIn(userId: 'u1', displayName: 'Alice')]);
      final json = captured[0].toJson();
      expect(json['userId'], 'u1');
      expect(json['displayName'], 'Alice');
    });
  });

  group('UserSignedOut', () {
    test('serializes with type and timestamp only', () {
      dispatch([UserSignedOut()]);
      final json = captured[0].toJson();
      expect(json['type'], 'user_signed_out');
      expect(json.keys.toSet(), {'type', 'timestamp'});
    });
  });

  group('ProfileUpdated', () {
    test('serializes displayName', () {
      dispatch([ProfileUpdated(displayName: 'New Name')]);
      expect(captured[0].toJson()['displayName'], 'New Name');
    });
  });

  group('CodeSubmitted', () {
    for (final result in CodeSubmitResult.values) {
      test('serializes result=${result.name}', () {
        dispatch([CodeSubmitted(
          challengeId: 'test_challenge',
          result: result,
        )]);
        final json = captured[0].toJson();
        expect(json['result'], result.name);
      });
    }

    test('fromWire parses all variants', () {
      expect(CodeSubmitResult.fromWire('pass'), CodeSubmitResult.pass);
      expect(CodeSubmitResult.fromWire('PASS'), CodeSubmitResult.pass);
      expect(CodeSubmitResult.fromWire('fail'), CodeSubmitResult.fail);
      expect(CodeSubmitResult.fromWire('Fail'), CodeSubmitResult.fail);
      expect(CodeSubmitResult.fromWire(null), CodeSubmitResult.timeout);
      expect(CodeSubmitResult.fromWire('garbage'), CodeSubmitResult.timeout);
    });
  });

  group('MapEditorEntered', () {
    test('serializes mapId and mapName', () {
      dispatch([MapEditorEntered(mapId: 'm1', mapName: 'Map 1')]);
      final json = captured[0].toJson();
      expect(json['mapId'], 'm1');
      expect(json['mapName'], 'Map 1');
    });
  });

  group('MapEditorExited', () {
    test('serializes applied=true', () {
      dispatch([MapEditorExited(applied: true)]);
      expect(captured[0].toJson()['applied'], true);
    });

    test('serializes applied=false', () {
      dispatch([MapEditorExited(applied: false)]);
      expect(captured[0].toJson()['applied'], false);
    });
  });

  group('MapEdited', () {
    for (final action in MapEditAction.values) {
      test('serializes action=${action.name}', () {
        dispatch([MapEdited(action: action, x: 10, y: 20)]);
        final json = captured[0].toJson();
        expect(json['action'], action.name);
        expect(json['x'], 10);
        expect(json['y'], 20);
      });
    }
  });

  group('PlayerEnteredProximity', () {
    test('serializes playerId', () {
      dispatch([PlayerEnteredProximity(playerId: 'p1')]);
      expect(captured[0].toJson()['playerId'], 'p1');
    });
  });

  group('PlayerLeftProximity', () {
    test('serializes playerId', () {
      dispatch([PlayerLeftProximity(playerId: 'p1')]);
      expect(captured[0].toJson()['playerId'], 'p1');
    });
  });

  group('BotJoined', () {
    test('serializes identity', () {
      dispatch([BotJoined(identity: 'agent-AJ_12345')]);
      expect(captured[0].toJson()['identity'], 'agent-AJ_12345');
    });
  });

  group('BotLeft', () {
    test('serializes with type and timestamp only', () {
      dispatch([BotLeft()]);
      final json = captured[0].toJson();
      expect(json['type'], 'bot_left');
      expect(json.keys.toSet(), {'type', 'timestamp'});
    });
  });

  group('ScreenShareToggled', () {
    test('serializes started=true', () {
      dispatch([ScreenShareToggled(started: true)]);
      expect(captured[0].toJson()['started'], true);
    });

    test('serializes started=false', () {
      dispatch([ScreenShareToggled(started: false)]);
      expect(captured[0].toJson()['started'], false);
    });
  });

  group('LiveKitConnected', () {
    test('serializes roomName', () {
      dispatch([LiveKitConnected(roomName: 'test_room')]);
      expect(captured[0].toJson()['roomName'], 'test_room');
    });
  });

  group('LiveKitDisconnected', () {
    test('serializes reason when present', () {
      dispatch([LiveKitDisconnected(reason: 'timeout')]);
      expect(captured[0].toJson()['reason'], 'timeout');
    });

    test('omits reason when null', () {
      dispatch([LiveKitDisconnected()]);
      expect(captured[0].toJson().containsKey('reason'), isFalse);
    });
  });

  group('GroupMessageSent', () {
    test('serializes messageId and optional challengeId', () {
      dispatch([GroupMessageSent(
        messageId: 'msg_1',
        challengeId: 'evocation_fizzbuzz',
      )]);
      final json = captured[0].toJson();
      expect(json['messageId'], 'msg_1');
      expect(json['challengeId'], 'evocation_fizzbuzz');
    });

    test('omits challengeId when null', () {
      dispatch([GroupMessageSent(messageId: 'msg_2')]);
      expect(captured[0].toJson().containsKey('challengeId'), isFalse);
    });
  });

  group('DmSent', () {
    test('serializes peerId and conversationId', () {
      dispatch([DmSent(peerId: 'p1', conversationId: 'conv_1')]);
      final json = captured[0].toJson();
      expect(json['peerId'], 'p1');
      expect(json['conversationId'], 'conv_1');
    });
  });

  group('HelpRequested', () {
    test('serializes challengeId', () {
      dispatch([HelpRequested(challengeId: 'evocation_countdown')]);
      expect(captured[0].toJson()['challengeId'], 'evocation_countdown');
    });
  });

  group('BotSpoke', () {
    for (final ctx in BotSpokeContext.values) {
      test('serializes context=${ctx.name}', () {
        dispatch([BotSpoke(text: 'Hello', context: ctx)]);
        final json = captured[0].toJson();
        expect(json['context'], ctx.name);
        expect(json['text'], 'Hello');
      });
    }
  });

  group('AppLogRecord', () {
    for (final severity in LogSeverity.values) {
      test('serializes severity=${severity.name}', () {
        dispatch([AppLogRecord(
          loggerName: 'TestLogger',
          severity: severity,
          message: 'test message',
        )]);
        final json = captured[0].toJson();
        expect(json['type'], 'log');
        expect(json['severity'], severity.name);
        expect(json['logger'], 'TestLogger');
      });
    }

    test('includes error and stackTrace when present', () {
      dispatch([AppLogRecord(
        loggerName: 'X',
        severity: LogSeverity.severe,
        message: 'boom',
        error: 'NullPointerException',
        stackTrace: '#0 main (test.dart:1)',
      )]);
      final json = captured[0].toJson();
      expect(json['error'], 'NullPointerException');
      expect(json['stackTrace'], contains('main'));
    });

    test('omits error and stackTrace when null', () {
      dispatch([AppLogRecord(
        loggerName: 'X',
        severity: LogSeverity.info,
        message: 'ok',
      )]);
      final json = captured[0].toJson();
      expect(json.containsKey('error'), isFalse);
      expect(json.containsKey('stackTrace'), isFalse);
    });
  });

  // ===========================================================================
  // Scenario E2E — real code paths triggering real events
  // ===========================================================================

  group('cast completion E2E', () {
    late FakeFirebaseFirestore fakeFirestore;
    late SpellbookService spellbook;
    late ProgressService progress;

    setUp(() async {
      fakeFirestore = FakeFirebaseFirestore();
      spellbook = SpellbookService(
        uid: 'test-user',
        collection: fakeFirestore.collection('users'),
      );
      progress = ProgressService(
        uid: 'test-user',
        collection: fakeFirestore.collection('users'),
      );
      await spellbook.loadSpellbook();
      await progress.loadProgress();
    });

    tearDown(() {
      spellbook.dispose();
      progress.dispose();
    });

    test('successful cast produces WordLearned → ChallengeCompleted', () async {
      await applyCastSuccessEffects(
        challengeId: PromptChallengeId.evocationFizzbuzz,
        spellbook: spellbook,
        progress: progress,
      );

      final types = captured.map((e) => e.runtimeType).toList();
      expect(types, [WordLearned, ChallengeCompleted]);

      final wordEvent = captured[0] as WordLearned;
      expect(wordEvent.wordId, WordId.ignis);
      expect(wordEvent.challengeId, PromptChallengeId.evocationFizzbuzz);

      final challengeEvent = captured[1] as ChallengeCompleted;
      expect(challengeEvent.challengeId, 'evocation_fizzbuzz');
    });

    test('performCast pass emits events, fail emits nothing', () async {
      final (failResult, failEvents) = await performCast(
        transcript: 'ignis',
        doorRequiredChallenges: [PromptChallengeId.evocationFizzbuzz],
        spellbook: spellbook,
        progress: progress,
      );
      expect(failResult, isA<DoorCastNotLearned>());
      expect(failEvents, isEmpty);
      expect(captured, isEmpty);

      await spellbook.learnWord(WordId.ignis);

      final (passResult, passEvents) = await performCast(
        transcript: 'ignis',
        doorRequiredChallenges: [PromptChallengeId.evocationFizzbuzz],
        spellbook: spellbook,
        progress: progress,
      );
      expect(passResult, isA<CastPass>());
      expect(passEvents.length, 2);
      expect(captured.map((e) => e.runtimeType).toList(),
          [WordLearned, ChallengeCompleted]);
    });

    test('wrong door cast emits nothing', () async {
      await spellbook.learnWord(WordId.ignis);

      final (result, events) = await performCast(
        transcript: 'ignis',
        doorRequiredChallenges: [PromptChallengeId.divinationColor],
        spellbook: spellbook,
        progress: progress,
      );
      expect(result, isA<CastWrongDoor>());
      expect(events, isEmpty);
      expect(captured, isEmpty);
    });

    test('no-match cast emits nothing', () async {
      final (result, events) = await performCast(
        transcript: 'abracadabra',
        doorRequiredChallenges: [PromptChallengeId.evocationFizzbuzz],
        spellbook: spellbook,
        progress: progress,
      );
      expect(result, isA<DoorCastNoMatch>());
      expect(events, isEmpty);
      expect(captured, isEmpty);
    });

    test('null transcript cast emits nothing', () async {
      final (result, events) = await performCast(
        transcript: null,
        doorRequiredChallenges: [PromptChallengeId.evocationFizzbuzz],
        spellbook: spellbook,
        progress: progress,
      );
      expect(result, isA<DoorCastNoMatch>());
      expect(events, isEmpty);
    });

    test('all 18 prompt challenges produce correct event pairs', () async {
      for (final id in PromptChallengeId.values) {
        captured.clear();
        await applyCastSuccessEffects(
          challengeId: id,
          spellbook: spellbook,
          progress: progress,
        );

        expect(captured.length, 2,
            reason: '${id.name} should produce exactly 2 events');

        final word = captured[0] as WordLearned;
        expect(word.challengeId, id);

        final challenge = captured[1] as ChallengeCompleted;
        expect(challenge.challengeId, id.wireName);
      }
    });

    test('idempotent — second cast of same challenge still emits events',
        () async {
      await applyCastSuccessEffects(
        challengeId: PromptChallengeId.evocationFizzbuzz,
        spellbook: spellbook,
        progress: progress,
      );
      expect(captured.length, 2);

      captured.clear();
      await applyCastSuccessEffects(
        challengeId: PromptChallengeId.evocationFizzbuzz,
        spellbook: spellbook,
        progress: progress,
      );
      // Events still emitted (they're facts about the cast, even if
      // the underlying services are idempotent).
      expect(captured.length, 2);
    });
  });

  // ===========================================================================
  // Proximity E2E — real ProximityService code path
  // ===========================================================================

  group('proximity E2E', () {
    late ProximityService proximity;

    setUp(() {
      proximity = ProximityService(proximityThreshold: 5);
    });

    tearDown(() {
      proximity.dispose();
    });

    test('player entering range fires PlayerEnteredProximity', () {
      proximity.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {'player_2': const Point(3, 3)},
      );
      expect(captured.length, 1);
      expect(captured[0], isA<PlayerEnteredProximity>()
          .having((e) => e.playerId, 'playerId', 'player_2'));
    });

    test('player leaving range fires PlayerLeftProximity', () {
      // Enter first.
      proximity.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {'player_2': const Point(3, 3)},
      );
      captured.clear();

      // Leave.
      proximity.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {'player_2': const Point(20, 20)},
      );
      expect(captured.length, 1);
      expect(captured[0], isA<PlayerLeftProximity>()
          .having((e) => e.playerId, 'playerId', 'player_2'));
    });

    test('player far away produces no events', () {
      proximity.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {'player_2': const Point(20, 20)},
      );
      expect(captured, isEmpty);
    });

    test('player disconnecting fires PlayerLeftProximity', () {
      proximity.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {'player_2': const Point(3, 3)},
      );
      captured.clear();

      proximity.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {},
      );
      expect(captured.length, 1);
      expect(captured[0], isA<PlayerLeftProximity>());
    });

    test('multiple players produce independent events', () {
      proximity.checkProximity(
        localPlayerPosition: const Point(10, 10),
        otherPlayerPositions: {
          'alice': const Point(12, 12),
          'bob': const Point(8, 8),
          'charlie': const Point(50, 50),
        },
      );

      expect(captured.length, 2);
      final ids = captured
          .cast<PlayerEnteredProximity>()
          .map((e) => e.playerId)
          .toSet();
      expect(ids, {'alice', 'bob'});
    });

    test('staying in range does not re-fire enter event', () {
      proximity.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {'p': const Point(3, 3)},
      );
      expect(captured.length, 1);

      captured.clear();
      proximity.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {'p': const Point(3, 3)},
      );
      expect(captured, isEmpty);
    });

    test('enter → leave → re-enter fires three events total', () {
      // Enter.
      proximity.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {'p': const Point(3, 3)},
      );
      // Leave.
      proximity.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {'p': const Point(20, 20)},
      );
      // Re-enter.
      proximity.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {'p': const Point(4, 4)},
      );

      expect(captured.length, 3);
      expect(captured[0], isA<PlayerEnteredProximity>());
      expect(captured[1], isA<PlayerLeftProximity>());
      expect(captured[2], isA<PlayerEnteredProximity>());
    });
  });

  // ===========================================================================
  // Session lifecycle E2E — event sequence tells a session story
  // ===========================================================================

  group('session lifecycle', () {
    test('full session sequence is well-ordered', () {
      // Simulate a complete session through direct dispatch.
      dispatch([
        UserSignedIn(userId: 'u1', displayName: 'Alice'),
        AvatarSelected(avatarId: 'wizard_blue'),
        RoomJoined(roomId: 'r1', roomName: "The Wizard's Tower"),
        LiveKitConnected(roomName: 'l_room'),
        MediaEnabled(),
        BotJoined(identity: 'bot-claude'),
        PlayerMoved(destX: 12, destY: 8),
        PlayerEnteredProximity(playerId: 'user_2'),
        TerminalOpened(
          challengeId: 'evocation_fizzbuzz',
          terminalX: 15,
          terminalY: 10,
        ),
        CodeSubmitted(
          challengeId: 'evocation_fizzbuzz',
          result: CodeSubmitResult.pass,
        ),
        TerminalClosed(),
        DoorUnlocked(doorX: 20, doorY: 5),
        PlayerLeftProximity(playerId: 'user_2'),
        BotLeft(),
        LiveKitDisconnected(),
        RoomLeft(roomId: 'r1'),
        UserSignedOut(),
      ]);

      expect(captured.length, 17);

      // Verify session boundaries.
      expect(captured.first, isA<UserSignedIn>());
      expect(captured.last, isA<UserSignedOut>());

      // Verify type sequence tells a coherent story.
      final typeSequence =
          captured.map((e) => e.toJson()['type'] as String).toList();
      expect(typeSequence, [
        'user_signed_in',
        'avatar_selected',
        'room_joined',
        'livekit_connected',
        'media_enabled',
        'bot_joined',
        'player_moved',
        'player_entered_proximity',
        'terminal_opened',
        'code_submitted',
        'terminal_closed',
        'door_unlocked',
        'player_left_proximity',
        'bot_left',
        'livekit_disconnected',
        'room_left',
        'user_signed_out',
      ]);
    });

    test('map editing session sequence', () {
      dispatch([
        MapEditorEntered(mapId: 'm1', mapName: 'Test Map'),
        MapEdited(action: MapEditAction.paintTile, x: 5, y: 5),
        MapEdited(action: MapEditAction.paintWall, x: 6, y: 5),
        MapEdited(action: MapEditAction.paintTerrain, x: 7, y: 5),
        MapEdited(action: MapEditAction.undo, x: 7, y: 5),
        MapEdited(action: MapEditAction.redo, x: 7, y: 5),
        MapEdited(action: MapEditAction.eraseWall, x: 6, y: 5),
        MapEdited(action: MapEditAction.eraseTerrain, x: 7, y: 5),
        MapEdited(action: MapEditAction.paintTileRef, x: 8, y: 5),
        RoomMapSaved(roomId: 'r1', roomName: 'Test Map'),
        MapEditorExited(applied: true),
      ]);

      expect(captured.length, 11);
      expect(captured.first, isA<MapEditorEntered>());
      expect(captured.last, isA<MapEditorExited>());

      // All 8 MapEditAction variants are represented.
      final actions = captured
          .whereType<MapEdited>()
          .map((e) => e.action)
          .toSet();
      expect(actions, MapEditAction.values.toSet());
    });
  });
}
