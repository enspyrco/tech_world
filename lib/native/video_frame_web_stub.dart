// Stub implementation for non-web platforms.
//
// This provides no-op implementations so the code compiles on native platforms
// without the web package dependencies.

import 'dart:ui' as ui;

/// Stub WebVideoFrameCapture that does nothing on non-web platforms.
class WebVideoFrameCapture {
  WebVideoFrameCapture._();

  /// Always returns null on non-web platforms.
  static Future<WebVideoFrameCapture?> createFromStream(dynamic stream) async =>
      null;

  /// Always returns null on non-web platforms.
  static Future<WebVideoFrameCapture?> createFromTrack(dynamic track) async =>
      null;

  /// Always returns null on non-web platforms.
  static dynamic findVideoElementByTrackId(String trackId) => null;

  /// No-op on non-web platforms.
  static void debugListVideoElements() {}

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
