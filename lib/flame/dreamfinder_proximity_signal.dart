import 'dart:math';

import 'package:logging/logging.dart';
import 'package:tech_world/flame/shared/dreamfinder_territory.dart';
import 'package:tech_world/livekit/livekit_service.dart';

final _log = Logger('DreamfinderProximitySignal');

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
    required int Function() proximityRadius,
  })  : _liveKitService = liveKitService,
        _proximityRadius = proximityRadius;

  final LiveKitService? Function() _liveKitService;

  /// The user's "Proximity range" preference, read live like every other gate
  /// in this stack. Only its ZERO-ness is consulted — see [_recompute].
  final int Function() _proximityRadius;

  /// What the bot SHOULD believe. A pure function of the world, recomputed
  /// every frame, carrying no history.
  bool _desired = false;

  /// What the bot currently believes.
  ///
  /// Starts `false` because that is ACCURATE, not merely convenient: a bot
  /// that has been told nothing does not think anyone is near it. Modelling
  /// the initial state as "unknown" instead would make the first reconcile
  /// publish an unsolicited `near: false` for every player on every room
  /// entry — chatter that says nothing the bot did not already assume.
  bool _confirmed = false;

  /// Bumped whenever the RECIPIENT changes ([recipientChanged], never [reset]
  /// — a reset means the player moved, not that the body was swapped). A
  /// publish that settles
  /// after a bump is a reply from a participant who no longer exists, so it
  /// must not be allowed to write [_confirmed].
  ///
  /// Without this, the in-flight publish's own success callback restores the
  /// stale belief a moment after [reset] cleared it — the fix undone by the
  /// thing it was fixing.
  int _generation = 0;

  /// The value of the publish currently outstanding, or null if none.
  ///
  /// At most ONE publish is ever in flight. That single fact is what makes
  /// out-of-order delivery unrepresentable rather than compensated-for.
  bool? _inFlight;

  /// Whether the bot currently believes the player is inside the territory.
  ///
  /// Reports what was CONFIRMED, never what was merely attempted.
  bool get isNear => _confirmed;

  /// Recompute the desired state from the world and reconcile toward it.
  ///
  /// [territory] is null when Dreamfinder is absent or the map authors no
  /// square, and [playerGrid] is null when there is no local player — either
  /// makes the desired state `false` on its own, with no teardown path needing
  /// to remember to say so.
  void update({
    required Point<int>? playerGrid,
    required TerritoryRect? territory,
  }) {
    // CONJUNCTION, NOT SWAP: the radius preference OWNS the kill switch and
    // territory NARROWS within it.
    //
    // Territory replaced distance as the shape of "near" (PR #529) because
    // Dreamfinder wanders inside his square, so distance-to-sprite let him
    // hear players standing outside the box. But replacing the metric also
    // dropped the OWNER: `proximityRadius` is documented as the single source
    // of all proximity gates, and radius 0 means proximity is off.
    //
    // Only the zero-ness is used. Comparing the radius to a DISTANCE here is
    // exactly the coupling PR #529 removed, and would re-open the
    // heard-from-outside-the-box bug it fixed.
    _desired = _proximityRadius() > 0 &&
        playerGrid != null &&
        territory != null &&
        territory.contains(playerGrid.x, playerGrid.y);
    _pump();
  }

  /// Teardown exit: the player is leaving, so the bot must stop hearing them.
  ///
  /// Just a desired-state change down the same path as everything else: there
  /// is no separate teardown mechanism that a leave path could forget to call,
  /// and none to keep in sync with [update].
  void reset() {
    _desired = false;
    _pump();
  }

  /// The BODY this signal was talking to is gone, and anything that replaces it
  /// is a different participant.
  ///
  /// Distinct from [reset], and the distinction is the whole point. [reset] means
  /// "the player is no longer near" — the recipient is still listening, so a
  /// failed exit publish must NOT clear [_confirmed]: the bot really does still
  /// hold `near: true`, and pretending otherwise is the lie that suite pins.
  ///
  /// THIS means "there is no recipient". The agents SDK mints a fresh `agent-*`
  /// identity on every dispatch, so whatever arrives next has been told nothing
  /// — and "told nothing" IS `false`. Clearing [_confirmed] locally is therefore
  /// ACCURATE rather than convenient, and crucially it does not depend on a
  /// publish to the departed agent succeeding.
  ///
  /// That dependency was the hole. Routing a Dreamfinder LEAVE through [reset]
  /// meant a failed exit publish left `_confirmed` true; a player standing
  /// inside the square recomputed `_desired` to true; [_pump] saw them equal and
  /// sent nothing; and the new Dreamfinder was never told the player was there
  /// — the exact lost signal the leave path was added to prevent, surviving in
  /// its own failure branch. (Tesla, PR #530 delta cage-match.)
  ///
  /// [_inFlight] is deliberately NOT cleared, and the reason is narrower than
  /// "ordering" — the generation counter already neutralises the stale REPLY.
  /// What it does not neutralise is the stale MESSAGE: freeing the slot lets a
  /// second publish go out while the first is still unsent, and both carry a
  /// value for the same topic. If they landed out of order the new agent would
  /// end up holding the departed agent's value while [_confirmed] recorded the
  /// new one — a divergence between us and the bot, which is worse than a
  /// delay. LiveKit's reliable data channel does preserve per-publisher order,
  /// so in practice the newer value lands last; correctness would then rest on
  /// a transport property nothing in this file states or tests.
  ///
  /// THE COST, NAMED: while the old publish is outstanding, [_pump] returns
  /// early, so a new Dreamfinder arriving in that window is not told until it
  /// settles — typically milliseconds, but unbounded if the publish hangs.
  /// (Tesla, PR #530 round 3, which argued for releasing the slot.) Traded
  /// deliberately: a bounded delay over a divergence resting on an unstated
  /// guarantee. If the hang case ever shows up in a log, the fix is a timeout
  /// on the publish, not an early release.
  void recipientChanged() {
    _generation++;
    _desired = false;
    _confirmed = false;
  }


  /// Reconcile: if the bot's confirmed belief differs from what we want it to
  /// believe, and nothing is already in flight, send the difference.
  ///
  /// Three properties hold BY CONSTRUCTION here, and each replaces a guard:
  ///
  ///  * Nothing is latched optimistically, so no handler ever has to decide
  ///    whether the state it wants to revert is still its own.
  ///  * At most one publish is outstanding, so two sends can never settle out
  ///    of order. A newer desire waits, then wins.
  ///  * Failure needs no compensation: [_confirmed] simply does not advance,
  ///    and the next frame reconciles toward the CURRENT desire rather than
  ///    replaying a stale one. An absent service behaves identically.
  void _pump() {
    if (_inFlight != null) return;
    if (_confirmed == _desired) return;

    final service = _liveKitService();
    if (service == null) return;

    final sending = _desired;
    final generation = _generation;
    _inFlight = sending;
    service.publishDfProximity(near: sending).then((_) {
      _inFlight = null;
      // Record ONLY if the recipient is still the one we sent to. Across a
      // [recipientChanged] this publish was heard by a participant who has
      // since left, and
      // what a departed agent was told is not evidence about what the new one
      // believes. Recording it anyway is how the lost-signal bug came back.
      if (generation == _generation) {
        // Safe to record unconditionally within a generation: this was the only
        // publish in flight, so it is necessarily the last thing the bot heard.
        _confirmed = sending;
      }
      // Latest-wins: if the world moved while this was in flight, send the
      // difference now rather than waiting for another frame.
      //
      // Terminates, but NOT for the reason a pre-generation reading gives. A
      // success at the CURRENT generation advances `_confirmed`, so that arm
      // converges as before. A success at a STALE generation deliberately does
      // not — and the recursion still ends, because the only thing that makes a
      // generation stale is [recipientChanged], which leaves `_desired` and
      // `_confirmed` equal. So the re-pump either returns immediately or starts
      // exactly one publish at the current generation, which does advance.
      _pump();
    }).catchError((Object e) {
      // Release the slot but do NOT re-pump.
      //
      // Retrying here would spin: a persistently failing publish never
      // advances `_confirmed`, so an immediate re-pump sends again, fails
      // again, and loops with no air gap — a tight retry storm rather than a
      // recovery. (Found by this class's own tests hanging.) The next
      // `update()` call retries instead, which is frame-paced and bounded by
      // the game loop rather than by the failure rate.
      _inFlight = null;
      _log.warning(
          'df-proximity publish failed (near: $sending) — not confirmed, '
          'will retry on the next frame',
          e);
    });
  }
}
