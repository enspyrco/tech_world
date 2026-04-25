import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'video_bubble_component.dart';

/// Maximum number of video bubbles the merged shader supports.
const int maxMergedBubbles = 4;

/// Padding around the bounding box of merged bubbles, in pixels.
const double _mergedPadding = 80.0;

/// Renders merged video content inside an organic metaball-shaped blob.
///
/// When 2+ [VideoBubbleComponent]s are close enough, this component
/// replaces their individual rendering. It reads [currentFrame] from
/// each source bubble and passes the textures to a GLSL shader that
/// computes the metaball boundary and samples the nearest bubble's
/// video for each pixel, with smooth Voronoi blending at boundaries.
///
/// The source bubbles continue capturing frames ([update] runs) but
/// skip [render] via [VideoBubbleComponent.hiddenForMerge].
class MergedVideoBubbleComponent extends PositionComponent {
  MergedVideoBubbleComponent({
    required ui.FragmentProgram shaderProgram,
    this.glowColor = const Color(0xFF00FF88),
    this.bubbleRadius = 32.0,
  }) : _shader = shaderProgram.fragmentShader();

  final ui.FragmentShader _shader;

  /// Glow colour for the merged boundary edge.
  Color glowColor;

  /// Individual bubble radius (half of bubbleSize).
  double bubbleRadius;

  double _time = 0;

  /// Source bubbles providing video frames and world positions.
  final List<VideoBubbleComponent> _sources = [];

  /// Lazily created 1×1 transparent image used when a source has no frame.
  static ui.Image? _placeholder;

  /// Update the set of source bubbles participating in the merge.
  void updateSources(List<VideoBubbleComponent> sources) {
    _sources
      ..clear()
      ..addAll(sources.take(maxMergedBubbles));
  }

  /// World-space positions of the merged bubbles (set externally by TechWorld).
  final List<Vector2> _positions = [];

  void updatePositions(List<Vector2> positions) {
    _positions
      ..clear()
      ..addAll(positions.take(maxMergedBubbles));
    _updateBounds();
  }

  void _updateBounds() {
    if (_positions.isEmpty) return;

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final pos in _positions) {
      minX = min(minX, pos.x);
      minY = min(minY, pos.y);
      maxX = max(maxX, pos.x);
      maxY = max(maxY, pos.y);
    }

    final pad = bubbleRadius + _mergedPadding;
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
    if (_sources.length < 2) return;

    final w = size.x;
    final h = size.y;
    if (w <= 0 || h <= 0) return;

    // Ensure placeholder exists for sources without frames.
    _placeholder ??= _createPlaceholder();

    // ── Float uniforms ────────────────────────────────────
    int fi = 0;
    _shader.setFloat(fi++, w); // u_size.x
    _shader.setFloat(fi++, h); // u_size.y
    _shader.setFloat(fi++, _time); // u_time
    _shader.setFloat(fi++, _sources.length.toDouble()); // u_count
    _shader.setFloat(fi++, bubbleRadius); // u_bubble_radius
    _shader.setFloat(fi++, glowColor.r); // u_glow_color.r
    _shader.setFloat(fi++, glowColor.g); // u_glow_color.g
    _shader.setFloat(fi++, glowColor.b); // u_glow_color.b

    // Bubble positions (local coords).
    for (int b = 0; b < maxMergedBubbles; b++) {
      if (b < _positions.length) {
        _shader.setFloat(fi++, _positions[b].x - position.x);
        _shader.setFloat(fi++, _positions[b].y - position.y);
      } else {
        _shader.setFloat(fi++, -9999.0);
        _shader.setFloat(fi++, -9999.0);
      }
    }

    // Video dimensions.
    for (int b = 0; b < maxMergedBubbles; b++) {
      final frame =
          b < _sources.length ? _sources[b].currentFrame : null;
      _shader.setFloat(fi++, frame?.width.toDouble() ?? 1.0);
      _shader.setFloat(fi++, frame?.height.toDouble() ?? 1.0);
    }

    // ── Image samplers ────────────────────────────────────
    for (int b = 0; b < maxMergedBubbles; b++) {
      final frame =
          b < _sources.length ? _sources[b].currentFrame : null;
      _shader.setImageSampler(b, frame ?? _placeholder!);
    }

    // ── Draw ──────────────────────────────────────────────
    final paint = Paint()..shader = _shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
  }

  /// Create a 1×1 transparent image for empty sampler slots.
  static ui.Image _createPlaceholder() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawPaint(Paint()..color = const Color(0x00000000));
    final picture = recorder.endRecording();
    return picture.toImageSync(1, 1);
  }
}
