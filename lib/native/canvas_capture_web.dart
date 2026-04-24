/// Captures frames from an HTMLCanvasElement via MediaStreamTrackProcessor.
///
/// Designed for capturing Three.js render output from a same-origin iframe.
/// Uses the same frame interface as [VideoElementCapture] so it plugs directly
/// into [VideoBubbleComponent]'s existing frame consumption loop.
///
/// Capture pipeline: canvas.captureStream() → MediaStreamTrackProcessor →
/// VideoFrame → createImageBitmap → createImageFromImageBitmap → ui.Image.
///
/// This reuses the exact same VideoFrame→ImageBitmap→ui.Image path that works
/// for remote participant video via DirectTrackCapture.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:logging/logging.dart';
import 'package:web/web.dart' as web;

// Reuse JS interop types from video_frame_web_v2.dart
import 'package:tech_world/native/video_frame_web_v2.dart'
    show MediaStreamTrackProcessor, MediaStreamTrackProcessorInit,
         MediaStreamTrackProcessorExtension, VideoFrame, VideoFrameExtension;

final _log = Logger('CanvasCapture');

class CanvasCapture {
  CanvasCapture._(this._canvas, {int fps = 15, this.onBeforeCapture})
      : _captureInterval = Duration(milliseconds: (1000 / fps).round()),
        _fps = fps;

  final web.HTMLCanvasElement _canvas;
  final Duration _captureInterval;
  final int _fps;

  /// Optional callback invoked before each frame capture.
  final void Function()? onBeforeCapture;

  ui.Image? _currentFrame;
  bool _hasNewFrame = false;
  bool _isCapturing = false;
  bool _frameInFlight = false;
  int _frameNumber = 0;
  Timer? _captureTimer;

  MediaStreamTrackProcessor? _processor;
  web.ReadableStreamDefaultReader? _reader;

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

    // Create a MediaStream from the canvas, extract the video track,
    // and pipe it through MediaStreamTrackProcessor to get VideoFrames.
    final stream = _canvas.captureStream(_fps);
    final tracks = stream.getVideoTracks();
    if (tracks.length == 0) {
      _log.severe('captureStream returned no video tracks');
      return;
    }
    final track = tracks.toDart.first;

    _processor = MediaStreamTrackProcessor(
      MediaStreamTrackProcessorInit(track: track),
    );
    _reader =
        _processor!.readable.getReader() as web.ReadableStreamDefaultReader;

    _captureTimer = Timer.periodic(_captureInterval, (_) => _captureFrame());
    _log.info(
      'Started canvas capture via MediaStreamTrackProcessor '
      'at ${_captureInterval.inMilliseconds}ms interval',
    );
  }

  void stopCapture() {
    _isCapturing = false;
    _captureTimer?.cancel();
    _captureTimer = null;

    try {
      _reader?.cancel().toDart.ignore();
    } catch (e) {
      _log.warning('Error cancelling reader: $e');
    }
    _reader = null;
    _processor = null;

    _log.info('Stopped canvas capture');
  }

  Future<void> _captureFrame() async {
    if (!_isCapturing || _reader == null) return;
    if (_frameInFlight) return;

    _frameInFlight = true;

    try {
      // Force a render if the canvas doesn't preserve its drawing buffer.
      onBeforeCapture?.call();

      // Read the next VideoFrame from the processor stream.
      final result = await _reader!.read().toDart;
      if (result.done) {
        _log.info('Capture stream ended');
        _isCapturing = false;
        _frameInFlight = false;
        return;
      }

      final videoFrame = result.value as VideoFrame?;
      if (videoFrame == null) {
        _frameInFlight = false;
        return;
      }

      final vw = videoFrame.displayWidth;
      final vh = videoFrame.displayHeight;
      if (vw == 0 || vh == 0) {
        videoFrame.close();
        _frameInFlight = false;
        return;
      }

      // VideoFrame → ImageBitmap → ui.Image
      // Same proven path as DirectTrackCapture for remote participants.
      final imageBitmap = await web.window
          .createImageBitmap(videoFrame as web.ImageBitmapSource)
          .toDart;

      // Close VideoFrame immediately to release decoder resources.
      videoFrame.close();

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
