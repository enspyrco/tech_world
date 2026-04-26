// Web implementation for video frame capture using MediaStreamTrackProcessor.
//
// Uses the WebCodecs API to capture frames directly from a MediaStreamTrack
// without needing an HTMLVideoElement. This avoids DOM element lifecycle issues.
//
// Browser support: Chrome (main thread), Safari 18+/Firefox (worker only - not supported here)
//
// This file should only be imported on web platforms.
//
// IMPORTANT: Remote WebRTC tracks start in a muted state and don't produce frames
// until RTP packets arrive. Use createAsync() which waits for the track to unmute.

import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' as ui;

import 'package:logging/logging.dart';
import 'package:web/web.dart' as web;

import 'frame_source.dart';

final _log = Logger('VideoFrameWebV2');

/// JS interop for MediaStreamTrackProcessor (not yet in package:web)
@JS('MediaStreamTrackProcessor')
external JSFunction? get _mediaStreamTrackProcessorConstructor;

@JS()
@staticInterop
class MediaStreamTrackProcessor {
  external factory MediaStreamTrackProcessor(MediaStreamTrackProcessorInit init);
}

@JS()
@staticInterop
@anonymous
class MediaStreamTrackProcessorInit {
  external factory MediaStreamTrackProcessorInit({required web.MediaStreamTrack track});
}

extension MediaStreamTrackProcessorExtension on MediaStreamTrackProcessor {
  external web.ReadableStream get readable;
}

/// JS interop for VideoFrame
@JS()
@staticInterop
class VideoFrame {}

extension VideoFrameExtension on VideoFrame {
  external int get displayWidth;
  external int get displayHeight;
  external void close();
}

/// Check if MediaStreamTrackProcessor is available (Chrome main thread)
bool get isMediaStreamTrackProcessorSupported {
  return _mediaStreamTrackProcessorConstructor != null;
}

/// Web-based video frame capture using MediaStreamTrackProcessor.
///
/// Captures frames directly from a MediaStreamTrack without creating
/// any DOM elements. This avoids the ownership/lifecycle issues with
/// HTMLVideoElement-based approaches.
///
/// IMPORTANT: Remote WebRTC tracks start muted and don't produce frames until
/// RTP packets arrive. Use [createAsync] which waits for the track to unmute.
class DirectTrackCapture {
  DirectTrackCapture._(this._processor);

  final MediaStreamTrackProcessor _processor;
  web.ReadableStreamDefaultReader? _reader;
  ui.Image? _currentFrame;
  bool _hasNewFrame = false;
  bool _isCapturing = false;
  int _frameNumber = 0;
  int _width = 0;
  int _height = 0;
  Timer? _captureTimer;
  bool _frameInFlight = false;
  web.HTMLCanvasElement? _readbackCanvas;
  web.CanvasRenderingContext2D? _readbackCtx;

  /// Completer for pending unmute wait (used to cancel if disposed early)
  static Completer<bool>? _pendingUnmute;

  /// Check if a MediaStreamTrack is currently muted.
  ///
  /// Remote WebRTC tracks start muted until RTP packets arrive.
  static bool _isTrackMuted(web.MediaStreamTrack track) {
    try {
      // Access the 'muted' property via dynamic cast
      final muted = (track as dynamic).muted as bool?;
      return muted ?? false;
    } catch (e) {
      _log.warning('DirectTrackCapture: Could not check muted state: $e', e);
      return false;
    }
  }

  /// Wait for the track to unmute, with timeout.
  ///
  /// Returns true if the track unmuted, false if timed out or cancelled.
  static Future<bool> _waitForUnmute(
    web.MediaStreamTrack track,
    Duration timeout,
  ) async {
    // First check if already unmuted (race condition handling)
    if (!_isTrackMuted(track)) {
      _log.fine('DirectTrackCapture: Track already unmuted');
      return true;
    }

    final completer = Completer<bool>();
    _pendingUnmute = completer;

    // Set up timeout
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _log.warning('DirectTrackCapture: Timeout waiting for unmute');
        completer.complete(false);
      }
    });

    // Listen for 'unmute' event using JS interop
    void onUnmute(web.Event event) {
      if (!completer.isCompleted) {
        _log.info('DirectTrackCapture: Track unmuted!');
        completer.complete(true);
      }
    }

    // Add event listener for 'unmute'
    final jsCallback = onUnmute.toJS;
    track.addEventListener('unmute', jsCallback);

    // Also poll periodically in case we miss the event
    Timer.periodic(const Duration(milliseconds: 100), (pollTimer) {
      if (completer.isCompleted) {
        pollTimer.cancel();
        return;
      }
      if (!_isTrackMuted(track)) {
        _log.info('DirectTrackCapture: Track unmuted (detected via polling)');
        if (!completer.isCompleted) {
          completer.complete(true);
        }
        pollTimer.cancel();
      }
    });

    try {
      final result = await completer.future;
      return result;
    } finally {
      timer.cancel();
      track.removeEventListener('unmute', jsCallback);
      _pendingUnmute = null;
    }
  }

  /// Cancel any pending unmute wait.
  ///
  /// Call this if the component is disposed while waiting for unmute.
  static void cancelPendingUnmute() {
    if (_pendingUnmute != null && !_pendingUnmute!.isCompleted) {
      _log.fine('DirectTrackCapture: Cancelling pending unmute wait');
      _pendingUnmute!.complete(false);
    }
  }

  /// Create a capture instance from a MediaStreamTrack (synchronous).
  ///
  /// WARNING: This may fail for remote tracks that are still muted.
  /// Prefer [createAsync] for remote tracks.
  ///
  /// Returns null if MediaStreamTrackProcessor is not supported.
  static DirectTrackCapture? create(web.MediaStreamTrack track) {
    if (!isMediaStreamTrackProcessorSupported) {
      _log.warning('DirectTrackCapture: MediaStreamTrackProcessor not supported');
      return null;
    }

    try {
      final processor = MediaStreamTrackProcessor(
        MediaStreamTrackProcessorInit(track: track),
      );
      _log.info('DirectTrackCapture: Created processor for track ${track.id}');
      return DirectTrackCapture._(processor);
    } catch (e) {
      _log.severe('DirectTrackCapture: Failed to create processor: $e', e);
      return null;
    }
  }

  /// Create a capture instance, waiting for the track to unmute if needed.
  ///
  /// This is the preferred method for remote tracks which start muted.
  ///
  /// Returns null if:
  /// - MediaStreamTrackProcessor is not supported
  /// - Track failed to unmute within timeout
  /// - Creation was cancelled via [cancelPendingUnmute]
  static Future<DirectTrackCapture?> createAsync(
    web.MediaStreamTrack track, {
    Duration timeout = const Duration(seconds: 5),
    Duration initialDelay = const Duration(milliseconds: 500),
  }) async {
    if (!isMediaStreamTrackProcessorSupported) {
      _log.warning('DirectTrackCapture: MediaStreamTrackProcessor not supported');
      return null;
    }

    // Check if track is muted (common for remote tracks)
    if (_isTrackMuted(track)) {
      _log.info('DirectTrackCapture: Track muted, waiting for unmute...');
      final unmuted = await _waitForUnmute(track, timeout);
      if (!unmuted) {
        _log.warning('DirectTrackCapture: Failed to unmute within timeout');
        return null;
      }
      _log.info('DirectTrackCapture: Track unmuted, proceeding with capture');
    } else {
      // Even if not muted, remote tracks may need time for decoder to produce frames
      // Add a small delay to let the video decoder start producing frames
      _log.fine('DirectTrackCapture: Track not muted, waiting ${initialDelay.inMilliseconds}ms for decoder...');
      await Future.delayed(initialDelay);
    }

    // Now create the processor (track should have frames)
    return create(track);
  }

  /// Whether a new frame is available.
  bool get hasNewFrame => _hasNewFrame;

  /// Whether capture is active.
  bool get isActive => _isCapturing;

  /// The current captured frame, or null if no frame available.
  ui.Image? get currentFrame => _currentFrame;

  /// Video width in pixels.
  int get width => _width;

  /// Video height in pixels.
  int get height => _height;

  /// Current frame number.
  int get frameNumber => _frameNumber;

  /// Start capturing frames.
  void startCapture() {
    if (_isCapturing) return;
    _isCapturing = true;

    // Get a reader for the frame stream
    _reader = _processor.readable.getReader() as web.ReadableStreamDefaultReader;

    // Use timer to control frame rate (~15fps)
    // This prevents overwhelming the system with frame reads
    _captureTimer = Timer.periodic(
      const Duration(milliseconds: 66),
      (_) => _captureFrame(),
    );

    _log.info('DirectTrackCapture: Started capture');
  }

  /// Stop capturing frames.
  void stopCapture() {
    _isCapturing = false;
    _captureTimer?.cancel();
    _captureTimer = null;

    // Cancel the reader to release the stream
    try {
      _reader?.cancel().toDart.ignore();
    } catch (e) {
      _log.warning('DirectTrackCapture: Error in stopCapture: $e', e);
    }
    _reader = null;

    _log.info('DirectTrackCapture: Stopped capture');
  }

  /// Capture the next available video frame.
  Future<void> _captureFrame() async {
    if (!_isCapturing || _reader == null) return;
    if (_frameInFlight) return; // Don't queue up multiple reads

    _frameInFlight = true;

    try {
      // Read the next frame from the stream
      final result = await _reader!.read().toDart;

      if (result.done) {
        _log.info('DirectTrackCapture: Stream ended');
        _isCapturing = false;
        _frameInFlight = false;
        return;
      }

      final videoFrame = result.value as VideoFrame?;
      if (videoFrame == null) {
        _frameInFlight = false;
        return;
      }

      // Update dimensions
      _width = videoFrame.displayWidth;
      _height = videoFrame.displayHeight;

      if (_width == 0 || _height == 0) {
        videoFrame.close();
        _frameInFlight = false;
        return;
      }

      // Draw VideoFrame directly to offscreen canvas, read pixels, decode.
      // Mirrors canvas_capture_web.dart — no ImageBitmap, no createImageFromImageBitmap.
      if (_readbackCanvas == null ||
          _readbackCanvas!.width != _width ||
          _readbackCanvas!.height != _height) {
        _readbackCanvas =
            web.document.createElement('canvas') as web.HTMLCanvasElement;
        _readbackCanvas!.width = _width;
        _readbackCanvas!.height = _height;
        _readbackCtx = _readbackCanvas!.getContext('2d')!
            as web.CanvasRenderingContext2D;
      }

      _readbackCtx!.drawImage(videoFrame as web.CanvasImageSource, 0, 0);
      // Close VideoFrame immediately to release video decoder resources.
      videoFrame.close();

      if (!_isCapturing) return;

      final imageData =
          _readbackCtx!.getImageData(0, 0, _width, _height);
      final clamped = imageData.data.toDart;
      final rgbaBytes = clamped.buffer.asUint8List(
        clamped.offsetInBytes,
        clamped.lengthInBytes,
      );

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgbaBytes,
        _width,
        _height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final newFrame = await completer.future;

      // Swap frames
      final oldFrame = _currentFrame;
      _currentFrame = newFrame;
      _hasNewFrame = true;
      _frameNumber++;

      if (_frameNumber == 1) {
        _log.info(
            'DirectTrackCapture: First frame captured! ${_width}x$_height');
      }

      oldFrame?.dispose();
    } catch (e, stackTrace) {
      _log.warning('DirectTrackCapture: Frame capture error: $e', e, stackTrace);
    } finally {
      _frameInFlight = false;
    }
  }

  /// Mark the current frame as consumed.
  void markConsumed() {
    _hasNewFrame = false;
  }

  /// Get the current frame and transfer ownership to caller.
  ///
  /// Returns the current frame and clears the internal reference.
  /// The caller is now responsible for disposing the returned image.
  /// Returns null if no frame is available.
  ui.Image? consumeFrame() {
    _hasNewFrame = false;
    final frame = _currentFrame;
    _currentFrame = null;
    return frame;
  }

  /// Dispose resources.
  void dispose() {
    stopCapture();
    _currentFrame?.dispose();
    _currentFrame = null;
    _log.info('DirectTrackCapture: Disposed');
  }
}

/// Video frame capture using HTMLVideoElement.
///
/// This is more reliable for remote WebRTC tracks because the video element
/// handles all the buffering, decoding, and frame timing internally.
/// It waits for the video to be ready before capturing frames.
///
/// Use this for remote tracks where MediaStreamTrackProcessor doesn't work reliably.
class VideoElementCapture implements FrameSource {
  VideoElementCapture._(this._videoElement, this._stream, {this.ownsElement = true});

  final web.HTMLVideoElement _videoElement;
  final web.MediaStream _stream;
  final bool ownsElement;
  ui.Image? _currentFrame;
  bool _hasNewFrame = false;
  bool _isCapturing = false;
  int _frameNumber = 0;
  int _width = 0;
  int _height = 0;
  Timer? _captureTimer;
  bool _frameInFlight = false;
  bool _videoReady = false;
  // Offscreen canvas for pixel readback (not in DOM).
  web.HTMLCanvasElement? _readbackCanvas;
  web.CanvasRenderingContext2D? _readbackCtx;
  JSFunction? _jsLoadedMetadata;

  /// Create a capture instance from a MediaStream (preferred) or MediaStreamTrack.
  ///
  /// If jsStream is provided, uses it directly. Otherwise falls back to creating
  /// a MediaStream from the track.
  static Future<VideoElementCapture?> createFromStream(dynamic jsStream, dynamic jsTrack) async {
    try {
      web.MediaStream? stream;

      // Try to use the provided stream first
      if (jsStream != null) {
        try {
          stream = jsStream as web.MediaStream;
          _log.fine('VideoElementCapture: Using provided MediaStream');
        } catch (e) {
          _log.warning('VideoElementCapture: jsStream cast failed: $e', e);
        }
      }

      // Fall back to creating a stream from the track
      if (stream == null && jsTrack != null) {
        final track = jsTrack as web.MediaStreamTrack;
        stream = web.MediaStream();
        stream.addTrack(track);
        _log.fine('VideoElementCapture: Created MediaStream from track (readyState=${track.readyState})');
      }

      if (stream == null) {
        _log.warning('VideoElementCapture: No stream or track available');
        return null;
      }

      // Log stream info
      final videoTracks = stream.getVideoTracks();
      _log.fine('VideoElementCapture: Stream has ${videoTracks.length} video tracks');
      if (videoTracks.length > 0) {
        final t = videoTracks.toDart[0];
        _log.fine('VideoElementCapture: Track readyState=${t.readyState}, enabled=${t.enabled}');
      }

      // Create video element
      final video = web.document.createElement('video') as web.HTMLVideoElement;
      video.autoplay = true;
      video.muted = true;
      video.playsInline = true;
      // Use off-screen positioning instead of display:none
      // Mobile browsers may not decode frames for hidden elements
      video.style.position = 'fixed';
      video.style.top = '-9999px';
      video.style.left = '-9999px';
      video.style.width = '1px';
      video.style.height = '1px';
      video.srcObject = stream;

      // Add to document body (required for some browsers to properly load video)
      web.document.body?.appendChild(video);

      // Start playback and wait for video to be ready
      try {
        await video.play().toDart;
        _log.fine('VideoElementCapture: play() succeeded');
      } catch (e) {
        _log.warning('VideoElementCapture: play() failed: $e', e);
      }

      // Wait for video dimensions to be available
      var attempts = 0;
      while (video.videoWidth == 0 && attempts < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (video.videoWidth > 0) {
        _log.info('VideoElementCapture: Video ready ${video.videoWidth}x${video.videoHeight} after $attempts attempts');
      } else {
        _log.warning('VideoElementCapture: Video dimensions not available after $attempts attempts');
      }

      return VideoElementCapture._(video, stream, ownsElement: true);
    } catch (e) {
      _log.severe('VideoElementCapture: createFromStream failed: $e', e);
      return null;
    }
  }

  /// Create a capture instance from a MediaStreamTrack.
  ///
  /// First tries to find an existing video element (created by flutter_webrtc),
  /// falls back to creating a new one if not found.
  static VideoElementCapture? create(web.MediaStreamTrack track) {
    try {
      // First, try to find an existing video element with this track
      final existingVideo = _findExistingVideoElement(track.id);
      if (existingVideo != null) {
        _log.fine('VideoElementCapture: Found existing video element for track ${track.id}');
        // Create a dummy stream (we don't own the element)
        final stream = web.MediaStream();
        return VideoElementCapture._(existingVideo, stream, ownsElement: false);
      }

      // No existing element found - create our own
      _log.fine('VideoElementCapture: Creating new video element for track ${track.id}');

      // Create a MediaStream with just this track
      final stream = web.MediaStream();
      stream.addTrack(track);

      // Create an offscreen video element
      final video = web.document.createElement('video') as web.HTMLVideoElement;
      video.autoplay = true;
      video.muted = true; // Mute to allow autoplay
      video.playsInline = true;

      // Set srcObject to our stream
      video.srcObject = stream;

      return VideoElementCapture._(video, stream, ownsElement: true);
    } catch (e) {
      _log.severe('VideoElementCapture: Failed to create: $e', e);
      return null;
    }
  }

  /// Find an existing video element that has a track with the given ID.
  static web.HTMLVideoElement? _findExistingVideoElement(String trackId) {
    final videos = web.document.querySelectorAll('video');
    _log.finer('VideoElementCapture: Searching ${videos.length} video elements for track $trackId');

    for (var i = 0; i < videos.length; i++) {
      final node = videos.item(i);
      if (node == null) continue;

      final video = node as web.HTMLVideoElement;
      final srcObject = video.srcObject;
      if (srcObject == null) continue;

      // Check if srcObject is a MediaStream
      if (srcObject.isA<web.MediaStream>()) {
        final stream = srcObject as web.MediaStream;
        final tracks = stream.getVideoTracks();

        for (var j = 0; j < tracks.length; j++) {
          final t = tracks.toDart[j];
          // Match by ID or by label (LiveKit puts its track ID in the label)
          if (t.id == trackId || t.label == trackId) {
            _log.fine('VideoElementCapture: Found match in video[$i] - ${video.videoWidth}x${video.videoHeight}');
            return video;
          }
        }
      }
    }

    _log.finer('VideoElementCapture: No existing video element found for track $trackId');
    return null;
  }

  /// Create a capture instance from an existing HTMLVideoElement.
  ///
  /// This is used when we have direct access to a video element (e.g., from RTCVideoRenderer).
  static VideoElementCapture? createFromVideoElement(dynamic videoElement) {
    try {
      final video = videoElement as web.HTMLVideoElement;
      final width = video.videoWidth;
      final height = video.videoHeight;

      _log.fine('VideoElementCapture: createFromVideoElement ${width}x$height, readyState=${video.readyState}');

      // Get the stream from the video element
      final srcObject = video.srcObject;
      web.MediaStream stream;

      if (srcObject != null && srcObject.isA<web.MediaStream>()) {
        stream = srcObject as web.MediaStream;
      } else {
        // Create a dummy stream if no srcObject
        stream = web.MediaStream();
        _log.fine('VideoElementCapture: No srcObject on video, using empty stream');
      }

      return VideoElementCapture._(video, stream, ownsElement: false);
    } catch (e) {
      _log.severe('VideoElementCapture: createFromVideoElement failed: $e', e);
      return null;
    }
  }

  /// Find any video element with a live video track and capture from it.
  ///
  /// This is used after RTCVideoRenderer creates a video element.
  static VideoElementCapture? findAndCapture() {
    final videos = web.document.querySelectorAll('video');
    _log.finer('VideoElementCapture: Searching ${videos.length} video elements for live track');

    for (var i = 0; i < videos.length; i++) {
      final node = videos.item(i);
      if (node == null) continue;

      final video = node as web.HTMLVideoElement;
      final width = video.videoWidth;
      final height = video.videoHeight;

      _log.finer('VideoElementCapture: Video[$i] size=${width}x$height, readyState=${video.readyState}');

      // Skip videos with no real dimensions
      if (width < 10 || height < 10) continue;

      final srcObject = video.srcObject;
      if (srcObject == null) continue;

      if (srcObject.isA<web.MediaStream>()) {
        final stream = srcObject as web.MediaStream;
        final tracks = stream.getVideoTracks();

        _log.finer('VideoElementCapture: Video[$i] has ${tracks.length} video tracks');

        for (var j = 0; j < tracks.length; j++) {
          final t = tracks.toDart[j];
          _log.finer('VideoElementCapture: Track[$j] readyState=${t.readyState}, enabled=${t.enabled}');

          // Look for a live track
          if (t.readyState == 'live' && t.enabled) {
            _log.fine('VideoElementCapture: Found live track in video[$i]!');
            return VideoElementCapture._(video, stream, ownsElement: false);
          }
        }
      }
    }

    _log.fine('VideoElementCapture: No video element with live track found');
    return null;
  }

  @override
  bool get hasNewFrame => _hasNewFrame;

  /// Whether capture is active.
  bool get isActive => _isCapturing;

  /// The current captured frame, or null if no frame available.
  ui.Image? get currentFrame => _currentFrame;

  /// Video width in pixels.
  int get width => _width;

  /// Video height in pixels.
  int get height => _height;

  /// Current frame number.
  int get frameNumber => _frameNumber;

  /// Start capturing frames.
  void startCapture() {
    if (_isCapturing) return;
    _isCapturing = true;

    // Listen for when video has proper dimensions.
    // Store the JS callback so we can remove it on stop/dispose.
    void onLoadedMetadata(web.Event e) {
      final w = _videoElement.videoWidth;
      final h = _videoElement.videoHeight;
      _log.fine('VideoElementCapture: Metadata loaded ${w}x$h');
    }
    _jsLoadedMetadata = onLoadedMetadata.toJS;
    _videoElement.addEventListener('loadedmetadata', _jsLoadedMetadata!);

    // Start playback only if we own the element (existing elements are already playing)
    if (ownsElement) {
      _videoElement.play().toDart.catchError((e) {
        _log.warning('VideoElementCapture: Play failed: $e');
        return null;
      });
    }

    // Use timer to control frame rate (~15fps)
    _captureTimer = Timer.periodic(
      const Duration(milliseconds: 66),
      (_) => _captureFrame(),
    );

    _log.info('VideoElementCapture: Started capture (ownsElement=$ownsElement)');
  }

  /// Stop capturing frames.
  void stopCapture() {
    _isCapturing = false;
    _captureTimer?.cancel();
    _captureTimer = null;
    if (_jsLoadedMetadata != null) {
      _videoElement.removeEventListener('loadedmetadata', _jsLoadedMetadata!);
      _jsLoadedMetadata = null;
    }
    _log.info('VideoElementCapture: Stopped capture');
  }

  /// Capture a frame from the video element.
  Future<void> _captureFrame() async {
    if (!_isCapturing) return;
    if (_frameInFlight) return;

    // Check if video has any dimensions
    final videoWidth = _videoElement.videoWidth;
    final videoHeight = _videoElement.videoHeight;

    if (videoWidth == 0 || videoHeight == 0) {
      // Video not ready yet
      return;
    }

    if (!_videoReady) {
      _videoReady = true;
      _log.info('VideoElementCapture: Video ready ${videoWidth}x$videoHeight');
      // Log track state for debugging
      final tracks = _stream.getVideoTracks();
      _log.fine('VideoElementCapture: Stream has ${tracks.length} video tracks');
      if (tracks.length > 0) {
        final track = tracks.toDart[0];
        _log.fine('VideoElementCapture: Track enabled=${track.enabled}, readyState=${track.readyState}, muted=${(track as dynamic).muted}');
      }
    }

    _frameInFlight = true;

    try {
      _width = videoWidth;
      _height = videoHeight;

      // Create ImageBitmap from video (this works — original code did it).
      // Then draw bitmap to canvas for pixel readback. We can't draw
      // HTMLVideoElement directly because the CanvasImageSource cast
      // may fail at runtime in package:web.
      final imageBitmap = await web.window
          .createImageBitmap(_videoElement as web.ImageBitmapSource)
          .toDart;

      if (_readbackCanvas == null ||
          _readbackCanvas!.width != _width ||
          _readbackCanvas!.height != _height) {
        _readbackCanvas =
            web.document.createElement('canvas') as web.HTMLCanvasElement;
        _readbackCanvas!.width = _width;
        _readbackCanvas!.height = _height;
        _readbackCtx = _readbackCanvas!.getContext('2d')!
            as web.CanvasRenderingContext2D;
      }

      _readbackCtx!.drawImage(imageBitmap as web.CanvasImageSource, 0, 0);
      imageBitmap.close();

      final imageData =
          _readbackCtx!.getImageData(0, 0, _width, _height);
      final clamped = imageData.data.toDart;
      final rgbaBytes = clamped.buffer.asUint8List(
        clamped.offsetInBytes,
        clamped.lengthInBytes,
      );

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgbaBytes,
        _width,
        _height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final newFrame = await completer.future;

      // Swap frames
      final oldFrame = _currentFrame;
      _currentFrame = newFrame;
      _hasNewFrame = true;
      _frameNumber++;

      if (_frameNumber == 1) {
        _log.info(
            'VideoElementCapture: First frame captured! ${_width}x$_height');
      }

      oldFrame?.dispose();
    } catch (e) {
      _log.warning('VideoElementCapture: Frame capture error: $e', e);
    } finally {
      _frameInFlight = false;
    }
  }

  /// Mark the current frame as consumed.
  void markConsumed() {
    _hasNewFrame = false;
  }

  @override
  ui.Image? consumeFrame() {
    _hasNewFrame = false;
    final frame = _currentFrame;
    _currentFrame = null;
    return frame;
  }

  /// Dispose resources.
  void dispose() {
    stopCapture();
    _currentFrame?.dispose();
    _currentFrame = null;

    // Only clean up video element if we created it
    if (ownsElement) {
      try {
        _videoElement.srcObject = null;
        // Remove from DOM if we added it
        _videoElement.remove();
        // DON'T call track.stop() - the track is owned by LiveKit
        // Stopping it would permanently end the track for everyone
      } catch (e) {
        _log.warning('VideoElementCapture: Error disposing: $e', e);
      }
    }

    _log.info('VideoElementCapture: Disposed (ownsElement=$ownsElement)');
  }
}
