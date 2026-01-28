import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/player_path.dart';

/// Service that manages LiveKit room connection and participant tracking.
///
/// This service:
/// - Connects to LiveKit room automatically
/// - Tracks remote participants
/// - Exposes streams for participant join/leave events
/// - Manages local audio/video tracks
class LiveKitService {
  LiveKitService({
    required this.userId,
    required this.displayName,
    this.roomName = 'tech-world',
  });

  final String userId;
  final String displayName;
  final String roomName;

  // LiveKit server URL
  static const _serverUrl = 'wss://testing-g5wrpk39.livekit.cloud';

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  bool _isConnecting = false;
  bool _isConnected = false;

  // Stream controllers for participant events
  final _participantJoinedController =
      StreamController<RemoteParticipant>.broadcast();
  final _participantLeftController =
      StreamController<RemoteParticipant>.broadcast();
  final _speakingChangedController =
      StreamController<(Participant, bool)>.broadcast();
  final _trackSubscribedController =
      StreamController<(Participant, VideoTrack)>.broadcast();
  final _localTrackPublishedController =
      StreamController<LocalTrackPublication>.broadcast();
  final _dataReceivedController =
      StreamController<DataChannelMessage>.broadcast();

  /// Stream of participants that joined the room
  Stream<RemoteParticipant> get participantJoined =>
      _participantJoinedController.stream;

  /// Stream of participants that left the room
  Stream<RemoteParticipant> get participantLeft =>
      _participantLeftController.stream;

  /// Stream of speaking state changes (participant, isSpeaking)
  Stream<(Participant, bool)> get speakingChanged =>
      _speakingChangedController.stream;

  /// Stream of video track subscription events (participant, videoTrack)
  Stream<(Participant, VideoTrack)> get trackSubscribed =>
      _trackSubscribedController.stream;

  /// Stream of local track publication events (fires when camera/mic is published)
  Stream<LocalTrackPublication> get localTrackPublished =>
      _localTrackPublishedController.stream;

  /// Stream of data channel messages received from other participants
  Stream<DataChannelMessage> get dataReceived => _dataReceivedController.stream;

  /// Stream of player position updates received from other participants.
  ///
  /// Filters dataReceived for 'position' topic and parses into PlayerPath.
  Stream<PlayerPath> get positionReceived => dataReceived
      .where((msg) => msg.topic == 'position')
      .map((msg) {
        final json = msg.json;
        if (json == null) return null;
        return _parsePlayerPath(json);
      })
      .where((path) => path != null)
      .cast<PlayerPath>();

  PlayerPath? _parsePlayerPath(Map<String, dynamic> json) {
    try {
      final playerId = json['playerId'] as String?;
      final pointsJson = json['points'] as List<dynamic>?;
      final directionsJson = json['directions'] as List<dynamic>?;

      if (playerId == null || pointsJson == null || directionsJson == null) {
        return null;
      }

      final points = pointsJson
          .map((p) => Vector2(
                (p['x'] as num).toDouble(),
                (p['y'] as num).toDouble(),
              ))
          .toList();

      final directions = directionsJson
          .map((d) => Direction.values.asNameMap()[d] ?? Direction.none)
          .toList();

      return PlayerPath(
        playerId: playerId,
        largeGridPoints: points,
        directions: directions,
      );
    } catch (e) {
      debugPrint('LiveKitService: Failed to parse player path: $e');
      return null;
    }
  }

  /// Current room instance
  Room? get room => _room;

  /// Whether connected to LiveKit
  bool get isConnected => _isConnected;

  /// Local participant
  LocalParticipant? get localParticipant => _room?.localParticipant;

  /// All remote participants
  Map<String, RemoteParticipant> get remoteParticipants =>
      _room?.remoteParticipants ?? {};

  /// Connect to the LiveKit room
  Future<bool> connect() async {
    if (_isConnecting || _isConnected) {
      debugPrint('LiveKitService: Already connecting or connected');
      return _isConnected;
    }

    _isConnecting = true;
    debugPrint('LiveKitService: Connecting to LiveKit...');

    try {
      // Get token from Firebase Function
      final token = await _retrieveToken();
      if (token == null) {
        debugPrint('LiveKitService: Failed to retrieve token');
        _isConnecting = false;
        return false;
      }

      // Create room with options
      _room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultCameraCaptureOptions: CameraCaptureOptions(
            maxFrameRate: 30,
            params: VideoParametersPresets.h540_169,
          ),
          defaultAudioCaptureOptions: AudioCaptureOptions(
            noiseSuppression: true,
            echoCancellation: true,
            autoGainControl: true,
          ),
        ),
      );

      // Set up event listener
      _listener = _room!.createListener();
      _setupListeners();

      // Connect to room
      await _room!.connect(
        _serverUrl,
        token,
        fastConnectOptions: FastConnectOptions(
          microphone: const TrackOption(enabled: false),
          camera: const TrackOption(enabled: false),
        ),
      );

      _isConnected = true;
      _isConnecting = false;
      debugPrint('LiveKitService: Connected to LiveKit room "$roomName"');

      // Notify about existing participants
      for (final participant in _room!.remoteParticipants.values) {
        _participantJoinedController.add(participant);
      }

      return true;
    } catch (e) {
      debugPrint('LiveKitService: Connection failed: $e');
      _isConnecting = false;
      return false;
    }
  }

  /// Disconnect from the LiveKit room
  Future<void> disconnect() async {
    if (!_isConnected || _room == null) return;

    debugPrint('LiveKitService: Disconnecting from LiveKit...');

    await _room!.disconnect();
    await _listener?.dispose();
    _listener = null;
    _room = null;
    _isConnected = false;

    debugPrint('LiveKitService: Disconnected');
  }

  /// Enable/disable local camera
  Future<void> setCameraEnabled(bool enabled) async {
    if (_room?.localParticipant == null) return;
    try {
      await _room!.localParticipant!.setCameraEnabled(enabled);
      debugPrint('LiveKitService: Camera ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      debugPrint('LiveKitService: Failed to set camera: $e');
    }
  }

  /// Enable/disable local microphone
  Future<void> setMicrophoneEnabled(bool enabled) async {
    if (_room?.localParticipant == null) return;
    try {
      await _room!.localParticipant!.setMicrophoneEnabled(enabled);
      debugPrint(
          'LiveKitService: Microphone ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      debugPrint('LiveKitService: Failed to set microphone: $e');
    }
  }

  /// Get a participant by their identity (userId)
  Participant? getParticipant(String identity) {
    if (_room == null) return null;

    if (_room!.localParticipant?.identity == identity) {
      return _room!.localParticipant;
    }

    return _room!.remoteParticipants[identity];
  }

  /// Publish data to the room via data channel.
  ///
  /// [data] is the raw bytes to send.
  /// [reliable] when true, uses reliable (ordered) delivery (default: true).
  /// [destinationIdentities] when provided, sends only to specific participants.
  /// [topic] optional topic string to categorize the message.
  Future<void> publishData(
    List<int> data, {
    bool reliable = true,
    List<String>? destinationIdentities,
    String? topic,
  }) async {
    if (_room?.localParticipant == null) {
      debugPrint('LiveKitService: Cannot publish data - not connected');
      return;
    }

    await _room!.localParticipant!.publishData(
      data,
      reliable: reliable,
      destinationIdentities: destinationIdentities,
      topic: topic,
    );
    debugPrint('LiveKitService: Published data, topic: $topic');
  }

  /// Publish a JSON message to the room via data channel.
  ///
  /// Convenience method that encodes [json] as UTF-8 bytes.
  Future<void> publishJson(
    Map<String, dynamic> json, {
    bool reliable = true,
    List<String>? destinationIdentities,
    String? topic,
  }) async {
    final data = utf8.encode(jsonEncode(json));
    await publishData(
      data,
      reliable: reliable,
      destinationIdentities: destinationIdentities,
      topic: topic,
    );
  }

  /// Publish the local player's position to other participants.
  ///
  /// Uses unreliable delivery for lower latency since positions update frequently.
  Future<void> publishPosition({
    required List<Vector2> points,
    required List<Direction> directions,
  }) async {
    final message = {
      'playerId': userId,
      'points': points.map((p) => {'x': p.x, 'y': p.y}).toList(),
      'directions': directions.map((d) => d.name).toList(),
    };

    await publishJson(
      message,
      topic: 'position',
      reliable: false, // Positions can use unreliable for lower latency
    );
  }

  /// Send a ping message to the bot and wait for pong response.
  ///
  /// Returns the pong response message if received within [timeout],
  /// or null if no response.
  Future<DataChannelMessage?> sendPing({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final pingId = DateTime.now().millisecondsSinceEpoch.toString();
    final pingMessage = {
      'type': 'ping',
      'id': pingId,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Listen for pong response with matching ID
    final pongFuture = dataReceived
        .where((msg) => msg.topic == 'pong')
        .where((msg) {
          final json = msg.json;
          return json != null &&
              json['originalMessage']?['id'] == pingId;
        })
        .first
        .timeout(timeout, onTimeout: () => throw TimeoutException('Ping timeout'));

    // Send the ping
    await publishJson(
      pingMessage,
      topic: 'ping',
      destinationIdentities: ['bot-claude'],
    );
    debugPrint('LiveKitService: Sent ping with id: $pingId');

    try {
      final pong = await pongFuture;
      debugPrint('LiveKitService: Received pong from ${pong.senderId}');
      return pong;
    } on TimeoutException {
      debugPrint('LiveKitService: Ping timed out');
      return null;
    }
  }

  Future<String?> _retrieveToken() async {
    try {
      debugPrint('LiveKitService: Retrieving token for room "$roomName"');
      final result = await FirebaseFunctions.instance
          .httpsCallable('retrieveLiveKitToken')
          .call({'roomName': roomName});
      return result.data as String?;
    } catch (e) {
      debugPrint('LiveKitService: Token retrieval failed: $e');
      return null;
    }
  }

  void _setupListeners() {
    _listener
      ?..on<ParticipantConnectedEvent>((event) {
        debugPrint(
            'LiveKitService: Participant joined: ${event.participant.identity}');
        _participantJoinedController.add(event.participant);
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        debugPrint(
            'LiveKitService: Participant left: ${event.participant.identity}');
        _participantLeftController.add(event.participant);
      })
      ..on<TrackSubscribedEvent>((event) {
        debugPrint(
            'LiveKitService: Track subscribed: ${event.participant.identity} - ${event.track.kind}');
        // Emit video track subscription events
        if (event.track is VideoTrack) {
          _trackSubscribedController
              .add((event.participant, event.track as VideoTrack));
        }
      })
      ..on<TrackUnsubscribedEvent>((event) {
        debugPrint(
            'LiveKitService: Track unsubscribed: ${event.participant.identity}');
      })
      ..on<ActiveSpeakersChangedEvent>((event) {
        // Emit speaking state for active speakers
        for (final speaker in event.speakers) {
          _speakingChangedController.add((speaker, true));
        }
      })
      ..on<RoomDisconnectedEvent>((event) {
        debugPrint('LiveKitService: Room disconnected: ${event.reason}');
        _isConnected = false;
      })
      ..on<LocalTrackPublishedEvent>((event) {
        debugPrint(
            'LiveKitService: Local track published: ${event.publication.kind}');
        _localTrackPublishedController.add(event.publication);
      })
      ..on<DataReceivedEvent>((event) {
        debugPrint(
            'LiveKitService: Data received from: ${event.participant?.identity}, topic: ${event.topic}');
        _dataReceivedController.add(DataChannelMessage(
          senderId: event.participant?.identity,
          topic: event.topic,
          data: event.data,
        ));
      });
  }

  /// Dispose of resources
  void dispose() {
    disconnect();
    _participantJoinedController.close();
    _participantLeftController.close();
    _speakingChangedController.close();
    _trackSubscribedController.close();
    _localTrackPublishedController.close();
    _dataReceivedController.close();
  }
}

/// A message received via LiveKit data channel.
class DataChannelMessage {
  DataChannelMessage({
    required this.senderId,
    required this.topic,
    required this.data,
  });

  /// Identity of the sender, or null if sent from server API.
  final String? senderId;

  /// Optional topic categorizing the message.
  final String? topic;

  /// Raw bytes of the message payload.
  final List<int> data;

  /// Decode data as UTF-8 JSON.
  Map<String, dynamic>? get json {
    try {
      return jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Decode data as UTF-8 string.
  String get text => utf8.decode(data);

  @override
  String toString() =>
      'DataChannelMessage(senderId: $senderId, topic: $topic, data: ${data.length} bytes)';
}
