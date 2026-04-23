/// Captures frames from an HTMLCanvasElement via createImageBitmap.
///
/// Designed for capturing Three.js render output from a same-origin iframe.
/// Uses the same frame interface as [VideoElementCapture] so it plugs directly
/// into [VideoBubbleComponent]'s existing frame consumption loop.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:logging/logging.dart';
import 'package:web/web.dart' as web;

final _log = Logger('CanvasCapture');

class CanvasCapture {
  CanvasCapture._(this._canvas, {int fps = 15, this.onBeforeCapture})
      : _captureInterval = Duration(milliseconds: (1000 / fps).round());

  final web.HTMLCanvasElement _canvas;
  final Duration _captureInterval;

  /// Optional callback invoked before each frame capture.
  /// Used to force a render when the canvas uses preserveDrawingBuffer: false.
  final void Function()? onBeforeCapture;

  ui.Image? _currentFrame;
  bool _hasNewFrame = false;
  bool _isCapturing = false;
  bool _frameInFlight = false;
  int _frameNumber = 0;
  Timer? _captureTimer;

  /// Create a capture from an HTMLCanvasElement.
  static CanvasCapture? create(
    web.HTMLCanvasElement canvas, {
    int fps = 15,
    void Function()? onBeforeCapture,
  }) {
    if (canvas.width == 0 && canvas.height == 0) {
      _log.warning('Canvas has zero dimensions');
    }
    return CanvasCapture._(canvas, fps: fps, onBeforeCapture: onBeforeCapture);
  }

  bool get hasNewFrame => _hasNewFrame;

  /// Consume the current frame, transferring ownership to the caller.
  ui.Image? consumeFrame() {
    _hasNewFrame = false;
    final frame = _currentFrame;
    _currentFrame = null;
    return frame;
  }

  void startCapture() {
    if (_isCapturing) return;
    _isCapturing = true;
    _captureTimer = Timer.periodic(_captureInterval, (_) => _captureFrame());
    _log.info('Started canvas capture at ${_captureInterval.inMilliseconds}ms interval');
  }

  void stopCapture() {
    _isCapturing = false;
    _captureTimer?.cancel();
    _captureTimer = null;
    _log.info('Stopped canvas capture');
  }

  Future<void> _captureFrame() async {
    if (!_isCapturing || _frameInFlight) return;

    final w = _canvas.width;
    final h = _canvas.height;
    if (w == 0 || h == 0) return;

    _frameInFlight = true;

    try {
      // Force a render if the canvas doesn't preserve its drawing buffer.
      onBeforeCapture?.call();

      final imageBitmap = await web.window
          .createImageBitmap(_canvas as web.ImageBitmapSource)
          .toDart;

      ui.Image newFrame;
      try {
        newFrame = await ui_web.createImageFromImageBitmap(
          imageBitmap as JSAny,
        );
      } finally {
        // Always close the ImageBitmap to prevent VideoFrame GC leak.
        // createImageFromImageBitmap transfers the pixel data; the
        // ImageBitmap handle itself must still be released.
        imageBitmap.close();
      }

      final oldFrame = _currentFrame;
      _currentFrame = newFrame;
      _hasNewFrame = true;
      _frameNumber++;

      if (_frameNumber == 1) {
        _log.info('First canvas frame captured: ${w}x$h');
      }

      oldFrame?.dispose();
    } catch (e) {
      _log.warning('Canvas frame capture error: $e', e);
    } finally {
      _frameInFlight = false;
    }
  }

  void dispose() {
    stopCapture();
    _currentFrame?.dispose();
    _currentFrame = null;
  }
}
