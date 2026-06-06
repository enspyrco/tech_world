/// Web implementation of [setTrackVolume].
///
/// livekit_client plays each subscribed remote audio track through an
/// `HTMLAudioElement` it appends to a hidden container, with DOM id
/// `livekit_audio_<cid>` (see livekit_client's `src/track/web/_audio_html.dart`,
/// `audioPrefix = 'livekit_audio_'`). We look that element up by id and set its
/// `volume` to fade the participant by distance.
///
/// This reaches into livekit_client's internal element-id scheme, which is the
/// only handle the SDK gives us — it exposes no per-track volume API. If the
/// prefix changes in a future SDK version the lookup simply misses and we
/// no-op, so the worst case is "no fade" (audio still plays via the gate), not
/// a crash. Typed `package:web` interop only — no dynamic dispatch (WASM-safe).
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// livekit_client's audio-element id prefix (`_audio_html.dart`).
const _audioElementPrefix = 'livekit_audio_';

void setTrackVolume(String cid, double volume) {
  final element = web.document.getElementById('$_audioElementPrefix$cid');
  if (element == null || !element.isA<web.HTMLAudioElement>()) return;
  (element as web.HTMLAudioElement).volume = volume.clamp(0.0, 1.0);
}
