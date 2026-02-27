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

  void simulateTrackSubscribed(Participant participant, VideoTrack track) {
    _trackSubscribedController.add((participant, track));
  }

  void simulateTrackUnsubscribed(Participant participant, VideoTrack track) {
    _trackUnsubscribedController.add((participant, track));
  }

  @override
  void dispose() {
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
  });
}
