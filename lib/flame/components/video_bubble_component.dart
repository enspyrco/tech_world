import 'dart:async' show Completer;
import 'dart:math' show pi;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../native/video_frame_capture.dart' as ffi;
import '../../native/web_video_capture.dart' as web_capture;

/// A Flame component that renders a circular video bubble with a player's video feed.
///
/// This component captures frames from a WebRTC video track and renders them
/// as a circular clipped image in the game world, with optional shader effects.
///
/// ## Platform Implementation
///
/// ### macOS (FFI)
/// Uses VideoFrameCapture FFI for direct frame access (no disk I/O):
/// - Native code registers as RTCVideoRenderer on the video track
/// - Frames are written to shared memory buffer
/// - Dart reads pixels directly via FFI pointer
/// - Converts BGRA to RGBA and creates dart:ui.Image
///
/// ### Web
/// Uses createImageBitmap + createImageFromImageBitmap for GPU-efficient capture:
/// - Finds the HTMLVideoElement created by flutter_webrtc
/// - Uses requestVideoFrameCallback for frame-accurate capture
/// - createImageBitmap provides GPU-to-GPU transfer
/// - createImageFromImageBitmap converts to Flutter ui.Image
///
/// ### Other platforms
/// Falls back to displaying a placeholder with the user's initial.
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

  // Native FFI capture (macOS)
  ffi.VideoFrameCapture? _capture;

  // Web capture
  dynamic _webCapture; // WebVideoFrameCapture on web, null otherwise

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

  // Retry tracking for capture initialization
  int _captureRetryCount = 0;
  static const int _maxCaptureRetries = 10;
  double _timeSinceLastRetry = 0;
  static const double _retryIntervalSeconds = 0.5; // Retry every 500ms

  // Loading state
  bool _isLoading = true;
  double _loadingRotation = 0.0;
  static const double _loadingSpinSpeed = 3.0; // radians per second

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
  void onRemove() {
    _disposeCapture();
    _currentFrame?.dispose();
    _currentFrame = null;
    super.onRemove();
  }

  /// Whether the component is still waiting for the first video frame
  bool get isWaitingForFrame => _isLoading;

  /// Notify that the video track is ready (called when track subscription event fires)
  /// This triggers immediate capture initialization instead of waiting for retry timer.
  void notifyTrackReady() {
    if (!_captureInitialized) {
      _initializeCapture();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;

    // Update loading animation
    if (_isLoading) {
      _loadingRotation += _loadingSpinSpeed * dt;
    }

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

    if (kIsWeb) {
      _initializeWebCapture();
    } else if (_isMacOS) {
      _initializeNativeCapture();
    } else {
      // Unsupported platform
      _captureInitialized = true;
    }
  }

  bool _webCaptureInitializing = false;

  void _initializeWebCapture() {
    // Prevent concurrent initialization attempts
    if (_webCaptureInitializing) return;

    final track = _getVideoTrack();
    if (track == null) {
      debugPrint('WebCapture: No video track found for $displayName');
      return;
    }

    // Get the underlying MediaStreamTrack
    final mediaStreamTrack = track.mediaStreamTrack;
    debugPrint('WebCapture: Got MediaStreamTrack for $displayName');

    // Mark as initializing and start async process
    _webCaptureInitializing = true;
    _initializeWebCaptureAsync(track, mediaStreamTrack);
  }

  Future<void> _initializeWebCaptureAsync(
      VideoTrack track, dynamic mediaStreamTrack) async {
    try {
      final isRemote = participant is! LocalParticipant;
      debugPrint('WebCapture: Initializing for $displayName (isRemote=$isRemote)');

      // Get the track ID from the public API (works in release mode)
      final trackId = mediaStreamTrack.id as String?;
      // Also get the LiveKit track SID which might be different
      final trackSid = track.sid;
      debugPrint('WebCapture: mediaStreamTrack.id=$trackId, track.sid=$trackSid');

      // Debug: list all video elements
      web_capture.WebVideoFrameCapture.debugListVideoElements();

      // Try to find an existing video element for this track
      // Try both the mediaStreamTrack.id AND the LiveKit track SID
      final idsToTry = <String>{};
      if (trackId != null && trackId.isNotEmpty) idsToTry.add(trackId);
      if (trackSid != null && trackSid.isNotEmpty) idsToTry.add(trackSid);
      debugPrint('WebCapture: IDs to try: $idsToTry');

      for (final id in idsToTry) {
        final existingVideo =
            web_capture.WebVideoFrameCapture.findVideoElementByTrackId(id);
        debugPrint('WebCapture: findVideoElementByTrackId($id) returned: ${existingVideo != null}');

        if (existingVideo != null) {
          final capture =
              await web_capture.WebVideoFrameCapture.createFromExistingVideo(
                  existingVideo);
          debugPrint('WebCapture: createFromExistingVideo returned: ${capture != null}');
          if (capture != null) {
            debugPrint('WebCapture: Using existing video for $displayName');
            _webCapture = capture;
            _videoTrack = track;
            capture.startCapture();
            _captureInitialized = true;
            _webCaptureInitializing = false;
            return;
          }
        }
      }

      // Fallback: create a new video element from the MediaStream
      // Try to get jsStream from the MediaStream (MediaStreamWeb on web)
      debugPrint('WebCapture: No existing video found, creating new one for $displayName');
      dynamic jsStream;
      try {
        // track.mediaStream gives us the flutter_webrtc MediaStream
        // On web, this is MediaStreamWeb which has jsStream property
        final mediaStream = track.mediaStream;
        jsStream = (mediaStream as dynamic).jsStream;
        debugPrint('WebCapture: Got jsStream via dynamic access');
      } catch (e) {
        debugPrint('WebCapture: Could not get jsStream: $e');
        // Try jsTrack as a fallback
        try {
          final jsTrack = (mediaStreamTrack as dynamic).jsTrack;
          debugPrint('WebCapture: Got jsTrack, creating stream from it');
          final capture = await web_capture.WebVideoFrameCapture.createFromTrack(jsTrack);
          if (capture != null) {
            _webCapture = capture;
            _videoTrack = track;
            capture.startCapture();
            _captureInitialized = true;
          }
        } catch (e2) {
          debugPrint('WebCapture: Could not get jsTrack either: $e2');
        }
        _webCaptureInitializing = false;
        return;
      }

      // Create video element from the JS MediaStream
      debugPrint('WebCapture: Creating video element from jsStream for $displayName');
      final capture = await web_capture.WebVideoFrameCapture.createFromStream(
        jsStream,
      );

      if (capture == null) {
        debugPrint('WebCapture: Failed to create capture for $displayName');
        _webCaptureInitializing = false;
        return;
      }

      debugPrint('WebCapture: Capture initialized for $displayName');
      _webCapture = capture;
      _videoTrack = track;
      capture.startCapture();
      _captureInitialized = true;
    } catch (e, stackTrace) {
      debugPrint('WebCapture: Error initializing capture: $e');
      debugPrint('WebCapture: Stack: $stackTrace');
      _webCaptureInitializing = false;
    }
  }

  void _initializeNativeCapture() {
    final track = _getVideoTrack();
    if (track == null) return;

    if (_videoTrack == track && _capture != null) {
      return; // Already attached
    }

    _disposeCapture();
    _videoTrack = track;

    // Get the WebRTC track ID (not the LiveKit sid)
    final trackId = track.mediaStreamTrack.id;
    if (trackId == null || trackId.isEmpty) return;

    _capture = ffi.VideoFrameCapture.create(
      trackId,
      targetFps: targetFps,
      maxWidth: 640,
      maxHeight: 480,
    );

    if (_capture != null) {
      _captureInitialized = true;
    }
  }

  void _disposeCapture() {
    // Dispose native capture
    _capture?.dispose();
    _capture = null;

    // Dispose web capture
    if (_webCapture != null) {
      (_webCapture as web_capture.WebVideoFrameCapture).dispose();
      _webCapture = null;
    }

    _videoTrack = null;
    _captureInitialized = false;
  }

  void _checkForNewFrame() {
    if (kIsWeb) {
      _checkForNewWebFrame();
    } else {
      _checkForNewNativeFrame();
    }
  }

  void _checkForNewWebFrame() {
    if (_webCapture == null) return;

    final capture = _webCapture as web_capture.WebVideoFrameCapture;
    if (!capture.hasNewFrame) return;

    // Throttle frame processing
    final now = DateTime.now();
    if (_lastFrameTime != null &&
        now.difference(_lastFrameTime!) < _minFrameInterval) {
      _framesDropped++;
      return;
    }
    _lastFrameTime = now;

    // Get the frame directly (already a ui.Image)
    final newFrame = capture.consumeFrame();
    if (newFrame == null) {
      _framesDropped++;
      return;
    }

    // Swap frames
    final oldFrame = _currentFrame;
    _currentFrame = newFrame;
    _framesCaptured++;
    oldFrame?.dispose();

    // First frame received - no longer loading
    if (_isLoading) {
      _isLoading = false;
    }
  }

  void _checkForNewNativeFrame() {
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
    _processNativeFrame();
  }

  Future<void> _processNativeFrame() async {
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

      // First frame received - no longer loading
      if (_isLoading) {
        _isLoading = false;
      }
    } catch (e) {
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

      // Draw loading spinner overlay if still loading
      if (_isLoading) {
        _drawLoadingSpinner(canvas, center, radius);
      }
    }

    if (_shader == null || !ui.ImageFilter.isShaderFilterSupported) {
      final borderPaint = Paint()
        ..color = _currentFrame != null ? Colors.green : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, borderPaint);
    }
  }

  /// Draw a spinning loading indicator arc
  void _drawLoadingSpinner(Canvas canvas, Offset center, double radius) {
    final spinnerRadius = radius * 0.6;
    final spinnerRect = Rect.fromCircle(center: center, radius: spinnerRadius);

    // Draw a spinning arc
    final spinnerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(_loadingRotation);
    canvas.translate(-center.dx, -center.dy);

    // Draw arc (270 degrees, leaving a gap)
    canvas.drawArc(
      spinnerRect,
      0,
      pi * 1.5, // 270 degrees
      false,
      spinnerPaint,
    );

    canvas.restore();
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
        'captureActive': kIsWeb
            ? (_webCapture as web_capture.WebVideoFrameCapture?)?.isActive ??
                false
            : _capture?.isActive ?? false,
        'targetFps': targetFps,
        'shaderEnabled':
            _shader != null && ui.ImageFilter.isShaderFilterSupported,
        'platform': kIsWeb ? 'web' : (_isMacOS ? 'macOS' : 'other'),
      };
}
