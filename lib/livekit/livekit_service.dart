import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

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
  }
}
