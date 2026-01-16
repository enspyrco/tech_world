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
/// as a circular clipped image in the game world, with optional shader effects.
///
/// ## Implementation
///
/// Uses frame capture approach for full Flame integration:
/// - Captures RGBA frames from MediaStreamTrack.captureFrame()
/// - Converts to dart:ui.Image for rendering
/// - Can apply custom fragment shaders via ImageFilter.shader (Impeller)
/// - Supports physics, particles, occlusion - full game object
///
/// ## Shader Effects
///
/// With Impeller (now default), custom fragment shaders can be applied:
/// - Glow effects when speaking
/// - Color grading / tinting
/// - Distortion effects
/// - Any GPU-accelerated pixel manipulation
///
/// Load a shader and pass it to enable effects:
/// ```dart
/// final program = await FragmentProgram.fromAsset('shaders/video_bubble.frag');
/// videoBubble.setShader(program.fragmentShader());
/// ```
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

  // Shader support
  ui.FragmentShader? _shader;
  double _time = 0;
  double _glowIntensity = 0.5;
  Color _glowColor = Colors.green;
  double _speakingLevel = 0.0;

  // Track stats for debugging
  int _framesCaptured = 0;
  int _framesDropped = 0;

  /// Set a custom fragment shader for effects.
  ///
  /// The shader should follow ImageFilter.shader requirements:
  /// - First uniform: vec2 u_size
  /// - At least one sampler2D uniform
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
    _startFrameCapture();
  }

  @override
  void onRemove() {
    _stopFrameCapture();
    _currentFrame?.dispose();
    _currentFrame = null;
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
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

  void _updateShaderUniforms() {
    if (_shader == null) return;

    // Update shader uniforms
    // Index 0-1: u_size (vec2) - required by ImageFilter.shader
    _shader!.setFloat(0, bubbleSize);
    _shader!.setFloat(1, bubbleSize);

    // Index 2: u_time
    _shader!.setFloat(2, _time);

    // Index 3: u_glow_intensity
    _shader!.setFloat(3, _glowIntensity);

    // Index 4-6: u_glow_color (vec3)
    _shader!.setFloat(4, _glowColor.r);
    _shader!.setFloat(5, _glowColor.g);
    _shader!.setFloat(6, _glowColor.b);

    // Index 7: u_speaking
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
      // Update shader uniforms if shader is set
      _updateShaderUniforms();

      // Create paint with optional shader filter
      final paint = Paint();

      // Apply shader via ImageFilter if available and supported
      if (_shader != null && ui.ImageFilter.isShaderFilterSupported) {
        paint.imageFilter = ui.ImageFilter.shader(_shader!);
      }

      // Use saveLayer to apply the shader to the entire video rendering
      canvas.saveLayer(
        Rect.fromCircle(center: center, radius: radius + 10), // Extra for glow
        paint,
      );

      // Clip to circle for video
      canvas.save();
      final clipPath = Path()
        ..addOval(Rect.fromCircle(center: center, radius: radius));
      canvas.clipPath(clipPath);

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

      canvas.restore(); // Restore from clip
      canvas.restore(); // Restore from saveLayer (applies shader)
    } else {
      // Fallback: draw colored background with initial (like PlayerBubbleComponent)
      canvas.save();
      final clipPath = Path()
        ..addOval(Rect.fromCircle(center: center, radius: radius));
      canvas.clipPath(clipPath);

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

      canvas.restore();
    }

    // Draw border (outside the clip) - only if no shader (shader handles its own border/glow)
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
        'targetFps': targetFps,
        'shaderEnabled':
            _shader != null && ui.ImageFilter.isShaderFilterSupported,
      };
}
