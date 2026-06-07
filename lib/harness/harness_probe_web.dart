import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// `const` so the whole probe tree-shakes out of a non-harness web build.
const bool _harnessEnabled = bool.fromEnvironment('TW_HARNESS');

bool _dfProximityNear = false;
final Set<String> _audioEnabled = <String>{};
final Map<String, double> _volumes = <String, double>{};

/// Serialise the current observed state to `window.twHarnessJson` as a JSON
/// string. A single string property (rather than a live JS object graph) keeps
/// the read side trivial: `JSON.parse(window.twHarnessJson)` in Playwright.
void _flush() {
  final snapshot = json.encode({
    'dfProximityNear': _dfProximityNear,
    'audioEnabledCids': _audioEnabled.toList(),
    'participantVolumes': _volumes,
  });
  globalContext.setProperty('twHarnessJson'.toJS, snapshot.toJS);
}

/// Record whether the local player is within Dreamfinder's range (bug #1's
/// terminal layer — the df-proximity decision the client actually made).
void harnessSetDfProximity(bool near) {
  if (!_harnessEnabled) return;
  _dfProximityNear = near;
  _flush();
}

/// Record whether a remote participant's audio is currently enabled (bug #3's
/// terminal layer — the proximity gate's actual enable/disable decision).
void harnessSetAudioEnabled(String identity, bool enabled) {
  if (!_harnessEnabled) return;
  if (enabled) {
    _audioEnabled.add(identity);
  } else {
    _audioEnabled.remove(identity);
  }
  _flush();
}

/// Record the playback volume the proximity layer applied to a participant.
/// Lets the harness cross-check the intended volume against the actual DOM
/// `HTMLAudioElement.volume` (bug #2).
void harnessSetVolume(String identity, double volume) {
  if (!_harnessEnabled) return;
  _volumes[identity] = volume;
  _flush();
}
