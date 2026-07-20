/// Platform-aware device-capability probe.
///
/// Exposes [isLowMemoryDevice] — `true` when the current device should default
/// to the low-memory safe mode (avatar-only bubbles + reduced motion). Uses
/// conditional exports so `dart:js_interop` never leaks into native builds and
/// `dart:io` never leaks into web builds (mirrors `platform_info.dart`).
///
/// The at-risk decision itself lives in the pure, unit-tested
/// `isLowMemoryUserAgent` (`low_memory_heuristic.dart`); the web impl just feeds
/// it `navigator.userAgent`.
library;

export 'device_capability_io.dart'
    if (dart.library.js_interop) 'device_capability_web.dart';
