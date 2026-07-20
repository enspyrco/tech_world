/// Platform-aware "must this client run in web safe mode?" probe.
///
/// Exposes [requiresWebSafeMode] — `true` when the current client should be
/// forced into avatar-only + reduced-motion mode to survive world entry. Uses
/// conditional exports so `dart:js_interop` never leaks into native builds and
/// `dart:io` never leaks into web builds (mirrors `platform_info.dart`).
///
/// The at-risk decision lives in the pure, unit-tested `isLegacyIosWebClient`
/// (`web_safe_mode_policy.dart`); the web impl feeds it `navigator.userAgent`
/// and fails **closed** (returns `true`) if that read throws — a crash-safety
/// floor must withhold the heavy path under uncertainty, not grant it.
library;

export 'web_safe_mode_io.dart'
    if (dart.library.js_interop) 'web_safe_mode_web.dart';
