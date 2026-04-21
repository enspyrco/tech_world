// Platform-aware canvas capture.
//
// Exports the appropriate implementation based on platform:
// - On web: Captures frames from an HTMLCanvasElement via createImageBitmap
// - On native: Uses a no-op stub

export 'canvas_capture_stub.dart'
    if (dart.library.js_interop) 'canvas_capture_web.dart';
