/// Sets the playback volume (0.0–1.0) of a subscribed remote audio track,
/// keyed by the track's LiveKit CID, so the proximity layer can fade voices by
/// distance instead of hard-cutting them.
///
/// Web sets the `volume` on the `HTMLAudioElement` that livekit_client
/// auto-creates per remote track. Other platforms no-op for now — the
/// proximity gate's enable/disable still applies, just without the fade.
///
/// Conditional export so neither `package:web` nor `dart:js_interop` leaks into
/// native/VM builds (mirrors `platform_info.dart`).
library;

export 'set_track_volume_stub.dart'
    if (dart.library.js_interop) 'set_track_volume_web.dart';
