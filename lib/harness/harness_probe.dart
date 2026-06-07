/// Observation seam for the integration harness (seam S3).
///
/// Under the `TW_HARNESS` build flag, on web, publishes the client's
/// audio/proximity decisions to a `window.twHarnessJson` string the Playwright
/// harness reads via `JSON.parse(window.twHarnessJson)`. This keeps the harness
/// black-box: it reads a published surface, it does not reach into Dart
/// internals. A no-op in every normal build and on non-web platforms.
///
/// Conditional export so neither `dart:js_interop` nor its unsafe sibling leaks
/// into native/VM builds (mirrors `set_track_volume.dart`).
///
/// See docs/integration-harness.md.
library;

export 'harness_probe_stub.dart'
    if (dart.library.js_interop) 'harness_probe_web.dart';
