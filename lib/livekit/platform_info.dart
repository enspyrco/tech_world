/// Platform-aware metadata for the agent-hello diagnostic payload.
///
/// Returns the OS name (or `"web"`) and an optional userAgent string. Uses
/// conditional exports so neither `dart:io` nor `dart:js_interop` leaks into
/// the wrong build.
library;

export 'platform_info_io.dart'
    if (dart.library.js_interop) 'platform_info_web.dart';
