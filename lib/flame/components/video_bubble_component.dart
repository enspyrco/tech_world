import 'dart:math' show cos, pi, sin, sqrt;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:livekit_client/livekit_client.dart';

import '../../events/dispatch.dart';
import '../../events/types.dart' show AvCaptureMethod, AvCaptureInitialized, AvCaptureInitFailed;
import '../../native/frame_source.dart';
import '../../native/video_frame_capture.dart' as ffi;
import '../../native/direct_track_capture.dart' as direct_capture;

final _log = Logger('VideoBubbleComponent');

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
/// Uses MediaStreamTrackProcessor (Chrome) or VideoElement fallback (all browsers):
/// - DirectTrackCapture: MediaStreamTrackProcessor → VideoFrame → canvas → decodeImageFromPixels
/// - VideoElementCapture: HTMLVideoElement → canvas → decodeImageFromPixels
/// - Never uses createImageFromImageBitmap (Skia issue 14637)
///
/// ### Other platforms
/// Falls back to displaying a placeholder with the user's initial.
class VideoBubbleComponent extends PositionComponent {
  VideoBubbleComponent({
    required this.participant,
    required this.displayName,
    this.bubbleSize = 64,
    this.targetFps = 15,
    this.externalVideoCapture,
    this.reduceMotion = false,
  }) : super(
          size: Vector2.all(bubbleSize),
          anchor: Anchor.bottomCenter,
        );

  final Participant participant;
  final String displayName;
  final double bubbleSize;
  final int targetFps;

  /// When true, purely decorative animation (breathing scale, glow pulse,
  /// voice ripples) renders in its resting state. Frame capture, opacity
  /// fading, and the loading spinner are unaffected.
  bool reduceMotion;

  /// Optional external frame source (e.g., [CanvasCapture] from
  /// Dreamfinder's 3D avatar iframe). When provided, bypasses participant
  /// video track discovery and uses this source directly for frame data.
  final FrameSource? externalVideoCapture;

  ui.Image? _currentFrame;

  /// The latest video frame, for use by [MergedVideoBubbleComponent].
  ui.Image? get currentFrame => _currentFrame;

  /// When true, [render] is skipped but [update] continues capturing frames.
  bool _hiddenForMerge = false;
  set hiddenForMerge(bool value) => _hiddenForMerge = value;
  VideoTrack? _videoTrack;

  // Native FFI capture (macOS)
  ffi.VideoFrameCapture? _capture;

  // Web capture - local tracks (MediaStreamTrackProcessor - fast, no DOM)
  direct_capture.DirectTrackCapture? _webCapture;

  // Web capture - remote tracks (HTMLVideoElement - handles buffering)
  direct_capture.VideoElementCapture? _remoteWebCapture;

  // RTCVideoRenderer for remote tracks on web (needed to properly attach to track)
  webrtc.RTCVideoRenderer? _rtcRenderer;

  bool _captureInitialized = false;
  bool _captureInitializing = false; // Prevent duplicate async init attempts
  bool _asyncInitInFlight = false; // Guard async remote capture init (outlives _captureInitializing)

  // Shader support
  ui.FragmentShader? _shader;
  double _time = 0;
  double _glowIntensity = 0.0;
  Color _glowColor = Colors.green;
  double _speakingLevel = 0.0;

  // Breathing animation — sinusoidal scale pulsing
  static const double _breathAmount = 0.025; // ±2.5% scale
  static const double _breathSpeed = 2.0; // cycles per second (radians)

  // ── Cached Paints (Flyweight) ───────────────────────────────────────────

  late final Paint _shadowPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.3)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

  final Paint _layerPaint = Paint();
  final Paint _hologramLinePaint = Paint()..strokeWidth = 1.5;

  // ── Per-frame bubble path (built once in render, reused for clip + border)

  Path? _frameBubblePath;

  // Voice ripple — number of wave lobes around the circle
  static const int _rippleLobes = 8;
  // Max ripple displacement in pixels at full speaking volume.
  // 10px on a 32px-radius bubble = ~30% edge wobble — clearly visible across
  // a populated map without being gaudy.
  static const double _rippleAmplitude = 10.0;
  // Smoothed audio level (lerped toward raw audioLevel each frame)
  double _smoothedAudioLevel = 0.0;

  // Track stats for debugging
  int _framesCaptured = 0;
  int _framesDropped = 0;
  double _timeSinceLastFrame = 0;
  static const double _minFrameIntervalSeconds = 0.05; // 20 fps cap

  // Guard against concurrent async frame decodes
  bool _nativeFrameInFlight = false;

  // Retry tracking for capture initialization
  int _captureRetryCount = 0;
  static const int _maxCaptureRetries = 10;
  double _timeSinceLastRetry = 0;
  static const double _retryIntervalSeconds = 0.5; // Retry every 500ms

  // ── Diagnostic getters (read by BubbleManager for AvPipelineSnapshot) ──

  /// Which capture path is active, or null if not yet initialized.
  AvCaptureMethod? get diagnosticCaptureMethod {
    if (externalVideoCapture != null) return AvCaptureMethod.canvasCapture;
    if (_capture != null) return AvCaptureMethod.ffi;
    if (_webCapture != null) return AvCaptureMethod.directTrack;
    if (_remoteWebCapture != null) return AvCaptureMethod.videoElement;
    return null;
  }

  int get diagnosticCaptureRetryCount => _captureRetryCount;
  int get diagnosticFramesCaptured => _framesCaptured;
  int get diagnosticFramesDropped => _framesDropped;

  // Opacity for distance-based fading
  double _opacity = 1.0;

  /// Optional loading progress (0–100) shown in the spinner.
  /// Set by the parent when the avatar GLB is downloading.
  int? loadingProgress;

  /// Set the opacity for distance-based fading (0.0 to 1.0).
  set opacity(double value) => _opacity = value.clamp(0.0, 1.0);

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

  @visibleForTesting
  VideoTrack? get selectedVideoTrackForTesting => _getVideoTrack();

  /// Notify that the video track is ready (called when track subscription event fires)
  /// This triggers immediate capture initialization instead of waiting for retry timer.
  void notifyTrackReady() {
    if (!_captureInitialized && externalVideoCapture == null) {
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

    // Try to initialize capture if not yet done (with retry backoff).
    // Skip when using an external canvas capture — it manages its own lifecycle.
    if (externalVideoCapture == null &&
        !_captureInitialized &&
        _captureRetryCount < _maxCaptureRetries) {
      _timeSinceLastRetry += dt;
      if (_timeSinceLastRetry >= _retryIntervalSeconds) {
        _timeSinceLastRetry = 0;
        _initializeCapture();
        // Dispatch failure event when retries are exhausted.
        if (!_captureInitialized &&
            _captureRetryCount >= _maxCaptureRetries) {
          dispatch([AvCaptureInitFailed(
            participant: participant.identity,
            maxRetries: _maxCaptureRetries,
          )]);
        }
      }
    }

    // Poll audio level from the LiveKit participant each frame.
    // Smooth with lerp to avoid jitter from the raw VAD signal.
    final rawLevel = participant.audioLevel;
    _smoothedAudioLevel +=
        (rawLevel - _smoothedAudioLevel) * (dt * 12.0).clamp(0.0, 1.0);
    _speakingLevel = _smoothedAudioLevel;

    // Check for new frames
    _timeSinceLastFrame += dt;
    _checkForNewFrame();
  }

  void _initializeCapture() {
    if (_captureInitialized) return;
    if (_captureInitializing) {
      return; // Already initializing, don't start another
    }
    if (_asyncInitInFlight) return; // Async remote init still running

    _captureRetryCount++;
    _captureInitializing = true;

    try {
      if (kIsWeb) {
        _initializeWebCapture();
      } else if (_isMacOS) {
        _initializeNativeCapture();
      } else {
        // Unsupported platform
        _captureInitialized = true;
      }
    } finally {
      _captureInitializing = false;
    }
  }

  void _initializeWebCapture() {
    final track = _getVideoTrack();
    if (track == null) {
      _log.fine('$displayName: no video track found');
      return;
    }

    final mediaStreamTrack = track.mediaStreamTrack;
    final isRemote = participant is! LocalParticipant;
    _log.fine('$displayName: initializing (isRemote=$isRemote, trackId=${mediaStreamTrack.id})');

    // Get the underlying JS MediaStreamTrack via the conditional import helper.
    // This avoids importing dart_webrtc directly (which pulls in dart:js_interop
    // and breaks native tests).
    final jsTrack = direct_capture.getJsTrack(mediaStreamTrack);
    if (jsTrack == null) {
      _log.fine('$displayName: mediaStreamTrack is ${mediaStreamTrack.runtimeType}, cannot extract JS track');
      return;
    }
    _log.fine('$displayName: got jsTrack (isRemote=$isRemote)');

    // Use DirectTrackCapture (MediaStreamTrackProcessor) for ALL tracks.
    _initializeLocalWebCapture(jsTrack, track);
  }

  void _initializeLocalWebCapture(Object jsTrack, VideoTrack track) {
    final supported = direct_capture.isMediaStreamTrackProcessorSupported;
    _log.fine('$displayName: MediaStreamTrackProcessor supported=$supported');

    if (!supported) {
      _log.fine('$displayName: falling back to VideoElementCapture');
      _initializeRemoteWebCapture(jsTrack, track);
      return;
    }

    final capture = direct_capture.DirectTrackCapture.create(jsTrack);
    if (capture == null) {
      _log.fine('$displayName: DirectTrackCapture.create RETURNED NULL');
      _captureInitializing = false;
      return;
    }

    _log.fine('$displayName: DirectTrackCapture created, starting capture');
    _webCapture = capture;
    _videoTrack = track;
    capture.startCapture();
    _captureInitialized = true;
    _captureInitializing = false;
    dispatch([AvCaptureInitialized(
      participant: participant.identity,
      method: AvCaptureMethod.directTrack,
      retryCount: _captureRetryCount,
    )]);
  }

  /// Initialize capture for remote tracks using VideoElementCapture.
  ///
  /// Creates a hidden video element and attaches the track's MediaStream to it.
  /// This is more reliable than RTCVideoRenderer for capturing frames.
  void _initializeRemoteWebCapture(Object jsTrack, VideoTrack track) {
    _asyncInitInFlight = true;
    _initializeRemoteWebCaptureAsync(jsTrack, track);
  }

  Future<void> _initializeRemoteWebCaptureAsync(
      Object jsTrack, VideoTrack track) async {
    try {
      _videoTrack = track;

      // Use the mediaStreamTrack directly (not mediaStream which may be stale)
      // jsTrack is already the JS MediaStreamTrack
      _log.fine('Creating VideoElementCapture from jsTrack for $displayName');

      // Try VideoElementCapture with just the track (it will create a fresh MediaStream)
      // This now waits for the video to be ready before returning
      final capture = await direct_capture.VideoElementCapture.createFromStream(
          null, jsTrack);
      if (capture != null) {
        _log.fine('VideoElementCapture created for remote track $displayName');
        _remoteWebCapture = capture;
        capture.startCapture();
        _captureInitialized = true;
        _captureInitializing = false;
        dispatch([AvCaptureInitialized(
          participant: participant.identity,
          method: AvCaptureMethod.videoElement,
          retryCount: _captureRetryCount,
        )]);
        return;
      }

      _log.warning('Failed to create VideoElementCapture for $displayName');
      _captureInitializing = false;
    } catch (e, stack) {
      _log.warning('Error initializing remote capture: $e\nStack: $stack');
      _captureInitializing = false;
    } finally {
      _asyncInitInFlight = false;
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
      dispatch([AvCaptureInitialized(
        participant: participant.identity,
        method: AvCaptureMethod.ffi,
        retryCount: _captureRetryCount,
      )]);
    }
  }

  void _disposeCapture() {
    // Dispose native capture
    _capture?.dispose();
    _capture = null;

    // Cancel any pending unmute wait before disposing (avoids orphaned completer).
    _webCapture?.cancelPendingUnmute();
    _webCapture?.dispose();
    _webCapture = null;

    _remoteWebCapture?.dispose();
    _remoteWebCapture = null;

    // Dispose RTCVideoRenderer
    _rtcRenderer?.srcObject = null;
    _rtcRenderer?.dispose();
    _rtcRenderer = null;

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
    // Check external canvas capture (e.g., Dreamfinder 3D avatar)
    if (externalVideoCapture != null && externalVideoCapture!.hasNewFrame) {
      _processWebFrame(externalVideoCapture!.consumeFrame());
      return;
    }

    // Check local capture (DirectTrackCapture)
    if (_webCapture != null && _webCapture!.hasNewFrame) {
      _processWebFrame(_webCapture!.consumeFrame());
      return;
    }

    // Check remote capture (VideoElementCapture)
    if (_remoteWebCapture != null && _remoteWebCapture!.hasNewFrame) {
      _processWebFrame(_remoteWebCapture!.consumeFrame());
      return;
    }
  }

  void _processWebFrame(ui.Image? newFrame) {
    if (newFrame == null) {
      _framesDropped++;
      return;
    }

    // Throttle frame processing using dt accumulator.
    if (_timeSinceLastFrame < _minFrameIntervalSeconds) {
      _framesDropped++;
      newFrame.dispose();
      return;
    }
    _timeSinceLastFrame = 0;

    // Swap frames — defer old frame disposal so CanvasKit can finish
    // any in-progress render pass that references the texture.
    final oldFrame = _currentFrame;
    _currentFrame = newFrame;
    _framesCaptured++;
    if (oldFrame != null) {
      Future.microtask(() => oldFrame.dispose());
    }

    // First frame received - no longer loading
    if (_isLoading) {
      _isLoading = false;
    }
  }

  void _checkForNewNativeFrame() {
    if (_capture == null) return;

    // Check if a new frame is available
    if (!_capture!.hasNewFrame) return;

    // Throttle frame processing using dt accumulator.
    if (_timeSinceLastFrame < _minFrameIntervalSeconds) {
      _framesDropped++;
      return;
    }
    _timeSinceLastFrame = 0;

    // Process the frame
    _processNativeFrame();
  }

  Future<void> _processNativeFrame() async {
    if (_capture == null || _nativeFrameInFlight) return;
    _nativeFrameInFlight = true;
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

      // Convert BGRA to RGBA before releasing the shared buffer.
      // markConsumed() must come AFTER the byte copy so the ObjC producer
      // cannot overwrite pixels while _bgraToRgba is still reading them.
      final rgbaBytes = _bgraToRgba(bgraBytes);

      // Mark the frame as consumed so native can write the next one
      _capture!.markConsumed();

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
    } finally {
      _nativeFrameInFlight = false;
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
    final publications = participant.videoTrackPublications;

    VideoTrack? videoTrackFrom(TrackPublication publication) {
      final track = publication.track;
      if (track is VideoTrack && track.kind == TrackType.VIDEO) {
        return track;
      }
      return null;
    }

    for (final publication in publications) {
      if (publication.source == TrackSource.camera) {
        final track = videoTrackFrom(publication);
        if (track != null) return track;
      }
    }

    for (final publication in publications) {
      if (!publication.isScreenShare) {
        final track = videoTrackFrom(publication);
        if (track != null) return track;
      }
    }

    for (final publication in publications) {
      final track = videoTrackFrom(publication);
      if (track != null) return track;
    }

    return null;
  }

  Future<ui.Image> _decodeRgbaImage(
      Uint8List bytes, int width, int height) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      try {
        final codec = await descriptor.instantiateCodec();
        try {
          final frameInfo = await codec.getNextFrame();
          return frameInfo.image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
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
    if (_opacity <= 0 || _hiddenForMerge) return;

    final center = Offset(size.x / 2, size.y / 2);
    final radius = bubbleSize / 2;

    // ── Breathing: scale the entire bubble around its centre ──
    // Resting state (scale 1.0) when reduce-motion is on.
    final breathScale =
        reduceMotion ? 1.0 : 1.0 + _breathAmount * sin(_time * _breathSpeed);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(breathScale);
    canvas.translate(-center.dx, -center.dy);

    // Apply opacity via saveLayer when not fully opaque
    if (_opacity < 1.0) {
      _layerPaint.color =
          Color.fromARGB((_opacity * 255).round(), 255, 255, 255);
      canvas.saveLayer(
        Rect.fromCircle(center: center, radius: radius + 10),
        _layerPaint,
      );
    }

    // Draw shadow (skip when glowing — the glow replaces the shadow)
    if (_glowIntensity <= 0) {
      canvas.drawCircle(center + const Offset(0, 2), radius, _shadowPaint);
    }

    // ── Radial glow ──────────────────────────────────────
    // Draws a soft halo behind the video circle. Intensity and color
    // are set per-bubble (e.g. gold for Dreamfinder, green for players).
    if (_glowIntensity > 0 && _currentFrame != null) {
      // Resting glow (no pulse) when reduce-motion is on.
      final glowPulse = reduceMotion ? 1.0 : 1.0 + 0.15 * sin(_time * 2.5);
      final glowRadius = radius + 8.0 * _glowIntensity * glowPulse;
      final glowPaint = Paint()
        ..color = _glowColor.withValues(alpha: 0.45 * _glowIntensity * glowPulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12.0 * _glowIntensity);
      canvas.drawCircle(center, glowRadius, glowPaint);

      // Inner bright ring at the bubble edge
      final ringPaint = Paint()
        ..color = _glowColor.withValues(alpha: 0.3 * _glowIntensity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(center, radius + 1, ringPaint);
    }

    if (_currentFrame != null) {
      _updateShaderUniforms();

      final paint = Paint();
      // Shader disabled — investigating black frame issue.
      // TODO: re-enable once frame capture is verified working.
      // if (_shader != null && ui.ImageFilter.isShaderFilterSupported) {
      //   paint.imageFilter = ui.ImageFilter.shader(_shader!);
      // }

      canvas.saveLayer(
        Rect.fromCircle(center: center, radius: radius + 10),
        paint,
      );

      // Build the bubble path once per frame, reuse for clip and border.
      _frameBubblePath = _buildBubblePath(center, radius);

      canvas.save();
      canvas.clipPath(_frameBubblePath!);

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
      // Fallback: draw placeholder with hologram boot effect during download
      canvas.save();
      final clipPath = Path()
        ..addOval(Rect.fromCircle(center: center, radius: radius));
      canvas.clipPath(clipPath);

      final bgPaint = Paint()..color = const Color(0xFF0A0A1A);
      canvas.drawCircle(center, radius, bgPaint);

      if (_isLoading && loadingProgress != null && loadingProgress! > 0) {
        // Hologram boot: scan lines fill up as download progresses
        _drawHologramBoot(canvas, center, radius);
      } else {
        // Static initial
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

      if (_isLoading) {
        _drawLoadingSpinner(canvas, center, radius);
      }
    }

    // Always draw a thin border at the bubble edge. For player bubbles with
    // glowIntensity = 0 this is the only edge affordance; for DF it sits on
    // top of the radial gold halo as a crisp inner ring.
    final borderPaint = Paint()
      ..color = _currentFrame != null ? _glowColor : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // Reuse the path built earlier, or build fresh if we took the no-video branch.
    final path = _frameBubblePath ?? _buildBubblePath(center, radius);
    canvas.drawPath(path, borderPaint);

    if (_opacity < 1.0) {
      canvas.restore();
    }

    // ── End breathing transform ──
    canvas.restore();
  }

  /// Draw a spinning loading indicator arc with optional progress text.
  void _drawLoadingSpinner(Canvas canvas, Offset center, double radius) {
    final spinnerRadius = radius * 0.6;
    final spinnerRect = Rect.fromCircle(center: center, radius: spinnerRadius);

    final spinnerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(_loadingRotation);
    canvas.translate(-center.dx, -center.dy);

    // Draw arc — if progress is known and > 0, show proportional arc.
    // Otherwise show the default spinning 270° arc.
    final hasProgress = loadingProgress != null && loadingProgress! > 0;
    final arcExtent = hasProgress
        ? pi * 2 * (loadingProgress! / 100).clamp(0.01, 1.0)
        : pi * 1.5;
    canvas.drawArc(spinnerRect, 0, arcExtent, false, spinnerPaint);
    canvas.restore();

    // Draw progress percentage text
    if (loadingProgress != null) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: '$loadingProgress%',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: radius * 0.35,
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
      textPainter.dispose();
    }
  }

  /// Draw a hologram materializing effect — scan lines fill the bubble
  /// from bottom to top as the avatar GLB downloads.
  void _drawHologramBoot(Canvas canvas, Offset center, double radius) {
    final progress = (loadingProgress ?? 0) / 100.0;
    final diameter = radius * 2;
    final lineSpacing = 3.0;
    final totalLines = (diameter / lineSpacing).ceil();
    final revealedLines = (totalLines * progress).ceil();

    // Gold hologram color
    const baseColor = Color(0xFFDAA520);

    for (int i = 0; i < revealedLines; i++) {
      // Draw from bottom up
      final y = center.dy + radius - (i * lineSpacing);
      if (y < center.dy - radius) break;

      // Calculate horizontal extent at this y (circle geometry)
      final dy = (y - center.dy).abs();
      if (dy > radius) continue;
      final halfWidth = sqrt(radius * radius - dy * dy);

      // Lines near the reveal edge shimmer
      final distFromEdge = (revealedLines - i).toDouble();
      final shimmer = distFromEdge < 5
          ? 0.3 + 0.7 * sin(_time * 8 + i * 0.5).abs()
          : 0.4 + 0.3 * sin(_time * 2 + i * 0.3).abs();

      _hologramLinePaint.color = baseColor.withValues(alpha: shimmer * 0.8);

      canvas.drawLine(
        Offset(center.dx - halfWidth, y),
        Offset(center.dx + halfWidth, y),
        _hologramLinePaint,
      );
    }

    // Progress text
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$loadingProgress%',
        style: TextStyle(
          color: baseColor.withValues(alpha: 0.9),
          fontSize: radius * 0.4,
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
    textPainter.dispose();
  }

  /// Build a circular path whose radius undulates when someone is speaking.
  ///
  /// When [_speakingLevel] is 0 the path is a perfect circle.
  /// As audio level rises, sinusoidal lobes appear around the edge,
  /// animated over time so the ripple *moves*.
  Path _buildBubblePath(Offset center, double radius) {
    if (reduceMotion || _speakingLevel < 0.01) {
      // No audio (or reduce-motion gating the ripple) — fast path, plain circle.
      return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    }

    final path = Path();
    // 64 segments is smooth enough for a ~32px radius circle.
    const segments = 64;
    final amplitude = _rippleAmplitude * _speakingLevel;

    for (int i = 0; i <= segments; i++) {
      final angle = (i / segments) * 2.0 * pi;
      // Two wave frequencies for organic feel.
      final wave1 = sin(angle * _rippleLobes + _time * 6.0) * amplitude;
      final wave2 = sin(angle * (_rippleLobes + 3) - _time * 4.0) * amplitude * 0.4;
      final r = radius + wave1 + wave2;
      final x = center.dx + cos(angle) * r;
      final y = center.dy + sin(angle) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
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
        'captureInitializing': _captureInitializing,
        'captureRetryCount': _captureRetryCount,
        'captureActive': kIsWeb
            ? (_webCapture?.isActive ?? _remoteWebCapture?.isActive ?? false)
            : _capture?.isActive ?? false,
        'captureType': kIsWeb
            ? (_webCapture != null
                ? 'DirectTrack'
                : (_remoteWebCapture != null ? 'VideoElement' : 'none'))
            : (_capture != null ? 'FFI' : 'none'),
        'targetFps': targetFps,
        'shaderEnabled':
            _shader != null && ui.ImageFilter.isShaderFilterSupported,
        'platform': kIsWeb ? 'web' : (_isMacOS ? 'macOS' : 'other'),
      };
}
