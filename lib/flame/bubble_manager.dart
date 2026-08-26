import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart' show Color, Colors;
import 'package:livekit_client/livekit_client.dart';
import 'package:logging/logging.dart';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, visibleForTesting;

import 'package:tech_world/bots/bot_config.dart';
import 'package:tech_world/device/web_safe_mode.dart';
import 'package:tech_world/flame/components/bot_bubble_component.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/flame/components/bot_character_component.dart';
import 'package:tech_world/flame/av_snapshot_reporter.dart';
import 'package:tech_world/flame/bubble_merge_renderer.dart';
import 'package:tech_world/flame/bubble_physics.dart';
import 'package:tech_world/flame/dreamfinder_avatar_host.dart';
import 'package:tech_world/flame/proximity_audio_gate.dart';
import 'package:tech_world/flame/components/dreamfinder_component.dart';
import 'package:tech_world/flame/components/player_bubble_component.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/components/video_bubble_component.dart';
import 'package:tech_world/diagnostics/diagnostics_service.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/utils/locator.dart';

final _log = Logger('BubbleManager');

/// Manages the lifecycle of all player proximity bubbles in the game world.
///
/// Plain Dart class (not a Flame Component). Receives a callback to add
/// components to the World, keeping component tree ownership in TechWorld.
///
/// Responsibilities:
///  - Proximity detection and bubble creation/removal
///  - Physics repulsion between overlapping bubbles
///  - Metaball field and merged video rendering
///  - Audio enable/disable based on distance
///  - Shader loading and assignment
///  - Dreamfinder avatar bridge lifecycle
class BubbleManager {
  BubbleManager({
    required PlayerComponent localPlayer,
    required void Function(Component) addComponent,
    required Map<String, PlayerComponent> remotePlayers,
    required Map<String, BotCharacterComponent> bots,
    this.hideVideoBubbles = false,
    this.reduceMotion = false,
    this.proximityRadius = defaultProximityRadius,
    DiagnosticsService? diagnostics,
  })  : _localPlayer = localPlayer,
        _addComponent = addComponent,
        _remotePlayers = remotePlayers,
        _bots = bots {
    _audioGate = ProximityAudioGate(
      proximityRadius: () => proximityRadius,
      liveKitService: () => _liveKitService,
      diagnosticsEnabled: () => avDiagnosticsEnabled,
      dreamfinderIdentity: () => dreamfinderIdentity,
    );
    _dfAvatar = DreamfinderAvatarHost(
      liveKitService: () => _liveKitService,
      onReady: () => refreshBubbleForPlayer(dreamfinderIdentity),
      // Share the single computed value rather than probing the platform
      // twice; it cannot change mid-session.
      isMobileWebOverride: _isMobileWeb,
    );
    _avReporter = AvSnapshotReporter(
      diagnostics: diagnostics ?? Locator.maybeLocate<DiagnosticsService>(),
      localPlayer: localPlayer,
      remotePlayers: remotePlayers,
      bots: bots,
      bubbles: _playerBubbles,
      audioEnabled: _audioGate.isEnabled,
      dreamfinder: () => dreamfinderComponent,
      dreamfinderIdentity: () => dreamfinderIdentity,
      liveKitService: () => _liveKitService,
      localBubbleKey: _localPlayerBubbleKey,
    );
    _mergeRenderer = BubbleMergeRenderer(
      bubbles: _playerBubbles,
      addComponent: addComponent,
      reduceMotion: () => reduceMotion,
    );
  }

  /// When true, all proximity bubbles render as [PlayerBubbleComponent]
  /// (avatar-only) regardless of whether the underlying participant has a
  /// video track. Audio and player avatars are unaffected.
  ///
  /// Mutable so the owning game world can apply the user's saved preference
  /// before each room entry. Existing bubbles are not retroactively swapped —
  /// the toggle takes effect for newly created bubbles only.
  bool hideVideoBubbles;

  /// Whether this client is a mobile browser, where the embodied Dreamfinder's
  /// WebGL-iframe capture renders black (see [isMobileWeb]). Computed once — the
  /// browser can't change mid-session. When true, DF stays a 2D sprite: the
  /// embodied video bubble is never created and its iframe bridge never loads.
  final bool _isMobileWeb = isMobileWeb();

  /// When true, purely decorative animation on proximity video bubbles
  /// renders in its resting state: no breathing scale, no glow pulse, no
  /// voice ripples, and the metaball merge field/animation freezes.
  ///
  /// Gameplay-essential animation (avatar walk, bubble physics repulsion,
  /// camera, tile rendering) is unaffected. Universal benefit (vestibular
  /// disorders, low-power devices, ADHD, autism, motion sensitivity).
  ///
  /// Mutable so the owning game world can apply the user's saved preference
  /// before each room entry. Applied to newly-created bubbles and to the
  /// shared metaball field/merged-video components on next update.
  bool reduceMotion;

  /// Chebyshev radius, in grid squares, inside which another participant is
  /// "nearby": their bubble forms, their audio subscribes, and Dreamfinder is
  /// told the local player is in range. `0` disables proximity entirely — no
  /// bubble forms for anyone, including a participant standing on the local
  /// player's own square.
  ///
  /// This is the user's "Proximity range" preference
  /// ([UserPreferences.proximityRadius]) and the single source of all three
  /// proximity gates: the visual threshold is this value, and the audio
  /// enable/disable pair derives from it (see [ProximityAudioGate.enableThreshold]).
  ///
  /// Mutable so the owning game world can apply the saved preference before
  /// each room entry — the same seam as [hideVideoBubbles] and [reduceMotion].
  /// Frozen for the session: a mid-session change never retroactively
  /// re-evaluates pairs already in range.
  int proximityRadius;

  /// Radius applied when the caller supplies none. Matches
  /// [UserPreferences.defaultProximityRadius]; a runtime test pins the two
  /// together so the constructor default can't drift from the preference's.
  static const int defaultProximityRadius = 5;

  // ── Construction-time stable references ──────────────────────────────────

  final PlayerComponent _localPlayer;
  final void Function(Component) _addComponent;
  final Map<String, PlayerComponent> _remotePlayers;
  final Map<String, BotCharacterComponent> _bots;

  // ── Bot status (arrives after construction, when ChatService is created) ──

  ValueListenable<BotStatus> _botStatus = ValueNotifier(BotStatus.absent);

  // ── LiveKit (arrives after construction) ─────────────────────────────────

  LiveKitService? _liveKitService;
  /// Lifecycle owner of the 3D avatar iframe. See [DreamfinderAvatarHost];
  /// every read through it is null-safe on platforms with no bridge.
  late final DreamfinderAvatarHost _dfAvatar;

  // ── Mutable references set by TechWorld ──────────────────────────────────

  DreamfinderComponent? dreamfinderComponent;
  String dreamfinderIdentity = dreamfinderBot.identity;

  // ── Bubble state ─────────────────────────────────────────────────────────

  final Map<String, PositionComponent> _playerBubbles = {};
  /// Soft-body repulsion + tether. See [BubblePhysics]; it owns the
  /// accumulated per-bubble displacement across frames.
  final BubblePhysics _physics = BubblePhysics();
  /// Distance-driven audio subscription + volume ramp. Owns the enable/disable
  /// hysteresis pair and the per-participant volume cache — see
  /// [ProximityAudioGate].
  late final ProximityAudioGate _audioGate;
  /// Last reported local-player proximity to Dreamfinder, so the df-proximity
  /// signal is published only on enter/exit transitions, not every frame.
  bool _wasNearDreamfinder = false;
  /// Participants inside [proximityRadius] as of the previous frame, so
  /// enter/exit events fire on transitions only. Excludes the local player's
  /// own bubble slot. See [_reconcileProximityMembership].
  final Set<String> _nearbyParticipants = {};

  // ── Shared merge/glow layer ──────────────────────────────────────────────

  /// The metaball field and merged-video surface that sit between bubbles,
  /// plus their shaders and the merge-group search. See [BubbleMergeRenderer].
  late final BubbleMergeRenderer _mergeRenderer;

  // ── Shader programs ───────────────────────────────────────────────────────

  /// Per-bubble video shader. Stays here because it is an input to bubble
  /// *creation*, not to the shared merge layer.
  ui.FragmentProgram? _shaderProgram;

  // ── AV diagnostics ─────────────────────────────────────────────────────────

  /// Periodic AV pipeline observer. Owns the diagnostics toggle, the snapshot
  /// timer, and snapshot construction — see [AvSnapshotReporter]. Read-only
  /// with respect to the bubble maps it is handed.
  late final AvSnapshotReporter _avReporter;

  /// Whether AV pipeline diagnostic events should be generated.
  ///
  /// Delegates to the reporter, which reads `DiagnosticsService.avEnabled`
  /// directly — there is no shadow field anywhere in the chain to drift out
  /// of sync. Kept on `BubbleManager` because the bubble-lifecycle events in
  /// [_replaceBubble] and `LiveKitGameBridge` gate on it.
  bool get avDiagnosticsEnabled => _avReporter.enabled;

  // ── Constants ─────────────────────────────────────────────────────────────

  static const _localPlayerBubbleKey = '_local_player_';
  // Audio gate with hysteresis so standing at the boundary doesn't flap the
  // SFU forward on/off. Audio enables when a participant is within
  // [ProximityAudioGate.enableThreshold] and only cuts once they drift past
  // [ProximityAudioGate.disableThreshold]. The enable distance sits one square inside the
  // visual range so you can hear almost anyone whose bubble you can see —
  // closing the old see-but-can't-hear dead zone (audio was ≤2 while bubbles
  // were ≤5). Both derive from [proximityRadius], so the user's preference
  // moves the whole gate stack together and the one-square hysteresis band is
  // preserved at every setting.
  //
  // At radius 0 the enable threshold is -1, which no distance satisfies —
  // proximity-disabled means silent, with no special case needed.
  static final _bubbleOffset =
      Vector2(16, -20); // center horizontally, above sprite

  // ═══════════════════════════════════════════════════════════════════════════
  // Public API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Whether [distance] grid squares counts as nearby at the current
  /// [proximityRadius].
  ///
  /// The `> 0` term is the whole reason this is a method and not an inline
  /// `distance <= proximityRadius`: radius 0 means proximity is off, and a
  /// bare comparison would still match a participant standing on the local
  /// player's own square. One owner, so the three call sites (remote players,
  /// Dreamfinder, bots) cannot drift apart on it.
  bool _isWithinRadius(int distance) =>
      proximityRadius > 0 && distance <= proximityRadius;

  /// Chebyshev distance (max of x/y difference) — the metric for proximity.
  static int chebyshevDistance(Point<int> a, Point<int> b) =>
      max((a.x - b.x).abs(), (a.y - b.y).abs());

  /// Load all three shader programs in parallel.
  Future<void> loadShaders() => Future.wait([
        _loadVideoBubbleShader(),
        _mergeRenderer.loadShaders(),
      ]);

  /// Called when LiveKitService becomes available (after connectToLiveKit).
  void setLiveKitService(LiveKitService service) {
    _liveKitService = service;
  }

  /// Called when ChatService becomes available (after room join).
  void setBotStatus(ValueListenable<BotStatus> status) {
    _botStatus = status;
  }

  /// Main per-frame entry point. Called from TechWorld.update().
  void update(double dt) {
    _avReporter.update(dt);

    final playerGrid = _localPlayer.miniGridPosition;

    // Recompute proximity every frame. A previous optimisation skipped this
    // whenever the LOCAL player hadn't changed grid cell — but remote players
    // and Dreamfinder (which wanders autonomously) move too, and that changes
    // distances. Skipping on local-stillness left the audio gate stale: a peer
    // could walk back into range and stay inaudible until the local player
    // happened to move (the "can't hear you until I move" bug). At meetup-scale
    // participant counts the per-frame recompute is cheap — a handful of
    // Chebyshev distances; bubble creation/removal is still transition-guarded,
    // and the audio enable/disable is a no-op when the gate state is unchanged.

    // Check each other player for proximity.
    final nearbyPlayerIds = <String>{};
    int closestDistance = proximityRadius + 1;

    for (final entry in _remotePlayers.entries) {
      final playerId = entry.key;
      final playerComponent = entry.value;

      final distance =
          chebyshevDistance(playerGrid, playerComponent.miniGridPosition);
      final isVisible = _isWithinRadius(distance);

      if (isVisible) {
        nearbyPlayerIds.add(playerId);
        if (distance < closestDistance) closestDistance = distance;

        if (!_playerBubbles.containsKey(playerId)) {
          final bubble = _createBubbleForPlayer(playerId, playerComponent);
          bubble.position = playerComponent.position + _bubbleOffset;
          _replaceBubble(playerId, bubble, 'remote-player-entered-proximity');
        }

        _setBubbleOpacity(_playerBubbles[playerId]!, distance);
        _audioGate.update(playerId, distance);
      } else {
        // Beyond visual range — ensure audio is disabled.
        _audioGate.update(playerId, distance);
      }
    }

    // Check proximity to Dreamfinder.
    if (dreamfinderComponent != null) {
      final dfGrid = dreamfinderComponent!.miniGridPosition;
      final dfDistance = chebyshevDistance(playerGrid, dfGrid);

      if (_isWithinRadius(dfDistance)) {
        nearbyPlayerIds.add(dreamfinderIdentity);
        if (dfDistance < closestDistance) closestDistance = dfDistance;

        if (!_playerBubbles.containsKey(dreamfinderIdentity)) {
          final dfParticipant =
              _liveKitService?.getParticipant(dreamfinderIdentity);
          PositionComponent bubble;
          if (dfParticipant != null && !hideVideoBubbles && !_isMobileWeb) {
            bubble = _createDreamfinderVideoBubble(dfParticipant);
          } else {
            // Mobile web (or hidden video) → the 2D sprite + a status bubble,
            // not the black embodied WebGL bubble.
            bubble = BotBubbleComponent(botStatus: _botStatus);
          }
          bubble.position =
              dreamfinderComponent!.position + _bubbleOffset;
          _replaceBubble(
              dreamfinderIdentity, bubble, 'dreamfinder-entered-proximity');
        }
      }

      // Proximity-gate DF audio symmetric with its video bubble — you hear
      // Dreamfinder only when close enough for the bubble to work. Runs every
      // frame (near OR far) so the gate is the single per-frame owner of DF
      // audio state. See [_updateDreamfinderAudio].
      _audioGate.updateDreamfinder(dfDistance);
    }

    // Check proximity to all bot characters.
    for (final entry in _bots.entries) {
      final botId = entry.key;
      final botComp = entry.value;
      final botDistance =
          chebyshevDistance(playerGrid, botComp.miniGridPosition);

      if (_isWithinRadius(botDistance)) {
        nearbyPlayerIds.add(botId);
        if (botDistance < closestDistance) closestDistance = botDistance;

        if (!_playerBubbles.containsKey(botId)) {
          final bubble = BotBubbleComponent(botStatus: _botStatus);
          bubble.position = botComp.position + _bubbleOffset;
          _replaceBubble(botId, bubble, 'bot-entered-proximity');
        }
      }
    }

    // Emit enter/exit before the local-player sentinel joins the set below —
    // `_localPlayerBubbleKey` is a bubble slot, not a participant.
    _reconcileProximityMembership(nearbyPlayerIds);

    // Show local player's bubble if near anyone.
    if (nearbyPlayerIds.isNotEmpty) {
      if (!_playerBubbles.containsKey(_localPlayerBubbleKey)) {
        final localBubble = _createLocalPlayerBubble();
        localBubble.position = _localPlayer.position + _bubbleOffset;
        _replaceBubble(
            _localPlayerBubbleKey, localBubble, 'local-player-bubble-shown');
      }
      _setBubbleOpacity(
          _playerBubbles[_localPlayerBubbleKey]!, closestDistance);
      nearbyPlayerIds.add(_localPlayerBubbleKey);
    }

    // Notify Dreamfinder when the local player enters/exits its range so the
    // bot can gate whose speech it hears. null distance == DF not present.
    _updateDreamfinderProximity(
      dreamfinderComponent == null
          ? null
          : chebyshevDistance(playerGrid, dreamfinderComponent!.miniGridPosition),
    );

    // Remove bubbles for players no longer nearby.
    final toRemove = <String>[];
    for (final playerId in _playerBubbles.keys) {
      if (!nearbyPlayerIds.contains(playerId)) {
        toRemove.add(playerId);
      }
    }
    for (final playerId in toRemove) {
      _replaceBubble(playerId, null, 'participant-left-proximity');
    }

    _updateBubblePositions(dt);
  }

  /// Emit [PlayerEnteredProximity] / [PlayerLeftProximity] for the frame's
  /// proximity set.
  ///
  /// Keyed off set membership rather than bubble creation on purpose: a bubble
  /// is replaced for reasons that have nothing to do with proximity (upgrading
  /// to video, camera on/off, a Dreamfinder respawn), and hanging the events
  /// off `_replaceBubble` would report a peer as re-entering every time their
  /// camera came on. Participants who vanish from the world maps entirely
  /// (disconnects) fall out of [nearby] and so emit an exit here too.
  void _reconcileProximityMembership(Set<String> nearby) {
    for (final id in nearby.difference(_nearbyParticipants)) {
      dispatch([PlayerEnteredProximity(playerId: id)]);
    }
    for (final id in _nearbyParticipants.difference(nearby)) {
      dispatch([PlayerLeftProximity(playerId: id)]);
    }
    _nearbyParticipants
      ..clear()
      ..addAll(nearby);
  }

  /// Refresh (upgrade to video or re-create) the bubble for a remote player.
  void refreshBubbleForPlayer(String playerId) {
    // Handle Dreamfinder separately.
    if (isDreamfinderIdentity(playerId) && dreamfinderComponent != null) {
      final existingBubble = _playerBubbles[playerId];
      final dfParticipant =
          _liveKitService?.getParticipant(dreamfinderIdentity);
      if (dfParticipant == null) return;

      // When video bubbles are hidden, or on mobile web (where the embodied
      // WebGL bubble renders black), never upgrade the DF bubble to a video
      // bubble — the existing BotBubbleComponent stays in place.
      if (hideVideoBubbles || _isMobileWeb) return;

      final hasCanvasCapture = existingBubble is VideoBubbleComponent &&
          existingBubble.externalVideoCapture != null;
      final needsUpgrade = existingBubble is! VideoBubbleComponent ||
          (!hasCanvasCapture && _dfAvatar.isReady);

      if (needsUpgrade) {
        final videoBubble = _createDreamfinderVideoBubble(dfParticipant);
        videoBubble.position =
            dreamfinderComponent!.position + _bubbleOffset;
        _replaceBubble(
            playerId, videoBubble, 'dreamfinder-bubble-upgraded-to-video');
      }
      return;
    }

    final existingBubble = _playerBubbles[playerId];
    if (existingBubble == null) return;

    if (existingBubble is VideoBubbleComponent) return;

    final playerComponent = _remotePlayers[playerId];
    if (playerComponent == null) return;

    final newBubble = _createBubbleForPlayer(playerId, playerComponent);
    newBubble.position = playerComponent.position + _bubbleOffset;
    _replaceBubble(playerId, newBubble, 'player-bubble-refreshed');
  }

  /// Refresh the local player's bubble (e.g. after camera comes online).
  void refreshLocalPlayerBubble() {
    final existingBubble = _playerBubbles[_localPlayerBubbleKey];
    if (existingBubble == null) return;

    if (existingBubble is VideoBubbleComponent) return;

    _log.fine('Refreshing local player bubble after camera enabled');

    final newBubble = _createLocalPlayerBubble();
    newBubble.position = _localPlayer.position + _bubbleOffset;
    _replaceBubble(_localPlayerBubbleKey, newBubble,
        'local-player-bubble-refreshed');
  }

  /// Downgrade the LOCAL player's video bubble to a static avatar — e.g. when
  /// the local camera is turned off.
  ///
  /// Without this, the local video bubble keeps its last decoded frame (a
  /// freeze) and, because it stays a [VideoBubbleComponent],
  /// [refreshLocalPlayerBubble]'s guard makes turning the camera back on a
  /// no-op. Mirrors [downgradeVideoBubble] for remote players. The camera is
  /// already off by the time this fires, so [_createLocalPlayerBubble] builds a
  /// static [PlayerBubbleComponent].
  void downgradeLocalPlayerBubble() {
    final existing = _playerBubbles[_localPlayerBubbleKey];
    if (existing is! VideoBubbleComponent) return;

    _log.fine('Downgrading local player bubble after camera disabled');
    final position = existing.position.clone();
    final newBubble = _createLocalPlayerBubble();
    newBubble.position = position;
    _replaceBubble(_localPlayerBubbleKey, newBubble,
        'local-video-downgraded-to-static');
  }

  /// Downgrade a video bubble to a static placeholder.
  void downgradeVideoBubble(String playerId) {
    final existingBubble = _playerBubbles[playerId];
    if (existingBubble == null) return;

    if (existingBubble is! VideoBubbleComponent) return;

    final position = existingBubble.position.clone();

    if (isDreamfinderIdentity(playerId)) {
      final botBubble = BotBubbleComponent(
        botStatus: _botStatus,
        bubbleSize: 64,
      );
      botBubble.position = position;
      _replaceBubble(
          playerId, botBubble, 'dreamfinder-video-downgraded-to-bot');
    } else {
      final playerComponent = _remotePlayers[playerId];
      if (playerComponent != null) {
        final newBubble = PlayerBubbleComponent(
          displayName: playerComponent.displayName,
          playerId: playerId,
        );
        newBubble.position = position;
        _replaceBubble(
            playerId, newBubble, 'player-video-downgraded-to-static');
      } else {
        _replaceBubble(playerId, null,
            'player-video-downgraded-no-player-component');
      }
    }
  }

  /// Update the speaking indicator on a video bubble.
  void updateSpeakingState(String participantId, bool isSpeaking) {
    final bubble = _playerBubbles[participantId];
    if (bubble is VideoBubbleComponent) {
      bubble.speakingLevel = isSpeaking ? 1.0 : 0.0;
    }
  }

  /// Signal that a video track is ready for frame capture.
  void notifyTrackReady(String participantId) {
    final bubble = _playerBubbles[participantId];
    if (bubble is VideoBubbleComponent) {
      _log.fine('Notifying bubble track ready for $participantId');
      bubble.notifyTrackReady();
    }
  }

  /// Initialize the Dreamfinder 3D avatar bridge (web only).
  void initDreamfinderBridge() => _dfAvatar.start();

  /// Clean up Dreamfinder-specific state when the participant leaves.
  void handleDreamfinderLeft() {
    dreamfinderIdentity = dreamfinderBot.identity;
    _dfAvatar.stop();
  }

  /// Remove a single bubble by player ID.
  void removeBubble(String playerId) {
    // A peer that vanishes (ungraceful disconnect) while inside audio range
    // never crosses the disable threshold in the proximity loop, so drop their
    // audio bookkeeping here to avoid leaking map entries until teardown.
    _audioGate.forget(playerId);
    _replaceBubble(playerId, null, 'remove-bubble-api');
  }

  /// Remove all bubbles and reset state. Safe to call multiple times.
  void clear() {
    // Drain via _replaceBubble so each removal dispatches a lifecycle
    // event under avDiagnosticsEnabled — otherwise a teardown would
    // silently strand "still-present" entries in the diagnostic stream.
    // Snapshot keys first since _replaceBubble mutates the map.
    final ids = List<String>.from(_playerBubbles.keys);
    for (final id in ids) {
      _replaceBubble(id, null, 'bubble-manager-cleared');
    }
    _physics.clear();
    _mergeRenderer.clearSurfaces();
    _audioGate.clear();
    // Everyone who was in range has now left, as far as any consumer of the
    // event stream is concerned. Same reasoning as the DF exit below: a
    // teardown that drops membership silently leaves the last enter unmatched.
    _reconcileProximityMembership(const {});
    // Emit a final exit so Dreamfinder doesn't hold a stale near:true after we
    // tear down while the player was in range (cage match PR #481 — Carnot).
    // Best-effort; the bot also self-heals on our ParticipantDisconnected.
    if (_wasNearDreamfinder) {
      _liveKitService?.publishDfProximity(near: false);
    }
    _wasNearDreamfinder = false;
    _liveKitService = null;
    _dfAvatar.stop();
    dreamfinderIdentity = dreamfinderBot.identity;
  }

  /// Final teardown. Call from TechWorld.dispose().
  void dispose() {
    clear();
    _shaderProgram = null;
    _mergeRenderer.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Private — shader loading
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadVideoBubbleShader() async {
    try {
      _shaderProgram =
          await ui.FragmentProgram.fromAsset('shaders/video_bubble.frag');
    } catch (e) {
      _log.warning('Video bubble shader failed to load', e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Private — bubble creation
  // ═══════════════════════════════════════════════════════════════════════════

  PositionComponent _createBubbleForPlayer(
      String playerId, PlayerComponent playerComponent) {
    final participant = _liveKitService?.getParticipant(playerId);
    if (!hideVideoBubbles &&
        participant != null &&
        AvSnapshotReporter.hasVideoTrack(participant)) {
      final videoBubble = VideoBubbleComponent(
        participant: participant,
        displayName: playerComponent.displayName,
        bubbleSize: 64,
        targetFps: 15,
        reduceMotion: reduceMotion,
      );

      if (_shaderProgram != null) {
        videoBubble.setShader(_shaderProgram!.fragmentShader());
      }

      return videoBubble;
    }

    return PlayerBubbleComponent(
      displayName: playerComponent.displayName,
      playerId: playerId,
    );
  }

  PositionComponent _createLocalPlayerBubble() {
    final localParticipant = _liveKitService?.localParticipant;

    if (!hideVideoBubbles &&
        localParticipant != null &&
        AvSnapshotReporter.hasVideoTrack(localParticipant)) {
      _log.fine('Creating local VideoBubbleComponent');
      final videoBubble = VideoBubbleComponent(
        participant: localParticipant,
        displayName: _localPlayer.displayName,
        bubbleSize: 64,
        targetFps: 15,
        reduceMotion: reduceMotion,
      );

      if (_shaderProgram != null) {
        videoBubble.setShader(_shaderProgram!.fragmentShader());
      }

      videoBubble.glowColor = Colors.cyan;

      return videoBubble;
    }

    return PlayerBubbleComponent(
      displayName: _localPlayer.displayName,
      playerId: _localPlayer.id,
    );
  }

  VideoBubbleComponent _createDreamfinderVideoBubble(
      Participant participant) {
    final videoBubble = VideoBubbleComponent(
      participant: participant,
      displayName: dreamfinderBot.displayName,
      bubbleSize: 64,
      targetFps: 10,
      externalVideoCapture: _dfAvatar.canvasCapture,
      reduceMotion: reduceMotion,
    );
    videoBubble.glowColor = const Color(0xFFDAA520); // gold
    videoBubble.glowIntensity = 0.7;
    return videoBubble;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Private — proximity and audio
  // ═══════════════════════════════════════════════════════════════════════════

  void _setBubbleOpacity(PositionComponent bubble, int distance) {
    final opacity = _opacityForDistance(distance);
    if (bubble is VideoBubbleComponent) {
      bubble.opacity = opacity;
    } else if (bubble is PlayerBubbleComponent) {
      bubble.opacity = opacity;
    }
  }

  /// Visual opacity for a bubble at [distance] Chebyshev grid squares: full
  /// within [ProximityAudioGate.fullVolumeDistance], then a linear fade to nothing at
  /// [proximityRadius].
  ///
  /// Opacity is presentation, not proximity logic — hence living here rather
  /// than in a proximity source. It used to be a ladder hand-tabulated for a
  /// radius of 5 (0.8 / 0.5 / 0.2); scaling it to the user's radius means the
  /// fade spans whatever range they chose instead of going fully transparent
  /// two squares early at radius 6, or never fading at all at radius 2. At the
  /// default radius the curve is within 0.05 of the old ladder at every
  /// square, and it is now the same shape as [ProximityAudioGate.volumeForDistance].
  double _opacityForDistance(int distance) {
    if (proximityRadius <= 0) return 0.0;
    if (distance <= ProximityAudioGate.fullVolumeDistance) return 1.0;
    final span = proximityRadius - ProximityAudioGate.fullVolumeDistance;
    if (span <= 0) return 1.0;
    return ((proximityRadius - distance) / span).clamp(0.0, 1.0);
  }

  /// Emit the `df-proximity` enter/exit signal to Dreamfinder. [dfDistance] is
  /// null when DF isn't present (forces an exit).
  ///
  /// Hardened per the PR #481 cage match (Kelvin + Carnot):
  /// - **Hysteresis** — enter within [ProximityAudioGate.enableThreshold]; once near, stay
  ///   near until past [ProximityAudioGate.disableThreshold]. Stops a peer hovering at the
  ///   boundary from spamming the reliable channel.
  /// - **Null-service safety** — if the service isn't ready we do NOT latch
  ///   [_wasNearDreamfinder]; the transition simply re-fires next frame once it
  ///   is. Latching-without-sending was the "signal lost forever" bug.
  void _updateDreamfinderProximity(int? dfDistance) {
    final near = dfDistance != null &&
        (_wasNearDreamfinder
            ? dfDistance <= _audioGate.disableThreshold
            : dfDistance <= _audioGate.enableThreshold);
    if (near == _wasNearDreamfinder) return;
    final service = _liveKitService;
    if (service == null) return; // can't emit — don't latch; retry next frame
    _wasNearDreamfinder = near;
    service.publishDfProximity(near: near);
  }

  /// Test seam for the DF proximity emission logic — exercising it through the
  /// real update loop would require a fully-constructed [DreamfinderComponent]
  /// (sprite + path harness). Pass the Chebyshev distance to DF, or null for
  /// "DF absent".
  @visibleForTesting
  void debugUpdateDreamfinderProximity(int? dfDistance) =>
      _updateDreamfinderProximity(dfDistance);

  /// Proximity-gate Dreamfinder's audio symmetric with its video bubble: you
  /// hear DF only when within audio range, via the same [_updateParticipantAudio]
  /// gate (enable/disable + hysteresis + volume fade) used for remote players.
  ///
  /// The manual silence button ([LiveKitService.dreamfinderSilenced]) ALWAYS
  /// wins: when silenced we feed the gate a beyond-range distance so DF stays
  /// muted regardless of how close you stand. Because this runs every frame,
  /// the gate is the single per-frame writer of DF audio state and
  /// self-reconciles with the manual path (which also disables the track
  /// directly) within one frame.
  /// Test seam for [_updateDreamfinderAudio] — see
  /// [debugUpdateDreamfinderProximity] for why the real loop can't be driven
  /// without a fully-constructed [DreamfinderComponent].
  @visibleForTesting
  void debugUpdateDreamfinderAudio(int dfDistance) =>
      _audioGate.updateDreamfinder(dfDistance);

  // ═══════════════════════════════════════════════════════════════════════════
  // Private — physics and rendering
  // ═══════════════════════════════════════════════════════════════════════════

  void _updateBubblePositions(double dt) {
    // Bubble positions change every frame (they track their owning character),
    // so the merge group must be rechecked.
    _mergeRenderer.invalidate();

    // 1. Set base positions from owning characters.
    for (final entry in _playerBubbles.entries) {
      if (entry.key == _localPlayerBubbleKey) {
        entry.value.position = _localPlayer.position + _bubbleOffset;
        entry.value.priority = _localPlayer.priority + 1;
      } else if (entry.key == dreamfinderIdentity &&
          dreamfinderComponent != null) {
        entry.value.position =
            dreamfinderComponent!.position + _bubbleOffset;
        entry.value.priority = dreamfinderComponent!.priority + 1;
        if (entry.value is VideoBubbleComponent) {
          (entry.value as VideoBubbleComponent).loadingProgress =
              _dfAvatar.avatarLoadProgress;
        }
      } else if (_bots.containsKey(entry.key)) {
        final botComp = _bots[entry.key]!;
        entry.value.position = botComp.position + _bubbleOffset;
        entry.value.priority = botComp.priority + 1;
      } else {
        final playerComponent = _remotePlayers[entry.key];
        if (playerComponent != null) {
          entry.value.position = playerComponent.position + _bubbleOffset;
          entry.value.priority = playerComponent.priority + 1;
        }
      }
    }

    // 2. Apply physics repulsion so bubbles don't overlap.
    _physics.apply(_playerBubbles, dt);

    // 3. Collect centres for the metaball field.
    final centres = <Vector2>[];
    int lowestPriority = 0x7fffffff;
    for (final entry in _playerBubbles.entries) {
      centres.add(entry.value.center);
      if (entry.value.priority < lowestPriority) {
        lowestPriority = entry.value.priority;
      }
    }

    _mergeRenderer.update(centres, lowestPriority);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Private — AV diagnostics
  // ═══════════════════════════════════════════════════════════════════════════

  /// Single owner of bubble-slot mutation. Removes any prior occupant
  /// (component-tree detach + lifecycle event) and installs [newBubble]
  /// (or leaves the slot empty when [newBubble] is null).
  ///
  /// Every direct write to [_playerBubbles] should route through here —
  /// the helper guarantees three invariants:
  ///   1. removed bubbles always detach from the component tree
  ///   2. created bubbles always attach to the component tree
  ///   3. `AvBubbleCreated`/`AvBubbleRemoved` events fire whenever the
  ///      slot's occupancy changes, gated by [avDiagnosticsEnabled]
  ///
  /// [reason] is a short kebab-case breadcrumb (logged at FINE level)
  /// that names the trigger — useful when replaying logs to understand
  /// which call site moved a bubble.
  ///
  /// An upgrade or downgrade (both old and new non-null) emits
  /// `AvBubbleRemoved` then `AvBubbleCreated` in that order — the
  /// pair documents the full transition without inventing a new event
  /// type. If the bubble type does not actually change, the events still
  /// fire: the diagnostic stream tracks identity-by-instance, not
  /// type-equality.
  ///
  /// Spiral F7 from PR #465 (same chord as the DiagnosticsService
  /// extraction in #466 / #467, but at the lifecycle level rather than
  /// the toggle level).
  void _replaceBubble(
      String id, PositionComponent? newBubble, String reason) {
    final old = _playerBubbles[id];

    if (old != null) {
      old.removeFromParent();
      if (avDiagnosticsEnabled) {
        dispatch([AvBubbleRemoved(participant: id)]);
      }
    }

    if (newBubble != null) {
      _playerBubbles[id] = newBubble;
      _addComponent(newBubble);
      if (avDiagnosticsEnabled) {
        dispatch([AvBubbleCreated(
          participant: id,
          bubbleType: classifyBubble(newBubble),
        )]);
      }
    } else {
      _playerBubbles.remove(id);
    }

    _mergeRenderer.invalidate();

    if (old != null || newBubble != null) {
      _log.fine('bubble[$id] ${old == null ? "+" : (newBubble == null ? "-" : "~")} $reason');
    }
  }

  /// Maps a bubble `PositionComponent` to its [AvBubbleType] for AV
  /// diagnostic events. The three known concrete bubble types map to
  /// their named enum values; anything else flows to
  /// [AvBubbleType.unknown] rather than silently being misreported as
  /// [AvBubbleType.player] (the pre-#466 catch-all).
  ///
  /// Exposed `@visibleForTesting` so the unknown-fallback case can be
  /// pinned with a sentinel `PositionComponent` subclass without
  /// reaching into the private dispatch path.
  @visibleForTesting
  static AvBubbleType classifyBubble(PositionComponent bubble) =>
      AvSnapshotReporter.classifyBubble(bubble);
}
