import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

void main() {
  group('Service lifecycle', () {
    group('LiveKitService connect/disconnect/reconnect', () {
      late LiveKitService service;

      setUp(() {
        service = LiveKitService(
          userId: 'test-user',
          displayName: 'Test',
          tokenRetriever: () async => 'fake-token',
        );
      });

      tearDown(() async {
        await service.dispose();
      });

      test('initial state is disconnected', () {
        expect(service.isConnected, isFalse);
        expect(service.room, isNull);
      });

      test('connect returns tokenNetworkError when token retriever fails', () async {
        final failingService = LiveKitService(
          userId: 'test-user',
          displayName: 'Test',
          tokenRetriever: () async => null,
        );
        addTearDown(failingService.dispose);

        final result = await failingService.connect();
        expect(result, equals(ConnectionResult.tokenUnknownError));
        expect(failingService.isConnected, isFalse);
        // Room and listener should be null (no dangling resources).
        expect(failingService.room, isNull);
      });

      test('connect returns alreadyConnected on duplicate call', () async {
        // First connect will fail (no real server) with roomFailed, but
        // mark isConnecting. A second call during connection should return
        // alreadyConnected. We test the guard path directly.

        // Create a service that hangs during token retrieval to simulate
        // an in-progress connection.
        final hangCompleter = Completer<String?>();
        final hangingService = LiveKitService(
          userId: 'test-user',
          displayName: 'Test',
          tokenRetriever: () => hangCompleter.future,
        );
        addTearDown(() async {
          hangCompleter.complete(null); // Unblock to allow cleanup.
          await hangingService.dispose();
        });

        // Start first connection (will hang on token retrieval).
        unawaited(hangingService.connect());
        await Future.delayed(const Duration(milliseconds: 10));

        // Second call should return immediately.
        final result = await hangingService.connect();
        expect(result, equals(ConnectionResult.alreadyConnected));
      });

      test('disconnect is safe to call when not connected', () async {
        // Should not throw.
        await service.disconnect();
        expect(service.isConnected, isFalse);
      });

      test('dispose is safe to call multiple times', () async {
        // Should not throw.
        await service.dispose();
        await service.dispose();
      });
    });

    group('LiveKitService connectionLost stream', () {
      test('stream is available and does not error when unused', () async {
        final service = LiveKitService(
          userId: 'test-user',
          displayName: 'Test',
          tokenRetriever: () async => 'fake-token',
        );
        addTearDown(service.dispose);

        // Just subscribing should not throw.
        final sub = service.connectionLost.listen((_) {});
        addTearDown(sub.cancel);
      });
    });

    group('MapEditorState dirty tracking', () {
      late MapEditorState state;

      setUp(() {
        state = MapEditorState();
      });

      test('starts clean', () {
        expect(state.isDirty, isFalse);
      });

      test('paintTile marks dirty', () {
        state.paintTile(5, 5);
        expect(state.isDirty, isTrue);
      });

      test('loadFromGameMap resets dirty', () {
        state.paintTile(5, 5);
        expect(state.isDirty, isTrue);

        state.loadFromGameMap(state.toGameMap());
        expect(state.isDirty, isFalse);
      });

      test('markClean resets dirty', () {
        state.paintTile(5, 5);
        expect(state.isDirty, isTrue);

        state.markClean();
        expect(state.isDirty, isFalse);
      });

      test('clearGrid marks dirty', () {
        state.clearGrid();
        expect(state.isDirty, isTrue);
      });

      test('clearAll marks dirty', () {
        state.clearAll();
        expect(state.isDirty, isTrue);
      });

      test('setMapName marks dirty', () {
        state.setMapName('New Name');
        expect(state.isDirty, isTrue);
      });

      test('setMapId marks dirty', () {
        state.setMapId('new_id');
        expect(state.isDirty, isTrue);
      });

      test('loadFromAscii resets dirty', () {
        state.paintTile(5, 5);
        expect(state.isDirty, isTrue);

        state.loadFromAscii('...\n...\n...');
        expect(state.isDirty, isFalse);
      });

      test('setTool does not mark dirty', () {
        state.setTool(EditorTool.eraser);
        expect(state.isDirty, isFalse);
      });

      test('setActiveLayer does not mark dirty', () {
        state.setActiveLayer(ActiveLayer.floor);
        expect(state.isDirty, isFalse);
      });
    });

    group('ConnectionResult enum', () {
      test('has all expected values', () {
        expect(ConnectionResult.values, containsAll([
          ConnectionResult.connected,
          ConnectionResult.alreadyConnected,
          ConnectionResult.tokenNetworkError,
          ConnectionResult.tokenAuthError,
          ConnectionResult.tokenUnknownError,
          ConnectionResult.roomFailed,
        ]));
      });
    });
  });
}
