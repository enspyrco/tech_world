import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Maximum number of bubbles the metaball shader supports.
const int maxBubbles = 8;

/// Padding around the bounding box of all bubbles, in pixels.
/// Must be large enough for the glow to render without clipping.
const double _fieldPadding = 80.0;

/// Renders a metaball energy field connecting nearby video bubbles.
///
/// This component sits below individual [VideoBubbleComponent]s in the
/// render order. It draws a merged glow using a fragment shader — when
/// two bubbles are close, their energy fields add up and the glow
/// organically bridges them.
///
/// Usage:
/// ```dart
/// final field = BubbleFieldComponent(shaderProgram: program);
/// add(field);
/// // Each frame:
/// field.updateBubblePositions(positions);
/// ```
class BubbleFieldComponent extends PositionComponent {
  BubbleFieldComponent({
    required ui.FragmentProgram shaderProgram,
    this.glowColor = const Color(0xFF00FF88),
    this.bubbleRadius = 32.0,
  }) : _shader = shaderProgram.fragmentShader();

  final ui.FragmentShader _shader;

  /// The glow color of the energy field.
  Color glowColor;

  /// Radius of each individual bubble (half of bubbleSize).
  double bubbleRadius;

  double _time = 0;

  /// Current bubble positions in world coordinates.
  final List<Vector2> _bubblePositions = [];

  /// Update the list of bubble centre positions (world coordinates).
  ///
  /// Call this every frame from [TechWorld._updateBubblePositions].
  void updateBubblePositions(List<Vector2> positions) {
    _bubblePositions
      ..clear()
      ..addAll(positions.take(maxBubbles));
    _updateBounds();
  }

  /// Recompute component position & size to tightly wrap all bubbles.
  void _updateBounds() {
    if (_bubblePositions.isEmpty) return;

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final pos in _bubblePositions) {
      minX = min(minX, pos.x);
      minY = min(minY, pos.y);
      maxX = max(maxX, pos.x);
      maxY = max(maxY, pos.y);
    }

    // Expand by bubble radius + glow padding.
    final pad = bubbleRadius + _fieldPadding;
    position = Vector2(minX - pad, minY - pad);
    size = Vector2(maxX - minX + pad * 2, maxY - minY + pad * 2);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  @override
  void render(Canvas canvas) {
    if (_bubblePositions.length < 2) return; // need ≥2 to merge

    final w = size.x;
    final h = size.y;
    if (w <= 0 || h <= 0) return;

    // ── Set uniforms ──────────────────────────────────────
    int i = 0;
    _shader.setFloat(i++, w); // u_size.x
    _shader.setFloat(i++, h); // u_size.y
    _shader.setFloat(i++, _time); // u_time
    _shader.setFloat(i++, _bubblePositions.length.toDouble()); // u_count
    _shader.setFloat(i++, glowColor.r); // u_color.r
    _shader.setFloat(i++, glowColor.g); // u_color.g
    _shader.setFloat(i++, glowColor.b); // u_color.b
    _shader.setFloat(i++, bubbleRadius); // u_bubble_radius

    // Bubble positions — transformed from world coords to local coords.
    for (int b = 0; b < maxBubbles; b++) {
      if (b < _bubblePositions.length) {
        _shader.setFloat(i++, _bubblePositions[b].x - position.x);
        _shader.setFloat(i++, _bubblePositions[b].y - position.y);
      } else {
        // Park unused bubbles off-screen so they contribute zero field.
        _shader.setFloat(i++, -9999.0);
        _shader.setFloat(i++, -9999.0);
      }
    }

    // ── Draw ──────────────────────────────────────────────
    final paint = Paint()
      ..shader = _shader
      ..blendMode = BlendMode.plus; // additive — glow only brightens

    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
  }
}
