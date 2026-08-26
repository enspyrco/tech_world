import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/livekit/livekit_service.dart';

/// Distance-driven audio gate: who is subscribed, and how loud.
///
/// Two layers, deliberately not one:
///  - a **hard enable/disable** with hysteresis, which is the SFU subscription
///    boundary and therefore the bandwidth saver;
///  - a **per-square volume ramp** inside it, so voices fade with range rather
///    than cutting out at the edge.
///
/// ## Why this takes a distance, never an `isNearby` bool
///
/// The three proximity gates in this game look like one threshold and are not.
/// The visual gate is `proximityRadius`. This gate is a *pair* —
/// [enableThreshold] one square tighter, [disableThreshold] at the radius —
/// and the ramp between them needs the actual distance, not a side of a line.
/// Collapsing them into a boolean re-opens the see-but-can't-hear dead zone and
/// makes a peer standing on the boundary flap the SFU forward on and off.
///
/// ## Why gate state only advances when the send lands
///
/// Every state mutation here is paired with a confirmed effect. If the service
/// is absent the gate does not latch, so the transition re-fires next frame;
/// if a volume write no-ops because the track has not subscribed yet, the cache
/// is not written, so the next frame retries. Latching a change that was never
/// sent is how a signal gets lost forever — the bug PR #481 closed.
class ProximityAudioGate {
  ProximityAudioGate({
    required int Function() proximityRadius,
    required LiveKitService? Function() liveKitService,
    required bool Function() diagnosticsEnabled,
    required String Function() dreamfinderIdentity,
  })  : _proximityRadius = proximityRadius,
        _liveKitService = liveKitService,
        _diagnosticsEnabled = diagnosticsEnabled,
        _dreamfinderIdentity = dreamfinderIdentity;

  final int Function() _proximityRadius;
  final LiveKitService? Function() _liveKitService;
  final bool Function() _diagnosticsEnabled;
  final String Function() _dreamfinderIdentity;

  /// Distance at or below which a voice plays at full volume; beyond it the
  /// ramp steps down to silence at [disableThreshold].
  static const int fullVolumeDistance = 1;

  final Set<String> _enabled = {};

  /// Last volume pushed to LiveKit per participant, so the per-frame ramp only
  /// writes when the value actually changes (distance is an int, so for a
  /// stationary peer that is most frames, and the web path is a DOM write).
  final Map<String, double> _volumes = {};

  /// Audio enables at or within this distance. One square tighter than the
  /// visual range, so you can hear almost anyone whose bubble you can see.
  ///
  /// At radius 0 this is -1, which no distance satisfies — proximity-disabled
  /// means silent, with no special case needed.
  int get enableThreshold => _proximityRadius() - 1;

  /// Audio cuts only once past this distance. The one-square gap to
  /// [enableThreshold] is the hysteresis band.
  int get disableThreshold => _proximityRadius();

  bool isEnabled(String participantId) => _enabled.contains(participantId);

  /// Volume curve: full within [fullVolumeDistance], then a linear step-down
  /// per grid square to silence at [disableThreshold]. Stepwise (distance is
  /// an int), not continuous.
  double volumeForDistance(int distance) {
    if (distance <= fullVolumeDistance) return 1.0;
    final span = disableThreshold - fullVolumeDistance;
    // Radius <= 1 collapses the ramp to nothing. Only reachable if a caller
    // mutates the radius mid-session; the early return above already covers
    // every distance the gate can have enabled at that radius, so this guards
    // the division rather than the behaviour.
    if (span <= 0) return 1.0;
    return ((disableThreshold - distance) / span).clamp(0.0, 1.0);
  }

  /// Apply the gate to one participant at [distance] grid squares.
  void update(String participantId, int distance) {
    // No LiveKit service yet (pre-connect / post-teardown) -> don't mutate the
    // gate state. Latching a state change we couldn't actually send leaves the
    // gate stuck once the service comes up (the next frame sees "no change").
    final service = _liveKitService();
    if (service == null) return;

    final hasAudio = _enabled.contains(participantId);

    // Hysteresis: enable when within the (tighter) enable threshold, disable
    // only once past the (looser) disable threshold. Between the two, hold the
    // current state.
    if (!hasAudio && distance <= enableThreshold) {
      _enabled.add(participantId);
      service.setParticipantAudioEnabled(participantId, true);
      _emit(participantId, enabled: true, distance: distance);
    } else if (hasAudio && distance > disableThreshold) {
      _enabled.remove(participantId);
      _volumes.remove(participantId); // re-set volume on next enable
      service.setParticipantAudioEnabled(participantId, false);
      _emit(participantId, enabled: false, distance: distance);
    }

    if (!_enabled.contains(participantId)) return;

    final volume = volumeForDistance(distance);
    if (_volumes[participantId] == volume) return;
    // Cache only if the volume actually landed on a track. If the track hasn't
    // subscribed yet the call no-ops; caching anyway would suppress the retry
    // and leave the late track stuck at default volume.
    if (service.setParticipantAudioVolume(participantId, volume)) {
      _volumes[participantId] = volume;
    }
  }

  /// Gate Dreamfinder audio at [dfDistance], honouring the local silence
  /// toggle.
  ///
  /// Gates EVERY DF participant in the room, not just the last-bound identity
  /// slot. Agent respawns and stale sessions mean more than one `agent-*`
  /// identity can exist at once, and any identity outside the gate is
  /// ungoverned audio — half of the 2026-07-18 silence failure.
  void updateDreamfinder(int dfDistance) {
    final service = _liveKitService();
    final silenced = service?.dreamfinderSilenced.value ?? false;
    // Silence is expressed as "infinitely far", so it flows through the same
    // hysteresis and the same send-confirmed latching as real distance rather
    // than being a second, parallel path to the same state.
    final fedDistance = silenced ? disableThreshold + 1 : dfDistance;

    final ids = <String>{
      _dreamfinderIdentity(),
      ...?service?.dreamfinderIdentities(),
    };

    for (final id in ids) {
      update(id, fedDistance);
      if (silenced && service != null && _volumes[id] != 0.0) {
        // Local hard-mute while silenced: the ramp above only writes volume
        // for gate-ENABLED participants, so after the silence disable nothing
        // else touches the playback element — if the server-side disable is
        // ineffective (the other half of the 2026-07-18 failure), audio keeps
        // playing at its last volume forever. Same retry-until-landed caching
        // semantics as the ramp.
        if (service.setParticipantAudioVolume(id, 0.0)) {
          _volumes[id] = 0.0;
        }
      }
    }
  }

  /// Drop bookkeeping for a participant who vanished.
  ///
  /// An ungraceful disconnect never crosses the disable threshold in the
  /// proximity loop, so without this their entries leak until teardown.
  void forget(String participantId) {
    _enabled.remove(participantId);
    _volumes.remove(participantId);
  }

  void clear() {
    _enabled.clear();
    _volumes.clear();
  }

  void _emit(String participantId,
      {required bool enabled, required int distance}) {
    if (!_diagnosticsEnabled()) return;
    dispatch([
      AvAudioGateChanged(
        participant: participantId,
        enabled: enabled,
        distance: distance,
      )
    ]);
  }
}
