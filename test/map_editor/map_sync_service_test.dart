import 'dart:async';
import 'dart:convert';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:tech_world/avatar/avatar.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/player_path.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';
import 'package:tech_world/map_editor/map_sync_service.dart';

void main() {
  late FakeLiveKitService fakeLiveKit;
  late MapEditorState state;
  late MapSyncService syncService;

  setUp(() {
    fakeLiveKit = FakeLiveKitService();
    state = MapEditorState();
    syncService = MapSyncService(
      liveKitService: fakeLiveKit,
      editorState: state,
      localPlayerId: 'alice',
    );
  });

  tearDown(() {
    syncService.dispose();
  });

  group('local edits', () {
    test('paintTile publishes edit batch', () async {
      state.setTool(EditorTool.barrier);
      syncService.paintTile(5, 10);

      // Wait for async publish.
      await Future.delayed(Duration.zero);

      expect(state.tileAt(5, 10), TileType.barrier);
      expect(fakeLiveKit.publishedMessages, hasLength(1));

      final msg = fakeLiveKit.publishedMessages.first;
      expect(msg['topic'], 'map-edit');
      final payload = msg['payload'] as Map<String, dynamic>;
      expect(payload['type'], 'edit');
      expect(payload['playerId'], 'alice');
      expect((payload['ops'] as List).length, 1);
    });

    test('paintTile skips no-op edits', () async {
      // Painting open on an already open cell should not publish.
      state.setTool(EditorTool.eraser);
      syncService.paintTile(5, 10);

      await Future.delayed(Duration.zero);
      expect(fakeLiveKit.publishedMessages, isEmpty);
    });

    test('paintTileRef publishes floor layer edit', () async {
      state.setActiveLayer(ActiveLayer.floor);
      state.setTileBrush(
        const TileRef(tilesetId: 'test', tileIndex: 42),
        columns: 32,
      );
      syncService.paintTileRef(5, 10);

      await Future.delayed(Duration.zero);

      expect(state.floorLayerData.tileAt(5, 10), isNotNull);
      expect(fakeLiveKit.publishedMessages, hasLength(1));

      final payload =
          fakeLiveKit.publishedMessages.first['payload'] as Map<String, dynamic>;
      final ops = payload['ops'] as List;
      expect(ops.length, 1);
      expect(ops[0]['layer'], 'floor');
    });
  });

  group('remote edits', () {
    test('applies remote structure edit', () async {
      fakeLiveKit.simulateMapEdit({
        'type': 'edit',
        'playerId': 'bob',
        'counter': 1,
        'ops': [
          {
            'x': 3,
            'y': 4,
            'layer': 'structure',
            'new': 'barrier',
          }
        ],
      });

      // Allow stream event to propagate.
      await Future.delayed(Duration.zero);

      expect(state.tileAt(3, 4), TileType.barrier);
    });

    test('applies remote floor tile edit', () async {
      fakeLiveKit.simulateMapEdit({
        'type': 'edit',
        'playerId': 'bob',
        'counter': 1,
        'ops': [
          {
            'x': 5,
            'y': 6,
            'layer': 'floor',
            'new': {'tilesetId': 'ext_terrains', 'tileIndex': 105},
          }
        ],
      });

      await Future.delayed(Duration.zero);

      final ref = state.floorLayerData.tileAt(5, 6);
      expect(ref, isNotNull);
      expect(ref!.tilesetId, 'ext_terrains');
      expect(ref.tileIndex, 105);
    });

    test('ignores own messages', () async {
      // Simulate a message from ourselves (alice).
      fakeLiveKit.simulateMapEditFrom('alice', {
        'type': 'edit',
        'playerId': 'alice',
        'counter': 99,
        'ops': [
          {
            'x': 0,
            'y': 0,
            'layer': 'structure',
            'new': 'barrier',
          }
        ],
      });

      await Future.delayed(Duration.zero);

      // Should NOT be applied (we already applied locally).
      expect(state.tileAt(0, 0), TileType.open);
    });

    test('LWW resolution: higher counter wins', () async {
      // Local edit at counter 1.
      state.setTool(EditorTool.barrier);
      syncService.paintTile(5, 5);

      await Future.delayed(Duration.zero);
      expect(state.tileAt(5, 5), TileType.barrier);

      // Remote edit at higher counter erases it.
      fakeLiveKit.simulateMapEdit({
        'type': 'edit',
        'playerId': 'bob',
        'counter': 100,
        'ops': [
          {
            'x': 5,
            'y': 5,
            'layer': 'structure',
            'new': null,
          }
        ],
      });

      await Future.delayed(Duration.zero);
      expect(state.tileAt(5, 5), TileType.open);
    });

    test('LWW resolution: lower counter loses', () async {
      // Local edit at counter 1.
      state.setTool(EditorTool.barrier);
      syncService.paintTile(5, 5);

      await Future.delayed(Duration.zero);
      expect(state.tileAt(5, 5), TileType.barrier);

      // Remote edit at lower counter is ignored.
      fakeLiveKit.simulateMapEdit({
        'type': 'edit',
        'playerId': 'bob',
        'counter': 0,
        'ops': [
          {
            'x': 5,
            'y': 5,
            'layer': 'structure',
            'new': null,
          }
        ],
      });

      await Future.delayed(Duration.zero);
      expect(state.tileAt(5, 5), TileType.barrier);
    });
  });

  group('undo/redo', () {
    test('undo reverts and publishes', () async {
      state.setTool(EditorTool.barrier);
      syncService.paintTile(5, 5);
      await Future.delayed(Duration.zero);
      expect(state.tileAt(5, 5), TileType.barrier);

      fakeLiveKit.publishedMessages.clear();
      syncService.undo();
      await Future.delayed(Duration.zero);

      expect(state.tileAt(5, 5), TileType.open);
      expect(fakeLiveKit.publishedMessages, hasLength(1));
    });

    test('redo re-applies and publishes', () async {
      state.setTool(EditorTool.barrier);
      syncService.paintTile(5, 5);
      await Future.delayed(Duration.zero);

      syncService.undo();
      await Future.delayed(Duration.zero);
      expect(state.tileAt(5, 5), TileType.open);

      fakeLiveKit.publishedMessages.clear();
      syncService.redo();
      await Future.delayed(Duration.zero);

      expect(state.tileAt(5, 5), TileType.barrier);
      expect(fakeLiveKit.publishedMessages, hasLength(1));
    });

    test('canUndo/canRedo state', () {
      expect(syncService.canUndo, isFalse);
      expect(syncService.canRedo, isFalse);

      state.setTool(EditorTool.barrier);
      syncService.paintTile(5, 5);
      expect(syncService.canUndo, isTrue);
      expect(syncService.canRedo, isFalse);

      syncService.undo();
      expect(syncService.canUndo, isFalse);
      expect(syncService.canRedo, isTrue);

      syncService.redo();
      expect(syncService.canUndo, isTrue);
      expect(syncService.canRedo, isFalse);
    });

    test('undoRedoChanged notifier fires', () async {
      var changeCount = 0;
      syncService.undoRedoChanged.addListener(() => changeCount++);

      state.setTool(EditorTool.barrier);
      syncService.paintTile(5, 5);
      expect(changeCount, 1);

      syncService.undo();
      expect(changeCount, 2);

      syncService.redo();
      expect(changeCount, 3);
    });
  });

  group('late-join sync', () {
    test('sync request is published', () async {
      // Don't actually wait 5 seconds — just verify the request is sent.
      unawaited(syncService.requestSync());
      await Future.delayed(Duration.zero);

      final syncMessages = fakeLiveKit.publishedMessages
          .where((m) => m['topic'] == 'map-edit-sync')
          .toList();
      expect(syncMessages, hasLength(1));

      final payload = syncMessages.first['payload'] as Map<String, dynamic>;
      expect(payload['type'], 'sync-request');
      expect(payload['playerId'], 'alice');
    });

    test('responds to sync request from other player', () async {
      // Set up some state first.
      state.setTool(EditorTool.barrier);
      syncService.paintTile(2, 3);
      await Future.delayed(Duration.zero);
      fakeLiveKit.publishedMessages.clear();

      // Simulate a sync request from bob.
      fakeLiveKit.simulateMapSync({
        'type': 'sync-request',
        'playerId': 'bob',
      }, senderId: 'bob');

      await Future.delayed(Duration.zero);

      final syncMessages = fakeLiveKit.publishedMessages
          .where((m) => m['topic'] == 'map-edit-sync')
          .toList();
      expect(syncMessages, hasLength(1));

      final payload = syncMessages.first['payload'] as Map<String, dynamic>;
      expect(payload['type'], 'sync-response');
      // Should contain the barrier we painted.
      final structure = payload['structure'] as List;
      expect(
        structure.any((e) => e['x'] == 2 && e['y'] == 3 && e['v'] == 'barrier'),
        isTrue,
      );
    });
  });

  group('wall sync', () {
    test('paintWall publishes wall + structure + object ops', () async {
      state.setTool(EditorTool.wall);
      syncService.paintWall(5, 10);

      await Future.delayed(Duration.zero);

      expect(state.tileAt(5, 10), TileType.barrier);
      expect(state.isWallAt(5, 10), isTrue);
      expect(fakeLiveKit.publishedMessages, hasLength(1));

      final payload =
          fakeLiveKit.publishedMessages.first['payload'] as Map<String, dynamic>;
      final ops = payload['ops'] as List;

      // Should have at least a walls op and a structure op.
      final wallOps = ops.where((o) => o['layer'] == 'walls').toList();
      final structureOps = ops.where((o) => o['layer'] == 'structure').toList();
      expect(wallOps, isNotEmpty, reason: 'should include wall layer ops');
      expect(structureOps, isNotEmpty, reason: 'should include structure ops');

      // Wall op should carry the style ID.
      expect(wallOps.first['new'], state.wallStyle);
    });

    test('remote wall op updates local walls and object layer', () async {
      final styleId = state.wallStyle;

      fakeLiveKit.simulateMapEdit({
        'type': 'edit',
        'playerId': 'bob',
        'counter': 1,
        'ops': [
          {
            'x': 3,
            'y': 4,
            'layer': 'walls',
            'new': styleId,
          },
          {
            'x': 3,
            'y': 4,
            'layer': 'structure',
            'new': 'barrier',
          },
        ],
      });

      await Future.delayed(Duration.zero);

      expect(state.isWallAt(3, 4), isTrue);
      expect(state.wallStyleAt(3, 4), styleId);
      expect(state.tileAt(3, 4), TileType.barrier);
    });

    test('wall neighbor cascade: adjacent wall changes bitmask', () async {
      state.setTool(EditorTool.wall);

      // Paint first wall.
      syncService.paintWall(5, 10);
      await Future.delayed(Duration.zero);
      fakeLiveKit.publishedMessages.clear();

      // Paint adjacent wall to the east — should produce ops for both cells.
      syncService.paintWall(6, 10);
      await Future.delayed(Duration.zero);

      expect(fakeLiveKit.publishedMessages, hasLength(1));
      final payload =
          fakeLiveKit.publishedMessages.first['payload'] as Map<String, dynamic>;
      final ops = payload['ops'] as List;

      // Should have object layer ops for both (5,10) and (6,10) since
      // wall at (5,10) now has an east neighbor and its bitmask changed.
      final objectOps = ops.where((o) => o['layer'] == 'objects').toList();
      final affectedPositions = objectOps
          .map((o) => (o['x'] as int, o['y'] as int))
          .toSet();
      expect(affectedPositions, contains((5, 10)),
          reason: 'existing wall should get updated object tile');
      expect(affectedPositions, contains((6, 10)),
          reason: 'new wall should get object tile');
    });

    test('snapshot includes wall data', () async {
      state.setTool(EditorTool.wall);
      syncService.paintWall(2, 3);
      await Future.delayed(Duration.zero);
      fakeLiveKit.publishedMessages.clear();

      // Simulate a sync request from bob.
      fakeLiveKit.simulateMapSync({
        'type': 'sync-request',
        'playerId': 'bob',
      }, senderId: 'bob');

      await Future.delayed(Duration.zero);

      final syncMessages = fakeLiveKit.publishedMessages
          .where((m) => m['topic'] == 'map-edit-sync')
          .toList();
      expect(syncMessages, hasLength(1));

      final payload = syncMessages.first['payload'] as Map<String, dynamic>;
      final walls = payload['walls'] as List;
      expect(
        walls.any(
            (e) => e['x'] == 2 && e['y'] == 3 && e['s'] == state.wallStyle),
        isTrue,
        reason: 'snapshot should include wall with style ID',
      );

      // Should also include the wall in structure.
      final structure = payload['structure'] as List;
      expect(
        structure.any((e) => e['x'] == 2 && e['y'] == 3 && e['v'] == 'barrier'),
        isTrue,
      );
    });

    test('eraseWall removes wall and publishes ops', () async {
      state.setTool(EditorTool.wall);
      syncService.paintWall(5, 10);
      await Future.delayed(Duration.zero);
      fakeLiveKit.publishedMessages.clear();

      state.setTool(EditorTool.eraser);
      syncService.eraseWall(5, 10);
      await Future.delayed(Duration.zero);

      expect(state.isWallAt(5, 10), isFalse);
      expect(fakeLiveKit.publishedMessages, hasLength(1));

      final payload =
          fakeLiveKit.publishedMessages.first['payload'] as Map<String, dynamic>;
      final ops = payload['ops'] as List;

      final wallOps = ops.where((o) => o['layer'] == 'walls').toList();
      expect(wallOps, isNotEmpty);
      // Wall op should erase (null new value).
      expect(wallOps.first['new'], isNull);
    });

    test('doorway lintel: cap tiles sync above gap between walls', () async {
      state.setTool(EditorTool.wall);

      // Paint two walls with a 2-cell gap between them (doorway).
      syncService.paintWall(5, 10);
      await Future.delayed(Duration.zero);
      fakeLiveKit.publishedMessages.clear();

      syncService.paintWall(8, 10);
      await Future.delayed(Duration.zero);

      final payload =
          fakeLiveKit.publishedMessages.first['payload'] as Map<String, dynamic>;
      final ops = payload['ops'] as List;

      // Lintel caps should appear at (6,9) and (7,9) — above the gap cells.
      final objectOps = ops.where((o) => o['layer'] == 'objects').toList();
      final objectPositions = objectOps
          .map((o) => (o['x'] as int, o['y'] as int))
          .toSet();

      expect(objectPositions, contains((6, 9)),
          reason: 'lintel cap above first gap cell');
      expect(objectPositions, contains((7, 9)),
          reason: 'lintel cap above second gap cell');
    });
  });
}

// ---------------------------------------------------------------------------
// Minimal FakeLiveKitService for MapSyncService testing
// ---------------------------------------------------------------------------

class FakeLiveKitService implements LiveKitService {
  bool connected = true;
  final List<Map<String, dynamic>> publishedMessages = [];
  final _dataReceivedController =
      StreamController<DataChannelMessage>.broadcast();

  void simulateMapEdit(Map<String, dynamic> json) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: json['playerId'] as String,
      topic: 'map-edit',
      data: utf8.encode(jsonEncode(json)),
    ));
  }

  void simulateMapEditFrom(String senderId, Map<String, dynamic> json) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: senderId,
      topic: 'map-edit',
      data: utf8.encode(jsonEncode(json)),
    ));
  }

  void simulateMapSync(Map<String, dynamic> json, {String? senderId}) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: senderId,
      topic: 'map-edit-sync',
      data: utf8.encode(jsonEncode(json)),
    ));
  }

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
  Stream<void> get mapInfoRequested => const Stream.empty();

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
  Map<String, RemoteParticipant> get remoteParticipants => {};

  @override
  Stream<RemoteParticipant> get participantJoined => const Stream.empty();

  @override
  Stream<RemoteParticipant> get participantLeft => const Stream.empty();

  @override
  Stream<(Participant, bool)> get speakingChanged => const Stream.empty();

  @override
  Stream<(Participant, VideoTrack)> get trackSubscribed =>
      const Stream.empty();

  @override
  Stream<(Participant, VideoTrack)> get trackUnsubscribed =>
      const Stream.empty();

  @override
  Stream<LocalTrackPublication> get localTrackPublished =>
      const Stream.empty();

  @override
  Stream<String?> get connectionLost => const Stream.empty();

  @override
  Stream<PlayerPath> get positionReceived => const Stream.empty();

  @override
  Stream<AvatarUpdate> get avatarReceived => const Stream.empty();

  @override
  Room? get room => null;

  @override
  LocalParticipant? get localParticipant => null;

  @override
  bool get isScreenShareEnabled => false;

  @override
  Future<ConnectionResult> connect() async => ConnectionResult.connected;

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
  void setParticipantAudioEnabled(String identity, bool enabled) {}

  @override
  Participant? getParticipant(String identity) => null;

  @override
  Future<void> dispose() async {
    _dataReceivedController.close();
  }
}
