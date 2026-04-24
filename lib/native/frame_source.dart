import 'dart:ui' as ui;

/// Minimal interface for frame producers that feed [VideoBubbleComponent].
///
/// Implemented by [CanvasCapture] (web canvas readback) and
/// [VideoElementCapture] (web video element capture).
abstract class FrameSource {
  /// Whether a new frame is ready to consume.
  bool get hasNewFrame;

  /// Take ownership of the current frame. Returns null if none available.
  /// Caller is responsible for disposing the returned image.
  ui.Image? consumeFrame();
}
