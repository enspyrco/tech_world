import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:logging/logging.dart';

import 'package:tech_world/device/web_safe_mode.dart';
import 'package:tech_world/native/frame_source.dart';
import 'package:tech_world/livekit/dreamfinder_avatar_bridge.dart';
import 'package:tech_world/livekit/livekit_service.dart';

final _log = Logger('DreamfinderAvatarHost');

/// Owns the lifecycle of the Dreamfinder 3D avatar bridge — the same-origin
/// iframe running Three.js whose canvas is captured as Dreamfinder's video.
///
/// Exists so the bubble layer can ASK about the avatar (is it ready, what is
/// its capture source, how far has it loaded) without also being responsible
/// for creating it, retrying it, and tearing it down. Every read is null-safe,
/// so a caller never has to know whether the bridge exists on this platform.
///
/// Two platforms never get a bridge at all:
///  - native, where the export resolves to a no-op stub;
///  - mobile web, where the embodied WebGL avatar renders black, so Dreamfinder
///    stays a 2D sprite and loading the iframe would be pure cost.
class DreamfinderAvatarHost {
  DreamfinderAvatarHost({
    required LiveKitService? Function() liveKitService,
    required void Function() onReady,
    bool? isMobileWebOverride,
    @visibleForTesting
    DreamfinderAvatarBridge Function(LiveKitService)? bridgeFactory,
  })  : _liveKitService = liveKitService,
        _onReady = onReady,
        _isMobileWeb = isMobileWebOverride ?? isMobileWeb(),
        _bridgeFactory = bridgeFactory ??
            ((liveKit) => DreamfinderAvatarBridge(liveKitService: liveKit));

  final LiveKitService? Function() _liveKitService;

  /// Called once the bridge reports ready, so the caller can swap Dreamfinder's
  /// placeholder bubble for one backed by the live canvas. Not called when the
  /// bridge is skipped or fails — there is nothing new to show in either case.
  final void Function() _onReady;

  final bool _isMobileWeb;

  /// How a bridge gets built. Injectable ONLY so the ready-path can be
  /// exercised: on native the real bridge is a stub that reports isReady false
  /// forever, so without this seam neither [_onReady] firing nor the
  /// stopped-before-ready guard below is reachable from a test at all.
  final DreamfinderAvatarBridge Function(LiveKitService) _bridgeFactory;

  DreamfinderAvatarBridge? _bridge;

  /// Whether a bridge exists AND has finished initializing.
  bool get isReady => _bridge?.isReady == true;

  /// Live capture source for the avatar canvas, or null when there is no
  /// bridge — in which case Dreamfinder renders as a 2D sprite instead.
  FrameSource? get canvasCapture => _bridge?.canvasCapture;

  /// Avatar load percentage, or null when unknown / not applicable.
  int? get avatarLoadProgress => _bridge?.avatarLoadProgress;

  /// Create and initialize the bridge if this platform gets one and there
  /// isn't one already.
  ///
  /// Idempotent: safe to call on every Dreamfinder arrival. The existing-bridge
  /// check is what makes it so — a DF respawn must not spawn a second iframe
  /// alongside the first.
  void start() {
    if (_isMobileWeb) return;
    if (_bridge != null) return;
    final liveKit = _liveKitService();
    if (liveKit == null) return;

    final bridge = _bridgeFactory(liveKit);
    _bridge = bridge;
    bridge.initialize().then((_) {
      // Re-check through the field rather than the local: a `stop()` between
      // the call and this callback nulls the field, and firing onReady after
      // teardown would resurrect a bubble for a Dreamfinder that has left.
      if (_bridge?.isReady == true) {
        _log.info('Dreamfinder avatar bridge ready — refreshing bubble');
        _onReady();
      }
    }).catchError((Object e) {
      _log.warning('Dreamfinder avatar bridge failed to initialize: $e');
    });
  }

  /// Tear the bridge down. Idempotent.
  void stop() {
    _bridge?.dispose();
    _bridge = null;
  }
}
