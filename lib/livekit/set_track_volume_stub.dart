/// Non-web stub for [setTrackVolume].
///
/// There is no portable per-remote-track playback-volume API in
/// livekit_client 2.7.0, and the web element trick doesn't apply off-web, so
/// this is a deliberate no-op. The distance fade is therefore web-only today;
/// the proximity enable/disable gate still works everywhere. A native fade
/// (via `flutter_webrtc`'s `Helper.setVolume`) can be implemented here later.
void setTrackVolume(String cid, double volume) {}
