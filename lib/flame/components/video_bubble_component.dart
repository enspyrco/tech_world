import 'dart:async' show Completer;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../native/video_frame_capture.dart' as ffi;

/// A Flame component that renders a circular video bubble with a player's video feed.
///
/// This component captures frames from a WebRTC video track using FFI
/// (zero-copy shared memory) and renders them as a circular clipped image
/// in the game world, with optional shader effects.
///
/// ## Implementation
///
/// Uses VideoFrameCapture FFI for direct frame access (no disk I/O):
/// - Native code registers as RTCVideoRenderer on the video track
/// - Frames are written to shared memory buffer
/// - Dart reads pixels directly via FFI pointer
/// - Converts BGRA to RGBA and creates dart:ui.Image
/// - Can apply custom fragment shaders via ImageFilter.shader (Impeller)
///
/// ## Platform Support
///
/// Currently only macOS is supported. Other platforms fall back to
/// displaying a placeholder with the user's initial.
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
  VideoTrack? _videoTrack;
  ffi.VideoFrameCapture? _capture;
  bool _captureInitialized = false;

  // Shader support
  ui.FragmentShader? _shader;
  double _time = 0;
  double _glowIntensity = 0.5;
  Color _glowColor = Colors.green;
  double _speakingLevel = 0.0;

  // Track stats for debugging
  int _framesCaptured = 0;
  int _framesDropped = 0;
  DateTime? _lastFrameTime;
  final Duration _minFrameInterval = const Duration(milliseconds: 50);

  // Retry tracking for FFI capture initialization
  int _captureRetryCount = 0;
  static const int _maxCaptureRetries = 10;
  double _timeSinceLastRetry = 0;
  static const double _retryIntervalSeconds = 0.5; // Retry every 500ms

  // Platform check that works on web (where dart:io is not available)
  static bool get _isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Set a custom fragment shader for effects.
  void setShader(ui.FragmentShader shader) {
    _shader = shader;
  }

  /// Set the glow intensity (0.0 - 1.0)
  set glowIntensity(double value) => _glowIntensity = value.clamp(0.0, 1.0);

  /// Set the glow color
  set glowColor(Color value) => _glowColor = value;

  /// Set the speaking level for pulse effects (0.0 - 1.0)
  set speakingLevel(double value) => _speakingLevel = value.clamp(0.0, 1.0);

  @override
  Future<void> onLoad() async {
    super.onLoad();
    _initializeCapture();
  }

  @override
  void onRemove() {
    _disposeCapture();
    _currentFrame?.dispose();
    _currentFrame = null;
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;

    // Try to initialize capture if not yet done (with retry backoff)
    if (!_captureInitialized && _captureRetryCount < _maxCaptureRetries) {
      _timeSinceLastRetry += dt;
      if (_timeSinceLastRetry >= _retryIntervalSeconds) {
        _timeSinceLastRetry = 0;
        _initializeCapture();
      }
    }

    // Check for new frames
    _checkForNewFrame();
  }

  void _initializeCapture() {
    if (_captureInitialized) return;

    _captureRetryCount++;

    // FFI capture only supported on macOS (not web or other platforms)
    if (kIsWeb || !_isMacOS) {
      _captureInitialized = true;
      debugPrint('VideoBubbleComponent: FFI capture only supported on macOS');
      return;
    }

    final track = _getVideoTrack();
    if (track == null) {
      if (_captureRetryCount >= _maxCaptureRetries) {
        debugPrint(
            'VideoBubbleComponent: No video track after $_captureRetryCount retries');
      }
      return;
    }

    if (_videoTrack == track && _capture != null) {
      return; // Already attached
    }

    _disposeCapture();
    _videoTrack = track;

    // Get the WebRTC track ID (not the LiveKit sid)
    final trackId = track.mediaStreamTrack.id;
    if (trackId == null || trackId.isEmpty) {
      debugPrint(
          'VideoBubbleComponent: Track has no mediaStreamTrack.id, cannot capture');
      return;
    }

    debugPrint(
        'VideoBubbleComponent: Creating FFI capture for track $trackId (sid: ${track.sid}), attempt $_captureRetryCount');

    // List available tracks for debugging (before attempting create)
    final availableTracks = ffi.VideoFrameCapture.listTracks();
    debugPrint(
        'VideoBubbleComponent: Available native tracks: $availableTracks');

    _capture = ffi.VideoFrameCapture.create(
      trackId,
      targetFps: targetFps,
      maxWidth: 640,
      maxHeight: 480,
    );

    if (_capture != null) {
      debugPrint('VideoBubbleComponent: FFI capture created successfully');
      _captureInitialized = true;
    } else {
      debugPrint(
          'VideoBubbleComponent: Failed to create FFI capture, will retry');
    }
  }

  void _disposeCapture() {
    _capture?.dispose();
    _capture = null;
    _videoTrack = null;
    _captureInitialized = false;
  }

  void _checkForNewFrame() {
    if (_capture == null) return;

    // Check if a new frame is available
    if (!_capture!.hasNewFrame) return;

    // Throttle frame processing
    final now = DateTime.now();
    if (_lastFrameTime != null &&
        now.difference(_lastFrameTime!) < _minFrameInterval) {
      _framesDropped++;
      return;
    }
    _lastFrameTime = now;

    // Process the frame
    _processFrame();
  }

  Future<void> _processFrame() async {
    if (_capture == null) return;

    try {
      final width = _capture!.width;
      final height = _capture!.height;

      if (width == 0 || height == 0) {
        _framesDropped++;
        return;
      }

      // Get the BGRA pixel data directly via FFI (zero-copy)
      final bgraBytes = _capture!.getPixels();
      if (bgraBytes == null) {
        _framesDropped++;
        return;
      }

      // Mark the frame as consumed so native can write the next one
      _capture!.markConsumed();

      // Convert BGRA to RGBA for ui.Image
      final rgbaBytes = _bgraToRgba(bgraBytes);

      // Decode to ui.Image
      final image = await _decodeRgbaImage(rgbaBytes, width, height);

      // Dispose old frame and set new one
      _currentFrame?.dispose();
      _currentFrame = image;
      _framesCaptured++;
    } catch (e) {
      debugPrint('VideoBubbleComponent: Frame processing failed: $e');
      _framesDropped++;
    }
  }

  /// Convert BGRA byte array to RGBA
  Uint8List _bgraToRgba(Uint8List bgra) {
    final rgba = Uint8List(bgra.length);
    for (var i = 0; i < bgra.length; i += 4) {
      rgba[i] = bgra[i + 2]; // R from B position in BGRA
      rgba[i + 1] = bgra[i + 1]; // G stays same
      rgba[i + 2] = bgra[i]; // B from R position in BGRA
      rgba[i + 3] = bgra[i + 3]; // A stays same
    }
    return rgba;
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

    ui.ImmutableBuffer.fromUint8List(bytes).then((buffer) {
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

  void _updateShaderUniforms() {
    if (_shader == null) return;

    _shader!.setFloat(0, bubbleSize);
    _shader!.setFloat(1, bubbleSize);
    _shader!.setFloat(2, _time);
    _shader!.setFloat(3, _glowIntensity);
    _shader!.setFloat(4, _glowColor.r);
    _shader!.setFloat(5, _glowColor.g);
    _shader!.setFloat(6, _glowColor.b);
    _shader!.setFloat(7, _speakingLevel);
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

    if (_currentFrame != null) {
      _updateShaderUniforms();

      final paint = Paint();
      if (_shader != null && ui.ImageFilter.isShaderFilterSupported) {
        paint.imageFilter = ui.ImageFilter.shader(_shader!);
      }

      canvas.saveLayer(
        Rect.fromCircle(center: center, radius: radius + 10),
        paint,
      );

      canvas.save();
      final clipPath = Path()
        ..addOval(Rect.fromCircle(center: center, radius: radius));
      canvas.clipPath(clipPath);

      final srcRect = Rect.fromLTWH(
        0,
        0,
        _currentFrame!.width.toDouble(),
        _currentFrame!.height.toDouble(),
      );

      final aspectRatio = _currentFrame!.width / _currentFrame!.height;
      double dstWidth, dstHeight;
      if (aspectRatio > 1) {
        dstHeight = bubbleSize;
        dstWidth = bubbleSize * aspectRatio;
      } else {
        dstWidth = bubbleSize;
        dstHeight = bubbleSize / aspectRatio;
      }

      final dstRect = Rect.fromCenter(
        center: center,
        width: dstWidth,
        height: dstHeight,
      );

      canvas.drawImageRect(_currentFrame!, srcRect, dstRect, Paint());

      canvas.restore();
      canvas.restore();
    } else {
      // Fallback: draw colored background with initial
      canvas.save();
      final clipPath = Path()
        ..addOval(Rect.fromCircle(center: center, radius: radius));
      canvas.clipPath(clipPath);

      final bgPaint = Paint()..color = Colors.grey[800]!;
      canvas.drawCircle(center, radius, bgPaint);

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

      canvas.restore();
    }

    if (_shader == null || !ui.ImageFilter.isShaderFilterSupported) {
      final borderPaint = Paint()
        ..color = _currentFrame != null ? Colors.green : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, borderPaint);
    }
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
        'captureActive': _capture?.isActive ?? false,
        'targetFps': targetFps,
        'shaderEnabled':
            _shader != null && ui.ImageFilter.isShaderFilterSupported,
      };
}
