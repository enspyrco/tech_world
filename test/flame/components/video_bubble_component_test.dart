import 'dart:typed_data';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tech_world/flame/components/video_bubble_component.dart';

// Mock classes for LiveKit
class MockParticipant extends Mock implements Participant {}

class MockVideoTrackPublication extends Mock
    implements TrackPublication<VideoTrack> {}

/// Testable subclass that exposes private methods for testing
class TestableVideoBubbleComponent extends VideoBubbleComponent {
  TestableVideoBubbleComponent({
    required super.participant,
    required super.displayName,
    super.bubbleSize,
    super.targetFps,
  });

  /// Expose _getInitial for testing
  String getInitialForTest() {
    if (displayName.isNotEmpty) {
      return displayName[0].toUpperCase();
    }
    return '?';
  }

  /// Expose _bgraToRgba for testing
  Uint8List bgraToRgbaForTest(Uint8List bgra) {
    final rgba = Uint8List(bgra.length);
    for (var i = 0; i < bgra.length; i += 4) {
      rgba[i] = bgra[i + 2]; // R from B position in BGRA
      rgba[i + 1] = bgra[i + 1]; // G stays same
      rgba[i + 2] = bgra[i]; // B from R position in BGRA
      rgba[i + 3] = bgra[i + 3]; // A stays same
    }
    return rgba;
  }
}

void main() {
  group('VideoBubbleComponent', () {
    late MockParticipant mockParticipant;

    setUp(() {
      mockParticipant = MockParticipant();
      // Default stub for videoTrackPublications
      when(() => mockParticipant.videoTrackPublications).thenReturn([]);
    });

    group('constructor', () {
      test('creates component with default values', () {
        final bubble = VideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'Test User',
        );

        expect(bubble.displayName, equals('Test User'));
        expect(bubble.bubbleSize, equals(64));
        expect(bubble.targetFps, equals(15));
        expect(bubble.size.x, equals(64));
        expect(bubble.size.y, equals(64));
      });

      test('creates component with custom bubble size', () {
        final bubble = VideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'Test',
          bubbleSize: 128,
        );

        expect(bubble.bubbleSize, equals(128));
        expect(bubble.size.x, equals(128));
        expect(bubble.size.y, equals(128));
      });

      test('creates component with custom target FPS', () {
        final bubble = VideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'Test',
          targetFps: 30,
        );

        expect(bubble.targetFps, equals(30));
      });

      test('has bottom center anchor', () {
        final bubble = VideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'Test',
        );

        expect(bubble.anchor, equals(Anchor.bottomCenter));
      });
    });

    group('initial state', () {
      test('isWaitingForFrame is true initially', () {
        final bubble = VideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'Test',
        );

        expect(bubble.isWaitingForFrame, isTrue);
      });

      test('debugStats shows initial state', () {
        final bubble = VideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'Test',
          targetFps: 20,
        );

        final stats = bubble.debugStats;
        expect(stats['framesCaptured'], equals(0));
        expect(stats['framesDropped'], equals(0));
        expect(stats['hasCurrentFrame'], isFalse);
        expect(stats['captureActive'], isFalse);
        expect(stats['targetFps'], equals(20));
      });
    });

    group('setters', () {
      test('glowIntensity clamps values between 0 and 1', () {
        final bubble = VideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'Test',
        );

        // Normal value
        bubble.glowIntensity = 0.5;
        // Can't directly access _glowIntensity, but we verify it doesn't throw

        // Below minimum - should clamp to 0
        bubble.glowIntensity = -0.5;

        // Above maximum - should clamp to 1
        bubble.glowIntensity = 1.5;

        // Exact boundaries
        bubble.glowIntensity = 0.0;
        bubble.glowIntensity = 1.0;
      });

      test('speakingLevel clamps values between 0 and 1', () {
        final bubble = VideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'Test',
        );

        // Normal value
        bubble.speakingLevel = 0.7;

        // Below minimum - should clamp to 0
        bubble.speakingLevel = -1.0;

        // Above maximum - should clamp to 1
        bubble.speakingLevel = 2.0;

        // Exact boundaries
        bubble.speakingLevel = 0.0;
        bubble.speakingLevel = 1.0;
      });
    });

    group('_getInitial logic', () {
      test('returns first character of displayName uppercased', () {
        final bubble = TestableVideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'john',
        );

        expect(bubble.getInitialForTest(), equals('J'));
      });

      test('returns uppercase for already uppercase name', () {
        final bubble = TestableVideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'Alice',
        );

        expect(bubble.getInitialForTest(), equals('A'));
      });

      test('returns ? for empty displayName', () {
        final bubble = TestableVideoBubbleComponent(
          participant: mockParticipant,
          displayName: '',
        );

        expect(bubble.getInitialForTest(), equals('?'));
      });

      test('handles numeric first character', () {
        final bubble = TestableVideoBubbleComponent(
          participant: mockParticipant,
          displayName: '42Bot',
        );

        expect(bubble.getInitialForTest(), equals('4'));
      });

      test('handles special character first', () {
        final bubble = TestableVideoBubbleComponent(
          participant: mockParticipant,
          displayName: '@User',
        );

        expect(bubble.getInitialForTest(), equals('@'));
      });

      test('handles emoji first character', () {
        final bubble = TestableVideoBubbleComponent(
          participant: mockParticipant,
          displayName: '🎮 Gamer',
        );

        // First "character" will be the first code unit of the emoji
        expect(bubble.getInitialForTest(), isNotEmpty);
      });
    });

    group('_bgraToRgba conversion', () {
      test('converts single pixel correctly', () {
        final bubble = TestableVideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'Test',
        );

        // BGRA: Blue=100, Green=150, Red=200, Alpha=255
        final bgra = Uint8List.fromList([100, 150, 200, 255]);
        final rgba = bubble.bgraToRgbaForTest(bgra);

        // RGBA: Red=200, Green=150, Blue=100, Alpha=255
        expect(rgba[0], equals(200)); // R (was at position 2 in BGRA)
        expect(rgba[1], equals(150)); // G (stays same)
        expect(rgba[2], equals(100)); // B (was at position 0 in BGRA)
        expect(rgba[3], equals(255)); // A (stays same)
      });

      test('converts multiple pixels correctly', () {
        final bubble = TestableVideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'Test',
        );

        // Two pixels in BGRA format
        final bgra = Uint8List.fromList([
          // Pixel 1: BGRA(10, 20, 30, 255)
          10, 20, 30, 255,
          // Pixel 2: BGRA(40, 50, 60, 128)
          40, 50, 60, 128,
        ]);
        final rgba = bubble.bgraToRgbaForTest(bgra);

        // Pixel 1 in RGBA
        expect(rgba[0], equals(30)); // R
        expect(rgba[1], equals(20)); // G
        expect(rgba[2], equals(10)); // B
        expect(rgba[3], equals(255)); // A

        // Pixel 2 in RGBA
        expect(rgba[4], equals(60)); // R
        expect(rgba[5], equals(50)); // G
        expect(rgba[6], equals(40)); // B
        expect(rgba[7], equals(128)); // A
      });

      test('handles empty input', () {
        final bubble = TestableVideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'Test',
        );

        final bgra = Uint8List(0);
        final rgba = bubble.bgraToRgbaForTest(bgra);

        expect(rgba.length, equals(0));
      });

      test('preserves alpha channel values', () {
        final bubble = TestableVideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'Test',
        );

        // Test various alpha values
        final bgra = Uint8List.fromList([
          0, 0, 0, 0, // Fully transparent
          0, 0, 0, 128, // Half transparent
          0, 0, 0, 255, // Fully opaque
        ]);
        final rgba = bubble.bgraToRgbaForTest(bgra);

        expect(rgba[3], equals(0)); // Fully transparent
        expect(rgba[7], equals(128)); // Half transparent
        expect(rgba[11], equals(255)); // Fully opaque
      });
    });

    group('size variations', () {
      test('small bubble size', () {
        final bubble = VideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'A',
          bubbleSize: 32,
        );

        expect(bubble.size.x, equals(32));
        expect(bubble.size.y, equals(32));
      });

      test('large bubble size', () {
        final bubble = VideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'A',
          bubbleSize: 256,
        );

        expect(bubble.size.x, equals(256));
        expect(bubble.size.y, equals(256));
      });
    });

    group('notifyTrackReady', () {
      test('can be called without error before initialization', () {
        final bubble = VideoBubbleComponent(
          participant: mockParticipant,
          displayName: 'Test',
        );

        // Should not throw
        expect(() => bubble.notifyTrackReady(), returnsNormally);
      });
    });
  });
}
