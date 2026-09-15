import 'dart:math';

import 'package:flame/components.dart';

/// Soft-body repulsion that keeps proximity bubbles from stacking on top of
/// each other.
///
/// Each bubble is tethered to its owning character's position; this applies a
/// per-frame *displacement* on top of that anchor rather than moving bubbles
/// freely. That distinction is the whole design: a bubble can be nudged aside
/// by a crowd but is always pulled back toward the character it belongs to, so
/// it never drifts far enough to be read as someone else's.
///
/// Pure geometry over whatever components it is handed — it knows nothing
/// about video, audio, proximity or LiveKit.
class BubblePhysics {
  /// Bubbles closer than this push each other apart.
  static const double bubbleDiameter = 64.0;

  /// Hard cap on how far a bubble can sit from its anchor, in pixels. Even a
  /// large single-frame impulse cannot exceed it.
  static const double maxTetherDistance = 24.0;

  /// Per-frame decay applied to accumulated displacement, so a bubble returns
  /// to its anchor once the crowd disperses.
  static const double repulsionDamping = 0.85;

  /// 0.5 (base strength) / 0.016 (60 fps reference dt).
  static const double repulsionForceCoefficient = 31.25;

  /// Longest frame the solver will integrate over. A frame spike (a stalled
  /// tab, a slow first render) would otherwise be multiplied straight into
  /// displacement and fling every bubble to its tether limit at once.
  static const double maxIntegrationStep = 0.05;

  /// Accumulated displacement per bubble key, persisted across frames so
  /// damping has something to decay.
  final Map<String, Vector2> _displacements = {};

  /// Push apart any pair of [bubbles] closer than [bubbleDiameter], then apply
  /// the accumulated displacement to their positions.
  ///
  /// Call *after* positions have been set from their owning characters — this
  /// adds an offset to the anchor, it does not compute the anchor.
  void apply(Map<String, PositionComponent> bubbles, double dt) {
    final entries = bubbles.entries.toList();
    // Below two there is nothing to repel against. Note this returns BEFORE
    // the stale-key sweep below, so displacement for a departed bubble can
    // outlive it until the next frame that has a crowd. Bounded and transient
    // (teardown calls [clear]), and preserved deliberately from the original
    // in-BubbleManager version rather than "fixed" during a refactor.
    if (entries.length < 2) return;

    _displacements.removeWhere((k, _) => !bubbles.containsKey(k));

    final forces = <String, Vector2>{};
    for (var i = 0; i < entries.length; i++) {
      for (var j = i + 1; j < entries.length; j++) {
        final delta = entries[i].value.center - entries[j].value.center;
        final dist = delta.length;
        // The `> 0.01` guard suppresses jitter, not NaN — `Vector2.normalized()`
        // already returns zero for a zero-length vector, so exact overlap is
        // safe on its own. The hazard is the band just above zero: direction is
        // numerically arbitrary there while `overlap` is at its maximum, so two
        // near-co-located bubbles would fire a full-strength push along a
        // direction that flips every frame.
        if (dist < bubbleDiameter && dist > 0.01) {
          final push = delta.normalized() *
              ((bubbleDiameter - dist) *
                  repulsionForceCoefficient *
                  min(dt, maxIntegrationStep));
          forces[entries[i].key] =
              (forces[entries[i].key] ?? Vector2.zero()) + push;
          forces[entries[j].key] =
              (forces[entries[j].key] ?? Vector2.zero()) - push;
        }
      }
    }

    for (final entry in entries) {
      final key = entry.key;
      // Damp first so accumulated drift decays before new force is applied,
      // then add this frame's force, then cap — so even a large single-frame
      // impulse cannot bypass the tether limit.
      var disp = (_displacements[key] ?? Vector2.zero()) * repulsionDamping;
      disp += forces[key] ?? Vector2.zero();
      if (disp.length > maxTetherDistance) {
        disp = disp.normalized() * maxTetherDistance;
      }
      _displacements[key] = disp;
      entry.value.position += disp;
    }
  }

  /// Current displacement for [key], or zero. Exposed so a test can assert the
  /// tether cap and the damping decay without reading back positions that the
  /// caller has since re-anchored.
  Vector2 displacementOf(String key) =>
      _displacements[key] ?? Vector2.zero();

  /// Forget all accumulated displacement. Call on room teardown.
  void clear() => _displacements.clear();
}
