import 'dart:math';

import 'package:tech_world/flame/shared/dreamfinder_territory.dart';
import 'package:tech_world/livekit/livekit_service.dart';

/// Publishes the `df-proximity` enter/exit signal so Dreamfinder knows whose
/// speech he is allowed to hear.
///
/// Outbound only: it tells the bot something, it never reads bubble or audio
/// state. That is why it is a signal rather than a gate — nothing local
/// changes when it fires.
///
/// ## Territory, not distance
///
/// "Near" means **standing inside Dreamfinder's territory square**, which is
/// what [TerritoryRect] has claimed all along: *"the overlay draws it,
/// Dreamfinder wanders within it, and the bot only hears players standing
/// inside it."* Until 2026-08-30 that sentence was false. The signal measured
/// Chebyshev distance to Dreamfinder's *sprite* using the audio-proximity
/// thresholds, and Dreamfinder wanders *within* his square — so a player
/// standing outside the box, next to a host who happened to be near its edge,
/// was heard. Reported from the outside as "he hears us when we're nearby the
/// box", which is exactly the geometry that produces.
///
/// The rect read here is the same object the overlay draws
/// ([DreamfinderComponent.territory]), so what you SEE is what he hears. A box
/// you can stand outside of is a promise to the player; distance-to-sprite
/// could not keep it, because the thing being measured moves.
///
/// ## This deliberately breaks an older coupling
///
/// The previous implementation used the audio gate's hysteresis pair on
/// purpose, so "Dreamfinder thinks you are in range" and "you can hear
/// Dreamfinder" could not drift apart (PR #481). They now differ by design:
/// he hears you only inside his square, while you still hear him by proximity
/// from outside it. Two docs disagreed about which rule was real; the
/// territory contract won.
///
/// ## Hysteresis is gone, and does not need replacing
///
/// Hysteresis existed because a player standing on a *distance* boundary would
/// spam the reliable data channel every frame. Grid containment has no such
/// boundary: [Point] cells are discrete and a stationary player's cell does not
/// oscillate, so a transition only fires when the player actually crosses the
/// edge.
///
/// ## The invariant that survived unchanged
///
/// **Never latch what you could not send** — if the service is absent the state
/// is left untouched so the transition re-fires next frame. Latching a change
/// that was never published is the "signal lost forever" bug: the local side
/// believes it has told the bot, and never tells it again.
class DreamfinderProximitySignal {
  DreamfinderProximitySignal({
    required LiveKitService? Function() liveKitService,
  }) : _liveKitService = liveKitService;

  final LiveKitService? Function() _liveKitService;

  bool _wasInside = false;

  /// Whether the last successfully-published state was "inside the territory".
  bool get isNear => _wasInside;

  /// Recompute and publish on transition.
  ///
  /// [territory] is null when Dreamfinder is absent or the map authors no
  /// square, and [playerGrid] is null when there is no local player — either
  /// forces an exit, so the bot never keeps hearing a player it can no longer
  /// locate.
  void update({
    required Point<int>? playerGrid,
    required TerritoryRect? territory,
  }) {
    final inside = playerGrid != null &&
        territory != null &&
        territory.contains(playerGrid.x, playerGrid.y);
    if (inside == _wasInside) return;

    final service = _liveKitService();
    if (service == null) return; // can't emit — don't latch; retry next frame

    _wasInside = inside;
    service.publishDfProximity(near: inside);
  }

  /// Teardown exit: tell Dreamfinder the player is gone.
  ///
  /// Unconditional, unlike [update] — a player leaving the room must not leave
  /// the bot holding a stale `near: true`.
  void reset() {
    _wasInside = false;
    _liveKitService()?.publishDfProximity(near: false);
  }
}
