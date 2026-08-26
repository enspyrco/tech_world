import 'package:flame/components.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/material.dart' show Color, Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tech_world/flame/bubble_factory.dart';
import 'package:tech_world/flame/components/bot_bubble_component.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/flame/components/player_bubble_component.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/components/video_bubble_component.dart';
import 'package:tech_world/livekit/livekit_service.dart';

class MockLiveKitService extends Mock implements LiveKitService {}

class MockRemoteParticipant extends Mock implements RemoteParticipant {}

class MockLocalParticipant extends Mock implements LocalParticipant {}

class MockRemoteVideoTrackPublication extends Mock
    implements RemoteTrackPublication<RemoteVideoTrack> {}

class MockLocalVideoTrackPublication extends Mock
    implements LocalTrackPublication<LocalVideoTrack> {}

class MockRemoteVideoTrack extends Mock implements RemoteVideoTrack {}

class MockLocalVideoTrack extends Mock implements LocalVideoTrack {}

void main() {
  late MockLiveKitService service;

  MockRemoteParticipant remoteWithVideo() {
    final pub = MockRemoteVideoTrackPublication();
    when(() => pub.track).thenReturn(MockRemoteVideoTrack());
    when(() => pub.subscribed).thenReturn(true);
    final p = MockRemoteParticipant();
    when(() => p.videoTrackPublications).thenReturn([pub]);
    return p;
  }

  MockRemoteParticipant remoteWithoutVideo() {
    final p = MockRemoteParticipant();
    when(() => p.videoTrackPublications).thenReturn([]);
    return p;
  }

  MockLocalParticipant localWithVideo() {
    final pub = MockLocalVideoTrackPublication();
    when(() => pub.track).thenReturn(MockLocalVideoTrack());
    when(() => pub.subscribed).thenReturn(true);
    final p = MockLocalParticipant();
    when(() => p.videoTrackPublications).thenReturn([pub]);
    return p;
  }

  BubbleFactory build({
    bool hideVideo = false,
    bool reduceMotion = false,
    bool mobileWeb = false,
  }) =>
      BubbleFactory(
        hideVideoBubbles: () => hideVideo,
        reduceMotion: () => reduceMotion,
        liveKitService: () => service,
        dreamfinderCapture: () => null,
        botStatus: () => ValueNotifier(BotStatus.idle),
        isMobileWeb: mobileWeb,
      );

  final player = PlayerComponent(
    position: Vector2.zero(),
    id: 'peer',
    displayName: 'Peer',
  );

  setUp(() {
    service = MockLiveKitService();
  });

  group('forRemotePlayer — the video-or-avatar decision', () {
    test('video bubble when the peer has a subscribed track', () {
      final p = remoteWithVideo();
      when(() => service.getParticipant('peer')).thenReturn(p);

      expect(build().forRemotePlayer('peer', player),
          isA<VideoBubbleComponent>());
    });

    test('avatar when video bubbles are hidden, track or no track', () {
      final p = remoteWithVideo();
      when(() => service.getParticipant('peer')).thenReturn(p);

      expect(build(hideVideo: true).forRemotePlayer('peer', player),
          isA<PlayerBubbleComponent>());
    });

    test('avatar when the peer publishes no video', () {
      final p = remoteWithoutVideo();
      when(() => service.getParticipant('peer')).thenReturn(p);

      expect(build().forRemotePlayer('peer', player),
          isA<PlayerBubbleComponent>());
    });

    test('avatar when the participant is unknown to LiveKit', () {
      when(() => service.getParticipant('peer')).thenReturn(null);

      expect(build().forRemotePlayer('peer', player),
          isA<PlayerBubbleComponent>());
    });

    test('a remote video bubble is NOT tinted — only the local one is', () {
      final p = remoteWithVideo();
      when(() => service.getParticipant('peer')).thenReturn(p);
      final bubble =
          build().forRemotePlayer('peer', player) as VideoBubbleComponent;

      expect(bubble.glowColor, isNot(equals(Colors.cyan)));
    });
  });

  group('forLocalPlayer — same decision, different source', () {
    test('video bubble from the LOCAL participant, glowing cyan', () {
      final p = localWithVideo();
      when(() => service.localParticipant).thenReturn(p);

      final bubble = build().forLocalPlayer(player);

      expect(bubble, isA<VideoBubbleComponent>());
      expect((bubble as VideoBubbleComponent).glowColor, equals(Colors.cyan));
    });

    test('avatar when the local camera is off', () {
      when(() => service.localParticipant).thenReturn(null);

      expect(build().forLocalPlayer(player), isA<PlayerBubbleComponent>());
    });

    test('does not read the remote participant lookup', () {
      // The two paths differ ONLY in their participant source. If the local
      // path ever reached getParticipant() it would pick up whoever happened
      // to share the local player's id.
      final p = localWithVideo();
      when(() => service.localParticipant).thenReturn(p);

      build().forLocalPlayer(player);

      verifyNever(() => service.getParticipant(any()));
    });
  });

  group('forDreamfinder', () {
    test('is gold, not the peer default', () {
      final bubble = build().forDreamfinder(remoteWithVideo());

      expect(bubble.glowColor, equals(const Color(0xFFDAA520)));
      expect(bubble.glowIntensity, equals(0.7));
    });

    test('is built regardless of track state — it renders a canvas', () {
      // DF's frames come from the avatar iframe, not a camera publication, so
      // the hasVideoTrack gate that governs peers must not apply here.
      final bubble = build().forDreamfinder(remoteWithoutVideo());

      expect(bubble, isA<VideoBubbleComponent>());
    });
  });

  group('canEmbodyDreamfinder', () {
    test('true by default', () {
      expect(build().canEmbodyDreamfinder, isTrue);
    });

    test('false on mobile web — the WebGL bubble renders black there', () {
      expect(build(mobileWeb: true).canEmbodyDreamfinder, isFalse);
    });

    test('false when the user has hidden video bubbles', () {
      expect(build(hideVideo: true).canEmbodyDreamfinder, isFalse);
    });
  });

  group('forBot', () {
    test('defaults to BotBubbleComponent own size', () {
      expect(build().forBot(), isA<BotBubbleComponent>());
      expect(build().forBot().bubbleSize, equals(48));
    });

    test('honours an explicit size', () {
      // The downgrade path passes 64 while the create path passes nothing, so
      // Dreamfinder's bot bubble is 48px when it appears and 64px after a
      // video downgrade. Preserved verbatim through the extraction rather than
      // normalised — pinned here so the discrepancy is visible instead of
      // folklore.
      expect(build().forBot(bubbleSize: 64).bubbleSize, equals(64));
    });
  });

  group('reduceMotion is read live, not captured', () {
    test('a preference applied at room entry reaches new bubbles', () {
      var reduce = false;
      final p = remoteWithVideo();
      when(() => service.getParticipant('peer')).thenReturn(p);
      final factory = BubbleFactory(
        hideVideoBubbles: () => false,
        reduceMotion: () => reduce,
        liveKitService: () => service,
        dreamfinderCapture: () => null,
        botStatus: () => ValueNotifier(BotStatus.idle),
        isMobileWeb: false,
      );

      final before =
          factory.forRemotePlayer('peer', player) as VideoBubbleComponent;
      expect(before.reduceMotion, isFalse);

      reduce = true;
      final after =
          factory.forRemotePlayer('peer', player) as VideoBubbleComponent;
      expect(after.reduceMotion, isTrue);
    });
  });
}
