import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/livekit/widgets/screen_share_overlay.dart';
import 'package:tech_world/livekit/widgets/screen_share_panel.dart';

/// Fake LiveKitService that exposes stream controllers for testing.
class FakeLiveKitService implements LiveKitService {
  final _trackSubscribedController =
      StreamController<(Participant, VideoTrack)>.broadcast();
  final _trackUnsubscribedController =
      StreamController<(Participant, VideoTrack)>.broadcast();

  @override
  Stream<(Participant, VideoTrack)> get trackSubscribed =>
      _trackSubscribedController.stream;

  @override
  Stream<(Participant, VideoTrack)> get trackUnsubscribed =>
      _trackUnsubscribedController.stream;

  /// Whether the subscribed stream currently has listeners.
  bool get hasSubscribedListeners =>
      _trackSubscribedController.hasListener;

  /// Whether the unsubscribed stream currently has listeners.
  bool get hasUnsubscribedListeners =>
      _trackUnsubscribedController.hasListener;

  void simulateTrackSubscribed(Participant participant, VideoTrack track) {
    _trackSubscribedController.add((participant, track));
  }

  void simulateTrackUnsubscribed(Participant participant, VideoTrack track) {
    _trackUnsubscribedController.add((participant, track));
  }

  @override
  Future<void> dispose() async {
    _trackSubscribedController.close();
    _trackUnsubscribedController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('ScreenShareOverlay', () {
    late FakeLiveKitService fakeLiveKit;

    setUp(() {
      fakeLiveKit = FakeLiveKitService();
    });

    tearDown(() {
      fakeLiveKit.dispose();
    });

    testWidgets('renders SizedBox.shrink when no screen shares',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ScreenShareOverlay(liveKitService: fakeLiveKit),
              ],
            ),
          ),
        ),
      );

      // Should render nothing visible.
      expect(find.byType(ScreenSharePanel), findsNothing);
    });

    testWidgets('subscribes to both streams on init', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ScreenShareOverlay(liveKitService: fakeLiveKit),
              ],
            ),
          ),
        ),
      );

      expect(fakeLiveKit.hasSubscribedListeners, isTrue);
      expect(fakeLiveKit.hasUnsubscribedListeners, isTrue);
    });

    testWidgets('cancels subscriptions on dispose', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ScreenShareOverlay(liveKitService: fakeLiveKit),
              ],
            ),
          ),
        ),
      );

      // Dispose the widget by replacing it.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      // Streams should no longer have listeners from the overlay.
      expect(fakeLiveKit.hasSubscribedListeners, isFalse);
      expect(fakeLiveKit.hasUnsubscribedListeners, isFalse);
    });

    testWidgets('resubscribes when liveKitService changes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ScreenShareOverlay(liveKitService: fakeLiveKit),
              ],
            ),
          ),
        ),
      );

      expect(fakeLiveKit.hasSubscribedListeners, isTrue);

      // Swap to a new service.
      final newService = FakeLiveKitService();
      addTearDown(newService.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ScreenShareOverlay(liveKitService: newService),
              ],
            ),
          ),
        ),
      );

      // Old service should lose its listeners; new service should gain them.
      expect(fakeLiveKit.hasSubscribedListeners, isFalse);
      expect(newService.hasSubscribedListeners, isTrue);
      expect(newService.hasUnsubscribedListeners, isTrue);
    });

    // Note: Testing subscribe/unsubscribe track flows would require mocking
    // Participant.getTrackPublicationBySource(), which returns a
    // TrackPublication whose track.sid must match. LiveKit's SDK classes
    // don't have simple test constructors, so these flows are best verified
    // via integration tests with a real LiveKit room.
  });
}
