// Platform-aware direct track capture.
//
// This file exports the appropriate implementation based on the platform:
// - On web: Uses MediaStreamTrackProcessor-based implementation (Chrome only)
// - On native platforms: Uses a stub that returns null/no-op

export 'video_frame_web_v2_stub.dart'
    if (dart.library.js_interop) 'video_frame_web_v2.dart';
