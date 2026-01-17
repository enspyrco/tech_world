import 'dart:math' show sin;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// A test component to verify shader effects work without needing LiveKit.
///
/// This renders a colored gradient as a "fake video" and applies the shader.
/// Use this to test the shader pipeline before integrating real video.
class TestShaderBubble extends PositionComponent {
  TestShaderBubble({
    this.bubbleSize = 80,
    Vector2? position,
  }) : super(
          size: Vector2.all(bubbleSize),
          position: position ?? Vector2.zero(),
          anchor: Anchor.center,
        );

  final double bubbleSize;

  // Shader support
  ui.FragmentShader? _shader;
  double _time = 0;
  double _glowIntensity = 0.7;
  Color _glowColor = Colors.cyan;
  double _speakingLevel = 0.0;

  // For animated test
  bool animateSpeaking = true;

  /// Set a custom fragment shader for effects.
  void setShader(ui.FragmentShader shader) {
    _shader = shader;
  }

  set glowIntensity(double value) => _glowIntensity = value.clamp(0.0, 1.0);
  set glowColor(Color value) => _glowColor = value;
  set speakingLevel(double value) => _speakingLevel = value.clamp(0.0, 1.0);

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;

    // Animate speaking level for testing
    if (animateSpeaking) {
      _speakingLevel = (0.5 + 0.5 * sin(_time * 2)).clamp(0.0, 1.0);
    }
  }

  void _updateShaderUniforms() {
    if (_shader == null) return;

    // Index 0-1: u_size (vec2)
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

    // Update shader uniforms
    _updateShaderUniforms();

    // Create paint with optional shader filter
    final paint = Paint();

    // Apply shader via ImageFilter if available and supported
    if (_shader != null && ui.ImageFilter.isShaderFilterSupported) {
      paint.imageFilter = ui.ImageFilter.shader(_shader!);
    }

    // Use saveLayer to apply the shader
    canvas.saveLayer(
      Rect.fromCircle(center: center, radius: radius + 15), // Extra for glow
      paint,
    );

    // Clip to circle
    canvas.save();
    final clipPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.clipPath(clipPath);

    // Draw a gradient as fake "video" content
    final gradient = RadialGradient(
      colors: [
        Colors.blue[300]!,
        Colors.purple[400]!,
        Colors.pink[300]!,
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    final gradientPaint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      );
    canvas.drawCircle(center, radius, gradientPaint);

    // Draw a simple face to make it more interesting
    final facePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Eyes
    canvas.drawCircle(Offset(center.dx - 12, center.dy - 8), 6, facePaint);
    canvas.drawCircle(Offset(center.dx + 12, center.dy - 8), 6, facePaint);

    // Pupils (animate based on time)
    final pupilPaint = Paint()..color = Colors.black;
    final pupilOffset = 2 * sin(_time * 0.5);
    canvas.drawCircle(
        Offset(center.dx - 12 + pupilOffset, center.dy - 8), 3, pupilPaint);
    canvas.drawCircle(
        Offset(center.dx + 12 + pupilOffset, center.dy - 8), 3, pupilPaint);

    // Mouth (animate based on speaking level)
    final mouthHeight = 4 + 8 * _speakingLevel;
    final mouthRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + 12),
        width: 20,
        height: mouthHeight,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(mouthRect, facePaint);

    canvas.restore(); // Restore from clip
    canvas.restore(); // Restore from saveLayer (applies shader)

    // Draw border if no shader
    if (_shader == null || !ui.ImageFilter.isShaderFilterSupported) {
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, borderPaint);
    }

    // Debug text showing shader status
    final textPainter = TextPainter(
      text: TextSpan(
        text: _shader != null && ui.ImageFilter.isShaderFilterSupported
            ? 'Shader ON'
            : 'No Shader',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(blurRadius: 2, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy + radius + 5),
    );
  }
}
