import 'dart:async' show Completer;
import 'dart:async' as async show Timer;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

/// A Flame component that renders a circular video bubble with a player's video feed.
///
/// This component captures frames from a WebRTC video track and renders them
/// as a circular clipped image in the game world.
///
/// ## Implementation Notes
///
/// This uses the frame capture approach - one of several possible methods:
///
/// ### Current: Frame Capture (Option 1)
/// - Captures RGBA frames from MediaStreamTrack.captureFrame()
/// - Converts to dart:ui.Image for rendering
/// - Pros: Full Flame integration, can apply effects/shaders
/// - Cons: CPU overhead from pixel copying, ~15-30fps realistic
///
/// ### Alternative: Hybrid Layer (Option 2)
/// - Use TextureLayer positioned to match game coordinates
/// - Pros: Native GPU performance, no frame copying
/// - Cons: Video renders "on top", can't apply Flame effects
///
/// ### Alternative: Custom Engine Integration (Option 3)
/// - Modify Flame to support TextureLayer in components
/// - Pros: Best of both worlds if feasible
/// - Cons: Requires Flame modifications or custom fork
///
/// For future exploration, see: https://github.com/aspect/tech_world/issues/XX
class VideoBubbleComponent extends PositionComponent {
  VideoBubbleComponent({
    required this.participant,
    required this.displayName,
    this.bubbleSize = 64,
    this.targetFps = 15,
  }) : super(
          size: Vector2.all(bubbleSize),
          anchor: Anchor.bottomCenter,
        );

  final Participant participant;
  final String displayName;
  final double bubbleSize;
  final int targetFps;

  ui.Image? _currentFrame;
  async.Timer? _captureTimer;
  bool _isCapturing = false;

  // Track stats for debugging
  int _framesCaptured = 0;
  int _framesDropped = 0;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    _startFrameCapture();
  }

  @override
  void onRemove() {
    _stopFrameCapture();
    _currentFrame?.dispose();
    _currentFrame = null;
    super.onRemove();
  }

  void _startFrameCapture() {
    final interval = Duration(milliseconds: 1000 ~/ targetFps);
    _captureTimer = async.Timer.periodic(interval, (_) => _captureFrame());
  }

  void _stopFrameCapture() {
    _captureTimer?.cancel();
    _captureTimer = null;
  }

  Future<void> _captureFrame() async {
    if (_isCapturing) {
      _framesDropped++;
      return;
    }

    final videoTrack = _getVideoTrack();
    if (videoTrack == null) return;

    _isCapturing = true;

    try {
      // Get the underlying MediaStreamTrack from the LiveKit track
      final mediaStreamTrack = videoTrack.mediaStreamTrack;

      // Capture frame as RGBA bytes
      final buffer = await mediaStreamTrack.captureFrame();
      final bytes = buffer.asUint8List();

      // We need to know the dimensions - get from track settings
      // The frame is RGBA, so we need width/height to decode
      final settings = mediaStreamTrack.getSettings();
      final width = settings['width'] as int? ?? 640;
      final height = settings['height'] as int? ?? 480;

      // Decode RGBA bytes to ui.Image
      final image = await _decodeRgbaImage(bytes, width, height);

      // Dispose old frame and set new one
      _currentFrame?.dispose();
      _currentFrame = image;
      _framesCaptured++;
    } catch (e) {
      // Frame capture can fail if track is not ready or disposed
      debugPrint('VideoBubbleComponent: Frame capture failed: $e');
      _framesDropped++;
    } finally {
      _isCapturing = false;
    }
  }

  VideoTrack? _getVideoTrack() {
    // Try to get the camera video track from the participant
    for (final publication in participant.videoTrackPublications) {
      final track = publication.track;
      if (track != null && track.kind == TrackType.VIDEO) {
        return track as VideoTrack;
      }
    }
    return null;
  }

  Future<ui.Image> _decodeRgbaImage(
      Uint8List bytes, int width, int height) async {
    final completer = Completer<ui.Image>();

    // Create an immutable buffer from the RGBA data
    ui.ImmutableBuffer.fromUint8List(bytes).then((buffer) {
      // Decode as raw RGBA pixels
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );

      descriptor.instantiateCodec().then((codec) {
        codec.getNextFrame().then((frameInfo) {
          completer.complete(frameInfo.image);
          codec.dispose();
          descriptor.dispose();
        });
      });
    });

    return completer.future;
  }

  @override
  void render(Canvas canvas) {
    final center = Offset(size.x / 2, size.y / 2);
    final radius = bubbleSize / 2;

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(center + const Offset(0, 2), radius, shadowPaint);

    // Clip to circle for video
    canvas.save();
    final clipPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.clipPath(clipPath);

    if (_currentFrame != null) {
      // Draw the video frame, scaled to fit the bubble
      final srcRect = Rect.fromLTWH(
        0,
        0,
        _currentFrame!.width.toDouble(),
        _currentFrame!.height.toDouble(),
      );

      // Calculate destination rect to cover the circle (center crop)
      final aspectRatio = _currentFrame!.width / _currentFrame!.height;
      double dstWidth, dstHeight;
      if (aspectRatio > 1) {
        // Wider than tall - fit height, crop width
        dstHeight = bubbleSize;
        dstWidth = bubbleSize * aspectRatio;
      } else {
        // Taller than wide - fit width, crop height
        dstWidth = bubbleSize;
        dstHeight = bubbleSize / aspectRatio;
      }

      final dstRect = Rect.fromCenter(
        center: center,
        width: dstWidth,
        height: dstHeight,
      );

      canvas.drawImageRect(_currentFrame!, srcRect, dstRect, Paint());
    } else {
      // Fallback: draw colored background with initial (like PlayerBubbleComponent)
      final bgPaint = Paint()..color = Colors.grey[800]!;
      canvas.drawCircle(center, radius, bgPaint);

      // Draw initial
      final textPainter = TextPainter(
        text: TextSpan(
          text: _getInitial(),
          style: TextStyle(
            color: Colors.white,
            fontSize: bubbleSize * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          center.dx - textPainter.width / 2,
          center.dy - textPainter.height / 2,
        ),
      );
    }

    canvas.restore();

    // Draw border (outside the clip)
    final borderPaint = Paint()
      ..color = _currentFrame != null ? Colors.green : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, borderPaint);
  }

  String _getInitial() {
    if (displayName.isNotEmpty) {
      return displayName[0].toUpperCase();
    }
    return '?';
  }

  /// Debug info about frame capture performance
  Map<String, dynamic> get debugStats => {
        'framesCaptured': _framesCaptured,
        'framesDropped': _framesDropped,
        'hasCurrentFrame': _currentFrame != null,
        'targetFps': targetFps,
      };
}
