// Stub implementation for non-web platforms.

import 'dart:ui' as ui;

/// Stub CanvasCapture that does nothing on non-web platforms.
class CanvasCapture {
  CanvasCapture._();

  /// Always returns false.
  bool get hasNewFrame => false;

  /// Always returns null.
  ui.Image? consumeFrame() => null;

  /// No-op.
  void startCapture() {}

  /// No-op.
  void stopCapture() {}

  /// No-op.
  void dispose() {}
}
