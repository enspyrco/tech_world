// Stub implementation for non-web platforms.
//
// This provides no-op implementations so the code compiles on native platforms
// without the web package dependencies.

import 'dart:ui' as ui;

/// Always returns false on non-web platforms.
bool get isMediaStreamTrackProcessorSupported => false;

/// Stub DirectTrackCapture that does nothing on non-web platforms.
class DirectTrackCapture {
  DirectTrackCapture._();

  /// Always returns null on non-web platforms.
  static DirectTrackCapture? create(dynamic track) => null;

  /// Always returns null on non-web platforms (async version).
  static Future<DirectTrackCapture?> createAsync(
    dynamic track, {
    Duration timeout = const Duration(seconds: 5),
    Duration initialDelay = const Duration(milliseconds: 500),
  }) async => null;

  /// No-op on non-web platforms.
  static void cancelPendingUnmute() {}

  /// Always returns false.
  bool get hasNewFrame => false;

  /// Always returns false.
  bool get isActive => false;

  /// Always returns null.
  ui.Image? get currentFrame => null;

  /// Always returns 0.
  int get width => 0;

  /// Always returns 0.
  int get height => 0;

  /// Always returns 0.
  int get frameNumber => 0;

  /// No-op.
  void startCapture() {}

  /// No-op.
  void stopCapture() {}

  /// No-op.
  void markConsumed() {}

  /// Always returns null.
  ui.Image? consumeFrame() => null;

  /// No-op.
  void dispose() {}
}

/// Stub VideoElementCapture that does nothing on non-web platforms.
class VideoElementCapture {
  VideoElementCapture._();

  final bool ownsElement = true;

  /// Always returns null on non-web platforms.
  static VideoElementCapture? create(dynamic track) => null;

  /// Always returns null on non-web platforms.
  static Future<VideoElementCapture?> createFromStream(dynamic stream, dynamic track) async => null;

  /// Always returns null on non-web platforms.
  static VideoElementCapture? createFromVideoElement(dynamic videoElement) => null;

  /// Always returns null on non-web platforms.
  static VideoElementCapture? findAndCapture() => null;

  /// Always returns false.
  bool get hasNewFrame => false;

  /// Always returns false.
  bool get isActive => false;

  /// Always returns null.
  ui.Image? get currentFrame => null;

  /// Always returns 0.
  int get width => 0;

  /// Always returns 0.
  int get height => 0;

  /// Always returns 0.
  int get frameNumber => 0;

  /// No-op.
  void startCapture() {}

  /// No-op.
  void stopCapture() {}

  /// No-op.
  void markConsumed() {}

  /// Always returns null.
  ui.Image? consumeFrame() => null;

  /// No-op.
  void dispose() {}
}
