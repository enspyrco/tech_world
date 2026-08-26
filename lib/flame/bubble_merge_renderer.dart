import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:logging/logging.dart';

import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/flame/components/bubble_field_component.dart';
import 'package:tech_world/flame/components/merged_video_bubble_component.dart';
import 'package:tech_world/flame/components/video_bubble_component.dart';

final _log = Logger('BubbleMergeRenderer');

/// The shared visual layer that sits *between* proximity bubbles: the metaball
/// glow field that gloms overlapping bubbles into one blob, and the merged
/// video surface that samples several video bubbles through a single shader.
///
/// Owns both shared components, both of their shader programs, and the
/// connected-component search that decides which bubbles belong to the merge.
/// It reads the bubble map but never adds or removes an entry — bubble
/// lifecycle stays with `BubbleManager`. The one thing it does write on a
/// bubble is [VideoBubbleComponent.hiddenForMerge], which is that bubble's own
/// render state: while the merged surface is drawing a bubble, the bubble must
/// not also draw itself.
class BubbleMergeRenderer {
  BubbleMergeRenderer({
    required Map<String, PositionComponent> bubbles,
    required void Function(Component) addComponent,
    required bool Function() reduceMotion,
  })  : _bubbles = bubbles,
        _addComponent = addComponent,
        _reduceMotion = reduceMotion;

  final Map<String, PositionComponent> _bubbles;
  final void Function(Component) _addComponent;
  final bool Function() _reduceMotion;

  /// Centre-to-centre distance below which two video bubbles merge.
  /// 1.5x bubble diameter.
  static const double mergeThreshold = 96.0;

  static const Color _glowColor = Color(0xFF00FF88);
  static const double _bubbleRadius = 32;

  ui.FragmentProgram? _metaballShaderProgram;
  ui.FragmentProgram? _mergedVideoShaderProgram;

  BubbleFieldComponent? _bubbleField;
  MergedVideoBubbleComponent? _mergedBubble;

  /// Cached result of [findMergeGroup], recomputed only when [invalidate] has
  /// been called since the last pass. Bubble positions move every frame, so in
  /// practice this is recomputed every frame — the flag exists so that a frame
  /// which does no position work does no search either.
  bool _dirty = true;
  List<String> _cachedMergeGroup = [];

  /// The merge group as of the last event emitted, NOT as of the last frame.
  /// The merge pass runs every frame; comparing against this is what keeps
  /// emission on transitions instead of at frame rate.
  List<String> _lastEmittedGroup = const [];

  @visibleForTesting
  BubbleFieldComponent? get bubbleField => _bubbleField;

  @visibleForTesting
  MergedVideoBubbleComponent? get mergedBubble => _mergedBubble;

  /// Mark the cached merge group stale. Called whenever bubble membership or
  /// position changes.
  void invalidate() => _dirty = true;

  Future<void> loadShaders() => Future.wait([
        _load('shaders/metaball_field.frag',
            (p) => _metaballShaderProgram = p),
        _load('shaders/merged_video_bubble.frag',
            (p) => _mergedVideoShaderProgram = p),
      ]);

  Future<void> _load(
      String asset, void Function(ui.FragmentProgram) assign) async {
    try {
      assign(await ui.FragmentProgram.fromAsset(asset));
    } catch (e) {
      // A missing shader degrades to "no merge effect", never to a crash —
      // the bubbles themselves still render.
      _log.warning('Shader failed to load: $asset', e);
    }
  }

  /// Refresh both shared surfaces for this frame.
  ///
  /// [centres] and [lowestPriority] are computed once by the caller from the
  /// same bubble pass that positions them, rather than re-walked here.
  void update(List<Vector2> centres, int lowestPriority) {
    _updateBubbleField(centres, lowestPriority);
    _updateMergedVideo(lowestPriority);
  }

  void _updateBubbleField(List<Vector2> centres, int lowestPriority) {
    if (centres.length < 2 || _metaballShaderProgram == null) {
      _bubbleField?.removeFromParent();
      _bubbleField = null;
      return;
    }

    if (_bubbleField == null) {
      _bubbleField = BubbleFieldComponent(
        shaderProgram: _metaballShaderProgram!,
        glowColor: _glowColor,
        bubbleRadius: _bubbleRadius,
        reduceMotion: _reduceMotion(),
      );
      _addComponent(_bubbleField!);
    }

    // Live-propagate so toggling reduce-motion does not require dropping the
    // field component (which would happen only when the merge group shrinks).
    _bubbleField!.reduceMotion = _reduceMotion();
    _bubbleField!.priority = lowestPriority - 1;
    _bubbleField!.updateBubblePositions(centres);
  }

  void _updateMergedVideo(int lowestPriority) {
    if (_mergedVideoShaderProgram == null) return;

    final videoBubbles = <String, VideoBubbleComponent>{};
    for (final entry in _bubbles.entries) {
      final bubble = entry.value;
      if (bubble is VideoBubbleComponent) videoBubbles[entry.key] = bubble;
    }

    if (_dirty) {
      _cachedMergeGroup = findMergeGroup(
          {for (final e in videoBubbles.entries) e.key: e.value.center});
      _dirty = false;
    }
    final mergeGroup = _cachedMergeGroup;

    if (mergeGroup.length < 2) {
      // Below the merge threshold every bubble draws itself again. This must
      // run even when there is no merged component to tear down, or a bubble
      // that was hidden for a merge stays invisible after the group breaks up.
      for (final bubble in videoBubbles.values) {
        bubble.hiddenForMerge = false;
      }
      _mergedBubble?.removeFromParent();
      _mergedBubble = null;
      _emitTransition(const []);
      return;
    }

    if (_mergedBubble == null) {
      _mergedBubble = MergedVideoBubbleComponent(
        shaderProgram: _mergedVideoShaderProgram!,
        glowColor: _glowColor,
        bubbleRadius: _bubbleRadius,
        reduceMotion: _reduceMotion(),
      );
      _addComponent(_mergedBubble!);
    }
    // Live-propagate so a toggle takes effect without re-creating the merge.
    _mergedBubble!.reduceMotion = _reduceMotion();

    final sources = <VideoBubbleComponent>[];
    final positions = <Vector2>[];
    for (final key in mergeGroup) {
      final bubble = videoBubbles[key]!;
      bubble.hiddenForMerge = true;
      sources.add(bubble);
      positions.add(bubble.center);
    }

    _mergedBubble!.priority = lowestPriority;
    _mergedBubble!.updateSources(sources);
    _mergedBubble!.updatePositions(positions);

    for (final entry in videoBubbles.entries) {
      if (!mergeGroup.contains(entry.key)) {
        entry.value.hiddenForMerge = false;
      }
    }

    // Emitted here, at the bottom of the build, rather than off the geometry
    // above: reaching this line means the merged surface exists and has its
    // sources. A shader that failed to load returns early at the top of this
    // method, so it can never produce a merge event it did not draw.
    _emitTransition(mergeGroup);
  }

  void _emitTransition(List<String> group) {
    final events = mergeTransitions(_lastEmittedGroup, group);
    if (events.isEmpty) return;
    _lastEmittedGroup = List.unmodifiable(group);
    dispatch(events);
  }

  /// The events owed for a change from [previous] to [current] merge group.
  ///
  /// Pure and static so the emission RULE is exhaustively testable without a
  /// shader, a canvas, or a running game loop. The call site — which decides
  /// WHEN to consult it — is proven separately by a live two-client session.
  ///
  /// Membership is compared as a SET: the merge search may return the same
  /// bubbles in a different order between frames, and re-emitting for that
  /// would be frame-rate noise wearing a transition's clothes.
  static List<AppEvent> mergeTransitions(
    List<String> previous,
    List<String> current,
  ) {
    final before = previous.toSet();
    final after = current.toSet();
    if (before.length == after.length && before.containsAll(after)) {
      return const [];
    }
    if (after.isEmpty) {
      return [BubblesUnmerged(participantIds: List.unmodifiable(previous))];
    }
    return [BubblesMerged(participantIds: List.unmodifiable(current))];
  }

  /// The largest cluster of bubble centres within [mergeThreshold] of each
  /// other, capped at [maxMergedBubbles] (the shader samples a fixed number of
  /// sources).
  ///
  /// Takes centres rather than components because the search is pure geometry
  /// — nothing about it is specific to video. That also makes it testable
  /// without constructing a `VideoBubbleComponent`, which drags in the
  /// platform capture stack.
  ///
  /// Breadth-first over the proximity graph, taking the largest connected
  /// component rather than the first found — with two separate pairs on screen
  /// the bigger huddle is the one worth merging. Returns empty below two, so
  /// callers can treat "no merge" and "group of one" identically.
  @visibleForTesting
  static List<String> findMergeGroup(Map<String, Vector2> centres) {
    if (centres.length < 2) return [];

    final keys = centres.keys.toList();
    final visited = <String>{};
    List<String> largestGroup = [];

    for (final startKey in keys) {
      if (visited.contains(startKey)) continue;

      final group = <String>[startKey];
      final queue = Queue<String>()..add(startKey);
      visited.add(startKey);

      while (queue.isNotEmpty) {
        final currentCentre = centres[queue.removeFirst()]!;

        for (final candidateKey in keys) {
          if (visited.contains(candidateKey)) continue;
          if (currentCentre.distanceTo(centres[candidateKey]!) <
              mergeThreshold) {
            visited.add(candidateKey);
            group.add(candidateKey);
            queue.add(candidateKey);
          }
        }
      }

      if (group.length > largestGroup.length) largestGroup = group;
    }

    return largestGroup.length >= 2
        ? largestGroup.take(maxMergedBubbles).toList()
        : [];
  }

  /// Drop both shared surfaces, keeping the loaded shaders.
  ///
  /// Mirrors `BubbleManager.clear()`: a room teardown removes the components
  /// but the programs stay compiled for the next room, which is the whole
  /// reason shader loading is not per-room work.
  void clearSurfaces() {
    _bubbleField?.removeFromParent();
    _bubbleField = null;
    _mergedBubble?.removeFromParent();
    _mergedBubble = null;
    _cachedMergeGroup = [];
    _dirty = true;
  }

  /// Final teardown: surfaces *and* shader programs.
  void dispose() {
    clearSurfaces();
    _metaballShaderProgram = null;
    _mergedVideoShaderProgram = null;
  }
}
