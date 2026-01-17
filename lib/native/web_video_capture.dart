// Platform-aware web video frame capture.
//
// This file exports the appropriate implementation based on the platform:
// - On web: Uses createImageBitmap-based implementation
// - On native platforms: Uses a stub that returns null/no-op

export 'video_frame_web_stub.dart'
    if (dart.library.js_interop) 'video_frame_web.dart';
