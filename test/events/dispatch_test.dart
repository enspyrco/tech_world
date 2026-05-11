import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

void main() {
  tearDown(clearSinks);

  group('dispatch', () {
    test('empty events list is a no-op', () async {
      var called = false;
      registerSink((_) => called = true);
      dispatch([]);
      expect(called, isFalse);
    });

    test('fans event to all registered sync sinks', () {
      final received = <AppEvent>[];
      registerSink(received.add);
      registerSink(received.add);

      final event = DoorUnlocked(doorX: 5, doorY: 10);
      dispatch([event]);

      expect(received, hasLength(2));
      expect(received.first, same(event));
      expect(received.last, same(event));
    });

    test('fans event to async sinks in order', () async {
      final order = <String>[];
      registerAsyncSink((e) async {
        order.add('first');
      });
      registerAsyncSink((e) async {
        order.add('second');
      });

      dispatch([DoorUnlocked(doorX: 0, doorY: 0)]);
      expect(order, ['first', 'second']);
    });

    test('sync sinks run before async sinks', () async {
      final order = <String>[];
      registerAsyncSink((e) async {
        order.add('async');
      });
      registerSink((e) {
        order.add('sync');
      });

      dispatch([DoorUnlocked(doorX: 0, doorY: 0)]);
      expect(order, ['sync', 'async']);
    });

    test('multiple events dispatch in order', () async {
      final received = <Type>[];
      registerSink((e) => received.add(e.runtimeType));

      dispatch([
        DoorUnlocked(doorX: 1, doorY: 2),
        BotSpoke(text: 'hello', context: BotSpokeContext.group),
      ]);

      expect(received, [DoorUnlocked, BotSpoke]);
    });

    test('no sinks registered does not throw', () async {
      // dispatch with no sinks — must not throw.
      dispatch([DoorUnlocked(doorX: 0, doorY: 0)]);
    });

    test('clearSinks removes all sinks', () async {
      var called = false;
      registerSink((_) => called = true);
      clearSinks();

      dispatch([DoorUnlocked(doorX: 0, doorY: 0)]);
      expect(called, isFalse);
    });
  });

  group('event types', () {
    test('DoorUnlocked carries coordinates', () {
      final event = DoorUnlocked(doorX: 3, doorY: 7);
      expect(event.doorX, 3);
      expect(event.doorY, 7);
      expect(event.timestamp, isNotNull);
    });

    test('BotSpoke carries text and context', () {
      final event =
          BotSpoke(text: 'hello wizard', context: BotSpokeContext.help);
      expect(event.text, 'hello wizard');
      expect(event.context, BotSpokeContext.help);
    });

    test('WordLearned carries wordId and challengeId', () {
      final event = WordLearned(
        wordId: WordId.ignis,
        challengeId: PromptChallengeId.evocationFizzbuzz,
      );
      expect(event.wordId, WordId.ignis);
      expect(event.challengeId, PromptChallengeId.evocationFizzbuzz);
    });

    test('ChallengeCompleted carries wire-format challengeId', () {
      final event =
          ChallengeCompleted(challengeId: 'evocation_fizzbuzz');
      expect(event.challengeId, 'evocation_fizzbuzz');
    });

    test('timestamp defaults to now', () {
      final before = DateTime.now();
      final event = DoorUnlocked(doorX: 0, doorY: 0);
      final after = DateTime.now();

      expect(event.timestamp.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue);
      expect(event.timestamp.isBefore(after.add(const Duration(seconds: 1))),
          isTrue);
    });

    test('timestamp can be overridden', () {
      final fixed = DateTime(2026, 5, 8, 12, 0);
      final event = DoorUnlocked(doorX: 0, doorY: 0, timestamp: fixed);
      expect(event.timestamp, fixed);
    });

    test('exhaustive switch over AppEvent', () {
      // Compile-time proof that all variants are handled. If a new
      // variant is added without updating this switch, the analyzer
      // will report a missing case.
      final event = DoorUnlocked(doorX: 0, doorY: 0) as AppEvent;
      final label = switch (event) {
        WordLearned() => 'word',
        ChallengeCompleted() => 'challenge',
        SpellCastFailed() => 'spell_failed',
        DoorUnlocked() => 'door',
        PlayerMoved() => 'moved',
        TerminalOpened() => 'terminal_open',
        TerminalClosed() => 'terminal_close',
        AvatarSelected() => 'avatar',
        MapEditorEntered() => 'editor_enter',
        MapEditorExited() => 'editor_exit',
        RoomJoined() => 'room_join',
        RoomLeft() => 'room_leave',
        RoomCreated() => 'room_create',
        RoomMapSaved() => 'room_save',
        RoomDeleted() => 'room_delete',
        UserSignedIn() => 'sign_in',
        UserSignedOut() => 'sign_out',
        ProfileUpdated() => 'profile',
        CodeSubmitted() => 'code_submit',
        MapEdited() => 'map_edit',
        PlayerEnteredProximity() => 'prox_enter',
        PlayerLeftProximity() => 'prox_leave',
        BotJoined() => 'bot_join',
        BotLeft() => 'bot_leave',
        ScreenShareToggled() => 'screen_share',
        LiveKitConnected() => 'lk_connect',
        LiveKitDisconnected() => 'lk_disconnect',
        HelpRequested() => 'help_req',
        MediaEnabled() => 'media',
        RemoteDoorUnlocked() => 'remote_door',
        GroupMessageSent() => 'group_msg',
        DmSent() => 'dm',
        BotSpoke() => 'bot',
        AppLogRecord() => 'log',
      };
      expect(label, 'door');
    });
  });
}
