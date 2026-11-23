// The hooks are @protected: the transport calls them, and so do these tests,
// standing in for a live Room's events.
// ignore_for_file: invalid_use_of_protected_member

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/livekit/livekit_service.dart';

/// [LiveKitService] layers the game onto [LiveKitTransport] through three
/// hooks. The transport calls them at the moment of the room event; these
/// tests call them the same way and pin what the game does in each.
void main() {
  late List<AppEvent> events;
  late void Function(AppEvent) sink;
  late List<String> silenced;
  late LiveKitService service;

  setUp(() {
    events = [];
    sink = events.add;
    registerSink(sink);
    silenced = [];
    service = LiveKitService(
      userId: 'user-1',
      displayName: 'User 1',
      roomName: 'room-x',
      silenceParticipantAudio: silenced.add,
    );
  });

  tearDown(() async {
    unregisterSink(sink);
    await service.dispose();
  });

  test('onConnected dispatches LiveKitConnected for the room', () {
    service.onConnected();

    expect(
      events.whereType<LiveKitConnected>().map((e) => e.roomName),
      ['room-x'],
    );
  });

  test('onConnectionLost dispatches LiveKitDisconnected with the reason', () {
    service.onConnectionLost('signalClose');

    expect(
      events.whereType<LiveKitDisconnected>().map((e) => e.reason),
      ['signalClose'],
    );
  });

  test('onRemoteTrackSubscribed disables a Dreamfinder audio track only', () {
    service
      ..onRemoteTrackSubscribed(identity: 'agent-abc', isAudioTrack: true)
      ..onRemoteTrackSubscribed(identity: 'agent-abc', isAudioTrack: false)
      ..onRemoteTrackSubscribed(identity: 'player-2', isAudioTrack: true);

    expect(silenced, ['agent-abc']);
  });
}
