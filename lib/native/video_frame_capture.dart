// Platform-aware video frame capture.
//
// This file exports the appropriate implementation based on the platform:
// - On native platforms (macOS, iOS, Android, etc.): Uses FFI-based implementation
// - On web: Uses a stub that returns null/no-op

export 'video_frame_ffi_stub.dart' if (dart.library.ffi) 'video_frame_ffi.dart';
