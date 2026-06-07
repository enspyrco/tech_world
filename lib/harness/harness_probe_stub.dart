// Non-web (and therefore non-harness) stub for the observation seam: every
// call is a no-op. See harness_probe.dart.

/// Record whether the local player is within Dreamfinder's range.
void harnessSetDfProximity(bool near) {}

/// Record whether a remote participant's audio is currently enabled.
void harnessSetAudioEnabled(String identity, bool enabled) {}

/// Record the playback volume the proximity layer applied to a participant.
void harnessSetVolume(String identity, double volume) {}
