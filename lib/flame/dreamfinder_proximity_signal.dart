import 'package:tech_world/livekit/livekit_service.dart';

/// Publishes the `df-proximity` enter/exit signal so Dreamfinder knows whether
/// the local player is close enough to be spoken to.
///
/// Outbound only: it tells the bot something, it never reads bubble or audio
/// state. That is why it is a signal rather than a gate — nothing local
/// changes when it fires.
///
/// ## Thresholds are deliberately the audio pair
///
/// The enter/exit distances are the same hysteresis pair the audio gate uses,
/// passed in rather than recomputed, so "Dreamfinder thinks you are in range"
/// and "you can hear Dreamfinder" cannot drift apart. They are supplied as
/// functions because the underlying radius is a user preference applied at
/// room entry.
///
/// ## Two invariants from the PR #481 cage match (Kelvin + Carnot)
///
/// **Hysteresis** — enter within the tighter threshold, and once near stay near
/// until past the looser one. Without it a player standing on the boundary
/// spams the reliable data channel every frame.
///
/// **Never latch what you could not send** — if the service is absent the state
/// is left untouched so the transition re-fires next frame. Latching a change
/// that was never published is the "signal lost forever" bug: the local side
/// believes it has told the bot, and never tells it again.
class DreamfinderProximitySignal {
  DreamfinderProximitySignal({
    required int Function() enableThreshold,
    required int Function() disableThreshold,
    required LiveKitService? Function() liveKitService,
  })  : _enableThreshold = enableThreshold,
        _disableThreshold = disableThreshold,
        _liveKitService = liveKitService;

  final int Function() _enableThreshold;
  final int Function() _disableThreshold;
  final LiveKitService? Function() _liveKitService;

  bool _wasNear = false;

  /// Whether the last successfully-published state was "near".
  bool get isNear => _wasNear;

  /// Recompute and publish on transition. [dfDistance] is null when Dreamfinder
  /// is absent, which forces an exit.
  void update(int? dfDistance) {
    final near = dfDistance != null &&
        (_wasNear
            ? dfDistance <= _disableThreshold()
            : dfDistance <= _enableThreshold());
    if (near == _wasNear) return;

    final service = _liveKitService();
    if (service == null) return; // can't emit — don't latch; retry next frame

    _wasNear = near;
    service.publishDfProximity(near: near);
  }

  /// Emit a final exit on teardown, so Dreamfinder isn't left holding a stale
  /// `near: true` for a player who has gone.
  ///
  /// Best-effort — the bot also self-heals on our ParticipantDisconnected — and
  /// the local flag clears either way, because after teardown there is no
  /// session left for a retry to belong to.
  void reset() {
    if (_wasNear) {
      _liveKitService()?.publishDfProximity(near: false);
    }
    _wasNear = false;
  }
}
