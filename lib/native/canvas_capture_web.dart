/// Captures frames from an HTMLCanvasElement via captureStream + video element.
///
/// Designed for capturing Three.js render output from a same-origin iframe.
/// Uses the same frame interface as [VideoElementCapture] so it plugs directly
/// into [VideoBubbleComponent]'s existing frame consumption loop.
///
/// Capture pipeline: canvas.captureStream() → MediaStream → <video> element →
/// createImageBitmap(video) → createImageFromImageBitmap → ui.Image.
///
/// This approach reuses the same video-element-to-texture path that already
/// works for every remote participant's video feed, avoiding the various
/// getImageData / decodeImageFromPixels / createImageFromImageBitmap(canvas)
/// paths that produce black frames in CanvasKit.
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
      : _captureInterval = Duration(milliseconds: (1000 / fps).round()),
        _fps = fps;

  final web.HTMLCanvasElement _canvas;
  final Duration _captureInterval;
  final int _fps;

  /// Optional callback invoked before each frame capture.
  /// Used to force a render when the canvas uses preserveDrawingBuffer: false.
  final void Function()? onBeforeCapture;

  ui.Image? _currentFrame;
  bool _hasNewFrame = false;
  bool _isCapturing = false;
  bool _frameInFlight = false;
  int _frameNumber = 0;
  Timer? _captureTimer;

  // Video element driven by the canvas's captureStream.
  web.HTMLVideoElement? _video;

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

    // Create a MediaStream from the canvas and pipe it into a <video> element.
    // This gives us a standard video source that CanvasKit can capture from
    // using the same createImageBitmap(video) path as remote participants.
    _video = web.document.createElement('video') as web.HTMLVideoElement;
    _video!.style.display = 'none';
    _video!.autoplay = true;
    _video!.muted = true;
    // playsInline needed for iOS/Safari autoplay.
    _video!.setAttribute('playsinline', '');
    web.document.body?.appendChild(_video!);

    final stream = _canvas.captureStream(_fps);
    _video!.srcObject = stream as web.MediaProvider;

    _captureTimer = Timer.periodic(_captureInterval, (_) => _captureFrame());
    _log.info(
        'Started canvas capture via captureStream at ${_captureInterval.inMilliseconds}ms interval');
  }

  void stopCapture() {
    _isCapturing = false;
    _captureTimer?.cancel();
    _captureTimer = null;

    _video?.srcObject = null;
    _video?.remove();
    _video = null;

    _log.info('Stopped canvas capture');
  }

  Future<void> _captureFrame() async {
    if (!_isCapturing || _frameInFlight || _video == null) return;

    // Wait until the video has enough data to render a frame.
    if (_video!.readyState < 2) return; // HAVE_CURRENT_DATA

    final vw = _video!.videoWidth;
    final vh = _video!.videoHeight;
    if (vw == 0 || vh == 0) return;

    _frameInFlight = true;

    try {
      // Force a render if the canvas doesn't preserve its drawing buffer.
      onBeforeCapture?.call();

      // Capture from the <video> element — same path as remote participants.
      final imageBitmap = await web.window
          .createImageBitmap(_video! as web.ImageBitmapSource)
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
        _log.info('First canvas frame captured: ${vw}x$vh');
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
