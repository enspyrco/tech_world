import 'dart:async';

import 'package:tech_world/avatar/avatar_spec.dart';

/// Rate-limits how often each peer can change how they look.
///
/// Avatar updates are peer-controlled input that drives real work: every
/// distinct spec composites a 512x64 sheet and rebuilds a component's
/// animations. The composed-sheet cache bounds the *memory*, but nothing
/// bounds how fast a peer can make us do that work — a client publishing on
/// the data channel at frame rate would have every other client recompositing
/// continuously. This is the bound.
///
/// **Leading edge, then trailing edge.** The first update for a peer applies
/// immediately, because a player changing their character should see it happen
/// at once rather than after a delay. Further updates within [interval] are
/// collapsed into a single pending value, applied when the window closes. A
/// peer flipping between two outfits sixty times a second therefore causes at
/// most one recomposite per interval, and — crucially — still ends up showing
/// the outfit they finished on, not the one that happened to arrive first.
///
/// Only the LATEST pending spec survives, which is what makes this a throttle
/// rather than a queue: intermediate states in a flood were never seen by
/// anyone and are not worth rendering.
class AvatarUpdateThrottle {
  AvatarUpdateThrottle({
    required void Function(String playerId, AvatarSpec spec) apply,
    this.interval = const Duration(milliseconds: 500),
  }) : _apply = apply;

  final void Function(String playerId, AvatarSpec spec) _apply;

  /// Minimum time between two applied updates for the same peer.
  final Duration interval;

  final Map<String, _PeerWindow> _windows = {};

  /// Offer an update for [playerId]. Applies now or schedules, per the class
  /// doc.
  void submit(String playerId, AvatarSpec spec) {
    final window = _windows[playerId];
    if (window == null) {
      _apply(playerId, spec);
      _windows[playerId] = _PeerWindow()
        ..lastApplied = spec
        ..timer = _startTimer(playerId);
      return;
    }

    // Inside the window. Hold the newest value; drop it if it's what we
    // already applied, so a peer re-broadcasting an unchanged avatar (the
    // late-joiner catch-up does exactly this) doesn't schedule a no-op
    // recomposite.
    window.pending = spec == window.lastApplied ? null : spec;
  }

  /// Stop tracking [playerId] — call when a participant leaves.
  ///
  /// Without this, a peer who leaves mid-window leaves a live [Timer] that
  /// fires into a component that no longer exists, and the map grows by one
  /// entry per participant the session ever saw.
  void forget(String playerId) {
    _windows.remove(playerId)?.timer?.cancel();
  }

  /// Drop every peer's state. Call on room teardown.
  void clear() {
    for (final window in _windows.values) {
      window.timer?.cancel();
    }
    _windows.clear();
  }

  Timer _startTimer(String playerId) => Timer(interval, () {
        final window = _windows[playerId];
        if (window == null) return;
        final pending = window.pending;
        if (pending == null) {
          // Quiet window — stop tracking, so the next update from this peer is
          // a leading edge again and applies immediately.
          _windows.remove(playerId);
          return;
        }
        window
          ..pending = null
          ..lastApplied = pending
          ..timer = _startTimer(playerId);
        _apply(playerId, pending);
      });
}

class _PeerWindow {
  Timer? timer;
  AvatarSpec? pending;

  /// The spec most recently handed to `apply` for this peer, so an unchanged
  /// re-broadcast can be dropped rather than scheduled.
  AvatarSpec? lastApplied;
}
