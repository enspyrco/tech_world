import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:tech_world/chat/chat_message_repository.dart';
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/proximity/proximity_service.dart';
import 'package:tech_world/rooms/room_data.dart';
import 'package:tech_world/services/dreamfinder_client.dart';
import 'package:tech_world/spellbook/oracle_service.dart';
import 'package:tech_world/utils/locator.dart';

final _log = Logger('RoomSession');

/// Encapsulates the lifecycle of a room session: service creation, LiveKit
/// connection, reconnection on failure, and teardown.
///
/// Replaces the 10+ nullable fields and 3 lifecycle methods that previously
/// lived in `_MyAppState`. Owned as a single `RoomSession? _session` field.
///
/// Usage:
/// ```dart
/// _session = RoomSession.create(room: room, userId: userId, ...);
/// final result = await _session!.connect();
/// if (result == ConnectionResult.connected) { ... }
/// // Later:
/// await _session?.leave();
/// _session = null;
/// ```
class RoomSession {
  RoomSession._({
    required this.liveKitService,
    required this.chatService,
    required this.chatMessageRepository,
    required this.proximityService,
    required this.room,
    required this.userId,
    required this.displayName,
    required FirebaseFirestore firestore,
    required void Function() onStateChanged,
    required Future<void> Function() onReconnectWorld,
    required void Function() onRoomDeleted,
  })  : _firestore = firestore,
        _onStateChanged = onStateChanged,
        _onReconnectWorld = onReconnectWorld,
        _onRoomDeleted = onRoomDeleted;

  // --- Final fields (set at construction) ---

  final LiveKitService liveKitService;
  final ChatService chatService;
  final ChatMessageRepository chatMessageRepository;
  final ProximityService proximityService;
  final RoomData room;
  final String userId;
  final String displayName;
  final FirebaseFirestore _firestore;

  // --- Callbacks ---

  /// Triggers `setState` in the owning widget so the UI rebuilds.
  final void Function() _onStateChanged;

  /// Re-wires TechWorld's LiveKit subscriptions after a successful reconnect.
  /// Called with `await` so the game world is ready before media re-enables.
  final Future<void> Function() _onReconnectWorld;

  /// Fires when the Firestore room document goes from existing to
  /// non-existing — i.e. the host deleted the room while the user is in it.
  /// The owning widget is expected to surface a notice and call its leave
  /// flow; [leave] will cancel this subscription.
  final void Function() _onRoomDeleted;

  // --- Connection state (observable by UI) ---

  /// Whether the LiveKit connection has failed or been lost.
  final connectionFailed = ValueNotifier<bool>(false);

  /// Human-readable connection failure/reconnection message, or null.
  final connectionMessage = ValueNotifier<String?>(null);

  // --- Internal state ---

  bool _isReconnecting = false;
  StreamSubscription<String?>? _connectionLostSub;
  StreamSubscription<DocumentSnapshot>? _roomDeletionSub;
  OracleService? _oracleService;

  /// Set by [leave]; read after every `await` in [_handleConnectionLost] so
  /// a delayed reconnection that races with the user leaving the room can't
  /// mutate disposed services or notifiers.
  bool _disposed = false;

  /// Lazily-created oracle service for bot-mediated generation (voice cast,
  /// spell combos). Cached for the session so the request-sequence counter
  /// (`_seq`) disambiguates microsecond collisions across rebuilds.
  OracleService get oracleService =>
      _oracleService ??= OracleService(liveKit: liveKitService);

  // ---------------------------------------------------------------------------
  // Factory
  // ---------------------------------------------------------------------------

  /// Create services for a room and register them in the [Locator].
  ///
  /// Does not connect to LiveKit — call [connect] next. This separation lets
  /// callers interleave wire-state tracking between creation and connection
  /// (the overlay join path).
  static RoomSession create({
    required RoomData room,
    required String userId,
    required String displayName,
    required void Function() onStateChanged,
    required Future<void> Function() onReconnectWorld,
    required void Function() onRoomDeleted,
    @visibleForTesting ChatMessageRepository? chatMessageRepository,
    @visibleForTesting LiveKitService? liveKitService,
    @visibleForTesting FirebaseFirestore? firestore,
  }) {
    final liveKit = liveKitService ??
        LiveKitService(
          userId: userId,
          displayName: displayName,
          roomName: room.id,
        );
    final chatRepo = chatMessageRepository ?? ChatMessageRepository();
    final chat = ChatService(
      liveKitService: liveKit,
      repository: chatRepo,
      dreamfinderClient: DreamfinderClient(
        baseUrl: 'https://dreamfinder.imagineering.cc',
        apiKey: const String.fromEnvironment(
          'DREAMFINDER_API_KEY',
          defaultValue:
              '2aa0e9ab3207b197dc0d392fe6e35e8cbe8bfa78f72ce7f9',
        ),
      ),
    );
    final proximity = ProximityService();

    Locator.add<LiveKitService>(liveKit);
    Locator.add<ChatService>(chat);
    Locator.add<ProximityService>(proximity);

    return RoomSession._(
      liveKitService: liveKit,
      chatService: chat,
      chatMessageRepository: chatRepo,
      proximityService: proximity,
      room: room,
      userId: userId,
      displayName: displayName,
      firestore: firestore ?? FirebaseFirestore.instance,
      onStateChanged: onStateChanged,
      onReconnectWorld: onReconnectWorld,
      onRoomDeleted: onRoomDeleted,
    );
  }

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  /// Connect to LiveKit and start listening for connection loss.
  ///
  /// On failure, sets [connectionFailed] and [connectionMessage] so the UI
  /// can show a banner. Returns the [ConnectionResult] so callers can act on
  /// it (e.g. skip camera/mic setup on failure).
  Future<ConnectionResult> connect() async {
    _listenForRoomDeletion();
    final result = await liveKitService.connect();
    _log.info('LiveKit connection result for room ${room.id}: $result');

    if (result == ConnectionResult.connected) {
      _listenForConnectionLoss();
    } else if (result != ConnectionResult.alreadyConnected) {
      connectionFailed.value = true;
      connectionMessage.value = failureMessageFor(result);
    }
    return result;
  }

  /// Listen to the Firestore room document; fire [_onRoomDeleted] when the
  /// document disappears (host deleted the room while the user is inside).
  void _listenForRoomDeletion() {
    _roomDeletionSub?.cancel();
    _roomDeletionSub = _firestore
        .collection('rooms')
        .doc(room.id)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) {
        _log.info('Room ${room.id} was deleted');
        _onRoomDeleted();
      }
    });
  }

  /// Enable camera and microphone.
  Future<void> enableMedia() async {
    await Future.wait([
      liveKitService.setCameraEnabled(true),
      liveKitService.setMicrophoneEnabled(true),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Reconnection
  // ---------------------------------------------------------------------------

  void _listenForConnectionLoss() {
    _connectionLostSub?.cancel();
    _connectionLostSub =
        liveKitService.connectionLost.listen(_handleConnectionLost);
  }

  // Backoff schedule: 2s, 4s, 8s.
  static const _maxReconnectAttempts = 3;
  static const _reconnectDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];

  Future<void> _handleConnectionLost(String? reason) async {
    _log.warning('LiveKit connection lost: $reason');
    if (_isReconnecting || _disposed) return;
    _isReconnecting = true;

    // Show failure banner immediately.
    connectionFailed.value = true;
    connectionMessage.value = 'Connection lost — reconnecting…';
    botStatusNotifier.value = BotStatus.absent;
    _onStateChanged();

    // TechWorld's own connectionLost listener calls disconnectFromLiveKit(),
    // which clears its subscriptions and nulls its service reference. That
    // enables re-initialization when connectToLiveKit() is called again.

    try {
      for (int attempt = 0; attempt < _maxReconnectAttempts; attempt++) {
        final delay = _reconnectDelays[attempt];
        _log.info('Reconnect attempt ${attempt + 1}/$_maxReconnectAttempts '
            'in ${delay.inSeconds}s');
        connectionMessage.value = 'Connection lost — reconnecting '
            '(${attempt + 1}/$_maxReconnectAttempts)…';
        _onStateChanged();

        await Future.delayed(delay);
        // Bail if the user left during the delay — services and notifiers
        // are disposed and any further work would be use-after-free.
        if (_disposed) return;

        final result = await liveKitService.connect();
        if (_disposed) return;
        _log.info('Reconnection attempt ${attempt + 1} result: $result');

        if (result == ConnectionResult.connected) {
          await _onReconnectWorld();
          if (_disposed) return;
          _listenForConnectionLoss();
          await enableMedia();
          if (_disposed) return;

          connectionFailed.value = false;
          connectionMessage.value = null;
          _log.info('Reconnected successfully on attempt ${attempt + 1}');
          _onStateChanged();
          return;
        }

        // Auth errors won't resolve with retries — stop immediately.
        if (result == ConnectionResult.tokenAuthError) {
          _log.warning('Auth error — aborting reconnection');
          break;
        }
      }

      // All attempts exhausted or auth error.
      connectionMessage.value =
          'Video & chat unavailable — connection lost';
      _onStateChanged();
    } finally {
      _isReconnecting = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Error messages
  // ---------------------------------------------------------------------------

  /// Map a [ConnectionResult] to a human-readable failure message.
  static String failureMessageFor(ConnectionResult result) => switch (result) {
        ConnectionResult.tokenAuthError =>
          'Session expired — please sign in again',
        ConnectionResult.tokenNetworkError =>
          'Could not reach server — check your connection',
        ConnectionResult.roomFailed =>
          'Room connection failed — try again later',
        _ => 'Video & chat unavailable — connection failed',
      };

  // ---------------------------------------------------------------------------
  // Teardown
  // ---------------------------------------------------------------------------

  /// Leave the room — dispose services in dependency order.
  ///
  /// Disposal order: cancel reconnection listener, then consumers before
  /// producers (ChatService → ProximityService → LiveKitService).
  Future<void> leave() async {
    _disposed = true;
    _roomDeletionSub?.cancel();
    _roomDeletionSub = null;
    _connectionLostSub?.cancel();
    _connectionLostSub = null;
    _isReconnecting = false;

    chatService.dispose();
    proximityService.dispose();
    await liveKitService.dispose();
    _oracleService = null;

    connectionFailed.dispose();
    connectionMessage.dispose();

    Locator.remove<LiveKitService>();
    Locator.remove<ChatService>();
    Locator.remove<ProximityService>();
  }
}
