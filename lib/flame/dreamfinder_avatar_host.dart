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
      // Guarded on IDENTITY, like the two arms below. Reading the field's
      // readiness alone covered teardown (a `stop()` nulls the field, so a late
      // onReady cannot resurrect a bubble for a departed Dreamfinder) but not
      // REPLACEMENT: `stop()` then `start()` leaves two initialize futures in
      // flight, and when the OLD one settles while the NEW bridge is already
      // ready, the field reads ready and `_onReady()` fires for a successor
      // this callback never initialized. Identity covers both — a nulled field
      // and a replaced one are equally not-this-bridge. Third arm on the same
      // iframe; the other two were locked first. (Tesla, PR #530 round 2.)
      if (identical(_bridge, bridge) && bridge.isReady) {
        _log.info('Dreamfinder avatar bridge ready — refreshing bubble');
        // Isolated from the initialize future on purpose. `_onReady` is a
        // CALLER'S callback, and letting it throw into this chain routes it to
        // `catchError` below, which then releases the slot for a bridge that
        // DID become ready — the next Dreamfinder builds a second iframe
        // beside a live one nobody will ever stop(). A consumer's failure is
        // not evidence about the bridge. (Tesla, PR #530 delta cage-match.)
        try {
          _onReady();
        } catch (e, st) {
          _log.warning('Dreamfinder avatar onReady callback threw — bridge '
              'stays live', e, st);
        }
      } else if (identical(_bridge, bridge)) {
        // Completed WITHOUT becoming ready — a timeout folded into a non-ready
        // state, an iframe that loaded but failed to capture, or any
        // implementation that reports failure through state rather than an
        // exception. `catchError` never fires for that, so an earlier version
        // of this fix closed only the throwing door and left this one open:
        // the slot stayed held by something that would never be ready, and
        // `start()`'s `_bridge != null` guard made every later Dreamfinder
        // arrival a no-op exactly as before.
        //
        // Disposed as well as cleared, matching [stop] — the bridge owns an
        // iframe, and dropping the reference without disposing leaks it.
        _log.warning('Dreamfinder avatar bridge initialized but never became '
            'ready — releasing the slot');
        bridge.dispose();
        _bridge = null;
      }
    }).catchError((Object e) {
      _log.warning('Dreamfinder avatar bridge failed to initialize: $e');
      // Release the slot. `start()` early-returns on `_bridge != null`, so a
      // bridge left occupying it after a FAILED initialize made every later
      // Dreamfinder arrival a silent no-op for the rest of the session — a
      // latch held by something that was never ready to send.
      //
      // Guarded on identity, not just non-null: a `stop()` or a newer `start()`
      // may already have replaced the field, and clearing that one would undo
      // a live bridge on behalf of a dead one.
      //
      // DISPOSED as well as cleared, matching [stop] and the non-ready branch
      // above. A failed initialize can still have constructed the iframe, and
      // this branch used to drop the reference without disposing — the exact
      // leak the branch above writes a comment against, surviving one door
      // over. (Tesla, PR #530 delta cage-match.)
      if (identical(_bridge, bridge)) {
        bridge.dispose();
        _bridge = null;
      }
    });
  }

  /// Tear the bridge down. Idempotent.
  void stop() {
    _bridge?.dispose();
    _bridge = null;
  }
}
