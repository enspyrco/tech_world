/// Captures frames from an HTMLCanvasElement via direct pixel readback.
///
/// Designed for capturing Three.js render output from a same-origin iframe.
/// Uses the same frame interface as [VideoElementCapture] so it plugs directly
/// into [VideoBubbleComponent]'s existing frame consumption loop.
///
/// Capture pipeline: drawImage(source canvas → offscreen 2D canvas) →
/// getImageData → decodeImageFromPixels → ui.Image.
///
/// This is the simplest possible capture path — no captureStream, no
/// VideoFrames, no ImageBitmaps, no createImageFromImageBitmap. Just a
/// direct canvas-to-canvas pixel copy via the 2D context.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:logging/logging.dart';
import 'package:web/web.dart' as web;

final _log = Logger('CanvasCapture');

class CanvasCapture {
  CanvasCapture._(this._canvas, {int fps = 15})
      : _captureInterval = Duration(milliseconds: (1000 / fps).round());

  final web.HTMLCanvasElement _canvas;
  final Duration _captureInterval;

  ui.Image? _currentFrame;
  bool _hasNewFrame = false;
  bool _isCapturing = false;
  bool _frameInFlight = false;
  int _frameNumber = 0;
  Timer? _captureTimer;

  // Offscreen 2D canvas for pixel readback.
  web.HTMLCanvasElement? _offscreen;
  web.CanvasRenderingContext2D? _offscreenCtx;

  /// Create a capture from an HTMLCanvasElement.
  static CanvasCapture? create(
    web.HTMLCanvasElement canvas, {
    int fps = 15,
    void Function()? onBeforeCapture,
  }) {
    if (canvas.width == 0 && canvas.height == 0) {
      _log.warning('Canvas has zero dimensions');
    }
    return CanvasCapture._(canvas, fps: fps);
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
    _log.info(
      'Started canvas capture via direct drawImage readback '
      'at ${_captureInterval.inMilliseconds}ms interval',
    );
  }

  void stopCapture() {
    _isCapturing = false;
    _captureTimer?.cancel();
    _captureTimer = null;
    _log.info('Stopped canvas capture');
  }

  Future<void> _captureFrame() async {
    if (!_isCapturing) return;
    if (_frameInFlight) return;

    final w = _canvas.width;
    final h = _canvas.height;
    if (w == 0 || h == 0) return;

    _frameInFlight = true;

    try {
      // Ensure offscreen canvas matches source dimensions.
      if (_offscreen == null ||
          _offscreen!.width != w ||
          _offscreen!.height != h) {
        _offscreen =
            web.document.createElement('canvas') as web.HTMLCanvasElement;
        _offscreen!.width = w;
        _offscreen!.height = h;
        _offscreenCtx =
            _offscreen!.getContext('2d')! as web.CanvasRenderingContext2D;
      }

      // Direct canvas-to-canvas copy. This is the exact call we verified
      // produces pixels from the browser console:
      //   [239, 205, 180, 255] — skin tone from the 3D avatar.
      _offscreenCtx!.drawImage(_canvas as web.CanvasImageSource, 0, 0);

      // Create ImageBitmap from the 2D offscreen canvas (CPU-backed).
      // Unlike captureStream-sourced ImageBitmaps, these work correctly
      // with CanvasKit's createImageFromImageBitmap.
      final imageBitmap = await web.window
          .createImageBitmap(_offscreen! as web.ImageBitmapSource)
          .toDart;

      ui.Image newFrame;
      try {
        newFrame = await ui_web.createImageFromImageBitmap(
          imageBitmap as JSAny,
        );
      } catch (_) {
        imageBitmap.close();
        rethrow;
      }

      final oldFrame = _currentFrame;
      _currentFrame = newFrame;
      _hasNewFrame = true;
      _frameNumber++;

      if (_frameNumber == 1) {
        _log.info('First canvas frame captured: ${w}x$h');
      }

      // Defer old frame disposal so CanvasKit can finish rendering it.
      if (oldFrame != null) {
        Future.microtask(() => oldFrame.dispose());
      }
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
