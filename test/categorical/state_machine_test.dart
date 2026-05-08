import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart'
    show
        LocalParticipant,
        LocalTrackPublication,
        Participant,
        RemoteParticipant,
        Room,
        ScreenShareCaptureOptions,
        VideoTrack;
import 'package:tech_world/avatar/avatar.dart';
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/player_path.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/widgets/wire_states.dart';

Future<void> pumpEventQueue() => Future<void>.delayed(Duration.zero);

void main() {
  group('BotStatus state machine (via ChatService)', () {
    late _FakeLiveKitService fakeLiveKit;
    late ChatService chatService;

    setUp(() {
      fakeLiveKit = _FakeLiveKitService();
    });

    tearDown(() {
      chatService.dispose();
    });

    test('absent → sendMessage is blocked (returns null, stays absent)',
        () async {
      chatService = ChatService(liveKitService: fakeLiveKit);
      // Bot starts absent — don't call setBotStatusForTest.
      expect(chatService.botStatus.value, BotStatus.absent);

      final result = await chatService.sendMessage('Hello');

      expect(result, isNull, reason: 'Guard should return null');
      expect(chatService.botStatus.value, BotStatus.absent,
          reason: 'Must NOT transition to thinking when absent');
      expect(fakeLiveKit.publishedMessages, isEmpty,
          reason: 'No message should be published to LiveKit');
    });

    test('idle → sendMessage transitions to thinking', () async {
      chatService = ChatService(liveKitService: fakeLiveKit);
      chatService.setBotStatusForTest(BotStatus.idle);
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Hello'));
      await pumpEventQueue();

      expect(chatService.botStatus.value, BotStatus.thinking);
    });

    test('thinking → idle on bot response', () async {
      chatService = ChatService(liveKitService: fakeLiveKit);
      chatService.setBotStatusForTest(BotStatus.idle);
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Hello'));
      await pumpEventQueue();
      expect(chatService.botStatus.value, BotStatus.thinking);

      // Simulate bot response.
      final messageId =
          fakeLiveKit.publishedMessages.first['payload']['id'] as String;
      fakeLiveKit.simulateResponse({
        'text': 'Hi!',
        'messageId': messageId,
      });
      await pumpEventQueue();

      expect(chatService.botStatus.value, BotStatus.idle);
    });

    test('thinking → absent via markBotAbsent (external interrupt)', () async {
      chatService = ChatService(liveKitService: fakeLiveKit);
      chatService.setBotStatusForTest(BotStatus.idle);
      fakeLiveKit.connected = true;

      // Send message — enters thinking.
      unawaited(chatService.sendMessage('Hello'));
      await pumpEventQueue();
      expect(chatService.botStatus.value, BotStatus.thinking);

      // Bot leaves the room while thinking — external interrupt.
      chatService.markBotAbsent();
      expect(chatService.botStatus.value, BotStatus.absent,
          reason: 'markBotAbsent must override thinking state');
    });

    test('markBotAbsent forces absent regardless of current state', () async {
      chatService = ChatService(liveKitService: fakeLiveKit);
      chatService.setBotStatusForTest(BotStatus.idle);

      chatService.markBotAbsent();
      expect(chatService.botStatus.value, BotStatus.absent);
    });

    test('botStatus is exposed as read-only ValueListenable', () {
      chatService = ChatService(liveKitService: fakeLiveKit);

      expect(chatService.botStatus, isA<ValueListenable<BotStatus>>());
      expect(chatService.botStatus.value, BotStatus.absent);
    });
  });

  group('WireStatus state machine (via WireStates)', () {
    test('all wires start in pending state', () {
      final states = WireStates();
      for (final wire in Wire.values) {
        expect(states[wire], WireStatus.pending);
      }
    });

    test('start transitions pending → active', () {
      final states = WireStates();
      states.start(Wire.tilesets);
      expect(states[Wire.tilesets], WireStatus.active);
      expect(states[Wire.server], WireStatus.pending);
    });

    test('complete is reachable from any state', () {
      final states = WireStates();
      // pending → complete (skip active).
      states.complete(Wire.tilesets);
      expect(states[Wire.tilesets], WireStatus.complete);

      // active → complete.
      states.start(Wire.server);
      states.complete(Wire.server);
      expect(states[Wire.server], WireStatus.complete);
    });

    test('error is reachable from any state', () {
      final states = WireStates();
      states.error(Wire.camera);
      expect(states[Wire.camera], WireStatus.error);

      states.start(Wire.chat);
      states.error(Wire.chat);
      expect(states[Wire.chat], WireStatus.error);
    });

    test('allComplete requires every wire to reach complete', () {
      final states = WireStates();
      expect(states.allComplete, isFalse);

      for (final wire in Wire.values) {
        if (wire != Wire.gameReady) states.complete(wire);
      }
      expect(states.allComplete, isFalse,
          reason: 'One pending wire blocks allComplete');

      states.complete(Wire.gameReady);
      expect(states.allComplete, isTrue);
    });

    test('allComplete is false if any wire has error', () {
      final states = WireStates();
      for (final wire in Wire.values) {
        states.complete(wire);
      }
      expect(states.allComplete, isTrue);

      states.error(Wire.server);
      expect(states.allComplete, isFalse);
    });

    test('wires are independent — one error does not affect others', () {
      final states = WireStates();
      states.start(Wire.tilesets);
      states.start(Wire.server);
      states.error(Wire.server);

      expect(states[Wire.tilesets], WireStatus.active);
      expect(states[Wire.server], WireStatus.error);
      expect(states[Wire.camera], WireStatus.pending);
    });

    test('every transition notifies listeners', () {
      final states = WireStates();
      var count = 0;
      states.addListener(() => count++);

      states.start(Wire.tilesets);
      states.complete(Wire.tilesets);
      states.error(Wire.server);

      expect(count, 3);
    });
  });
}

/// Minimal fake for testing ChatService's BotStatus transitions.
/// Mirrors the `FakeLiveKitService` in `test/chat/chat_service_test.dart`.
class _FakeLiveKitService implements LiveKitService {
  bool connected = true;
  final List<Map<String, dynamic>> publishedMessages = [];
  final _dataReceivedController =
      StreamController<DataChannelMessage>.broadcast();

  @override
  bool get isConnected => connected;
  @override
  String get userId => 'test-user-id';
  @override
  String get displayName => 'Test User';
  @override
  String get roomName => 'tech-world';

  @override
  Stream<DataChannelMessage> get dataReceived =>
      _dataReceivedController.stream;

  @override
  Future<void> publishJson(
    Map<String, dynamic> json, {
    bool reliable = true,
    List<String>? destinationIdentities,
    String? topic,
  }) async {
    publishedMessages.add({
      'payload': json,
      'topic': topic,
      'destinationIdentities': destinationIdentities,
    });
  }

  void simulateResponse(Map<String, dynamic> response) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: 'bot-claude',
      topic: 'chat-response',
      data: utf8.encode(jsonEncode(response)),
    ));
  }

  // -- Stubs for unused LiveKitService members --

  final _participantJoinedController =
      StreamController<RemoteParticipant>.broadcast();
  final _participantLeftController =
      StreamController<RemoteParticipant>.broadcast();
  final _speakingChangedController =
      StreamController<(Participant, bool)>.broadcast();
  final _trackSubscribedController =
      StreamController<(Participant, VideoTrack)>.broadcast();
  final _trackUnsubscribedController =
      StreamController<(Participant, VideoTrack)>.broadcast();
  final _localTrackPublishedController =
      StreamController<LocalTrackPublication>.broadcast();
  final _connectionLostController = StreamController<String?>.broadcast();

  @override
  Map<String, RemoteParticipant> get remoteParticipants => {};
  @override
  Stream<RemoteParticipant> get participantJoined =>
      _participantJoinedController.stream;
  @override
  Stream<RemoteParticipant> get participantLeft =>
      _participantLeftController.stream;
  @override
  Stream<(Participant, bool)> get speakingChanged =>
      _speakingChangedController.stream;
  @override
  Stream<(Participant, VideoTrack)> get trackSubscribed =>
      _trackSubscribedController.stream;
  @override
  Stream<(Participant, VideoTrack)> get trackUnsubscribed =>
      _trackUnsubscribedController.stream;
  @override
  Stream<LocalTrackPublication> get localTrackPublished =>
      _localTrackPublishedController.stream;
  @override
  Stream<String?> get connectionLost => _connectionLostController.stream;
  @override
  Stream<PlayerPath> get positionReceived => const Stream.empty();
  @override
  Stream<AvatarUpdate> get avatarReceived => const Stream.empty();
  @override
  Stream<void> get mapInfoRequested => const Stream.empty();
  @override
  Stream<String> get mapSwitchReceived => const Stream.empty();
  @override
  Stream<PositionHeartbeat> get positionHeartbeatReceived =>
      const Stream.empty();
  @override
  Room? get room => null;
  @override
  LocalParticipant? get localParticipant => null;
  @override
  bool get isScreenShareEnabled => false;
  @override
  Participant? getParticipant(String identity) => null;
  @override
  void setParticipantAudioEnabled(String identity, bool enabled) {}
  @override
  void startPositionHeartbeat(Point<int> Function() currentPosition) {}
  @override
  void stopPositionHeartbeat() {}
  @override
  Future<ConnectionResult> connect() async =>
      connected ? ConnectionResult.connected : ConnectionResult.roomFailed;
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> setCameraEnabled(bool enabled) async {}
  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}
  @override
  Future<void> setScreenShareEnabled(bool enabled,
      {ScreenShareCaptureOptions? options}) async {}
  @override
  Future<void> publishData(
    List<int> data, {
    bool reliable = true,
    List<String>? destinationIdentities,
    String? topic,
  }) async {}
  @override
  Future<void> publishMapInfo(GameMap map) async {}
  @override
  Future<void> publishMapSwitch(String mapId) async {}
  @override
  Future<void> publishPosition({
    required List<Vector2> points,
    required List<Direction> directions,
  }) async {}
  @override
  Future<void> publishTerminalActivity({
    required String action,
    String? challengeId,
    String? challengeTitle,
    String? challengeDescription,
    int? terminalX,
    int? terminalY,
  }) async {}
  @override
  Future<void> publishAvatar(Avatar avatar) async {}
  @override
  Future<DataChannelMessage?> sendPing({
    Duration timeout = const Duration(seconds: 5),
  }) async =>
      null;
  @override
  Future<void> dispose() async {
    _dataReceivedController.close();
    _participantJoinedController.close();
    _participantLeftController.close();
    _speakingChangedController.close();
    _trackSubscribedController.close();
    _trackUnsubscribedController.close();
    _localTrackPublishedController.close();
    _connectionLostController.close();
  }
}
