import 'dart:async';

import 'package:logging/logging.dart';
import 'package:tech_world/avatar/avatar_spec.dart';

final _log = Logger('AvatarUpdateThrottle');

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

  /// How many consecutive `_apply` throws a single spec gets before it is
  /// dropped. Three, not one: a transient failure (a decode that races a
  /// disposal, a momentarily-missing asset) should survive, while a spec that
  /// is simply un-appliable must not retry until the peer leaves.
  static const int maxApplyFailures = 3;

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
        // Schedule the next window FIRST so a retry exists either way.
        window.timer = _startTimer(playerId);
        try {
          _apply(playerId, pending);
          window.failures = 0;
          // Latch ONLY after the apply landed.
          //
          // Clearing `pending` and advancing `lastApplied` before the call
          // recorded the effect as complete whether or not it happened — and a
          // throw inside a Timer callback is a silent async error. The final
          // spec in a burst was then lost twice over: nothing applied it, and
          // `lastApplied` now equalled it, so a rebroadcast of the same spec
          // deduped away too. Peers rendered a stale avatar until some
          // DIFFERENT spec arrived.
          // Cleared only if it is STILL the spec we applied. `_apply` runs
          // synchronously, so anything it re-entrantly submits for this peer
          // lands in `pending` before this line — and a blind null would drop
          // that newer spec on the floor, which is the same lost-update the
          // latch-after-apply order exists to prevent, one step later.
          if (identical(window.pending, pending)) window.pending = null;
          window.lastApplied = pending;
        } catch (e) {
          // BOUNDED. `pending` left set means the window just scheduled will
          // retry — and for a spec that throws every time, that is a composite
          // attempt plus a warning line every `interval`, forever, driven by a
          // value a PEER chose. This class's own header calls itself the bound
          // on peer-controlled compose work, so an unbounded retry inside it is
          // the bound leaking. The sibling reconciler in
          // dreamfinder_proximity_signal refuses this pattern by name ("loops
          // with no air gap"); this one had it. (Tesla, PR #530 round 3.)
          //
          // On giving up the spec is QUARANTINED into `lastApplied` rather than
          // merely dropped, so a rebroadcast of the same bad spec dedupes away
          // instead of restarting the loop, while any DIFFERENT spec still
          // applies normally.
          window.failures++;
          if (window.failures >= maxApplyFailures) {
            if (identical(window.pending, pending)) window.pending = null;
            window.lastApplied = pending;
            window.failures = 0;
            _log.severe(
                'avatar apply failed $maxApplyFailures times for $playerId — '
                'dropping this spec; a different spec will still apply',
                e);
          } else {
            _log.warning(
                'avatar apply failed for $playerId '
                '(${window.failures}/$maxApplyFailures) — retrying next window',
                e);
          }
        }
      });
}

class _PeerWindow {
  Timer? timer;

  /// Consecutive `_apply` throws for [pending]. Reset on any success.
  int failures = 0;
  AvatarSpec? pending;

  /// The spec most recently handed to `apply` for this peer, so an unchanged
  /// re-broadcast can be dropped rather than scheduled.
  AvatarSpec? lastApplied;
}
