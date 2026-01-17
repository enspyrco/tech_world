// Stub implementation for platforms that don't support FFI (e.g., web).
//
// This file provides no-op implementations of the VideoFrameCapture class
// so that the code compiles on web without dart:ffi.

/// Stub VideoFrameCapture that does nothing on unsupported platforms.
class VideoFrameCapture {
  VideoFrameCapture._();

  /// Always returns null on unsupported platforms.
  static VideoFrameCapture? create(
    String trackId, {
    int targetFps = 15,
    int maxWidth = 640,
    int maxHeight = 480,
  }) {
    return null;
  }

  /// Always returns false.
  bool get hasNewFrame => false;

  /// Always returns false.
  bool get isActive => false;

  /// Always returns 0.
  int get width => 0;

  /// Always returns 0.
  int get height => 0;

  /// Always returns 0.
  int get bytesPerRow => 0;

  /// Always returns 0.
  int get frameNumber => 0;

  /// Always returns 0.
  int get timestamp => 0;

  /// Always returns null.
  dynamic getPixels() => null;

  /// No-op.
  void markConsumed() {}

  /// No-op.
  void dispose() {}

  /// Always returns empty list.
  static List<String> listTracks() => [];
}
