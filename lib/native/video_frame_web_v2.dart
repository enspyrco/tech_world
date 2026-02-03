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
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;

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
      debugPrint('DirectTrackCapture: Could not check muted state: $e');
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
      debugPrint('DirectTrackCapture: Track already unmuted');
      return true;
    }

    final completer = Completer<bool>();
    _pendingUnmute = completer;

    // Set up timeout
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        debugPrint('DirectTrackCapture: Timeout waiting for unmute');
        completer.complete(false);
      }
    });

    // Listen for 'unmute' event using JS interop
    void onUnmute(web.Event event) {
      if (!completer.isCompleted) {
        debugPrint('DirectTrackCapture: Track unmuted!');
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
        debugPrint('DirectTrackCapture: Track unmuted (detected via polling)');
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
      debugPrint('DirectTrackCapture: Cancelling pending unmute wait');
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
      debugPrint('DirectTrackCapture: MediaStreamTrackProcessor not supported');
      return null;
    }

    try {
      final processor = MediaStreamTrackProcessor(
        MediaStreamTrackProcessorInit(track: track),
      );
      debugPrint('DirectTrackCapture: Created processor for track ${track.id}');
      return DirectTrackCapture._(processor);
    } catch (e) {
      debugPrint('DirectTrackCapture: Failed to create processor: $e');
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
      debugPrint('DirectTrackCapture: MediaStreamTrackProcessor not supported');
      return null;
    }

    // Check if track is muted (common for remote tracks)
    if (_isTrackMuted(track)) {
      debugPrint('DirectTrackCapture: Track muted, waiting for unmute...');
      final unmuted = await _waitForUnmute(track, timeout);
      if (!unmuted) {
        debugPrint('DirectTrackCapture: Failed to unmute within timeout');
        return null;
      }
      debugPrint('DirectTrackCapture: Track unmuted, proceeding with capture');
    } else {
      // Even if not muted, remote tracks may need time for decoder to produce frames
      // Add a small delay to let the video decoder start producing frames
      debugPrint('DirectTrackCapture: Track not muted, waiting ${initialDelay.inMilliseconds}ms for decoder...');
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

    debugPrint('DirectTrackCapture: Started capture');
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
      debugPrint('DirectTrackCapture: Error in stopCapture: $e');
    }
    _reader = null;

    debugPrint('DirectTrackCapture: Stopped capture');
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
        debugPrint('DirectTrackCapture: Stream ended');
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

      // Convert VideoFrame to ImageBitmap, then to ui.Image
      // VideoFrame is an ImageBitmapSource
      final imageBitmapPromise = web.window.createImageBitmap(
        videoFrame as web.ImageBitmapSource,
      );

      final imageBitmap = await imageBitmapPromise.toDart;

      // IMPORTANT: Close the VideoFrame immediately after creating ImageBitmap
      // to release the underlying video decoder resources
      videoFrame.close();

      // Convert to Flutter ui.Image
      final newFrame = await ui_web.createImageFromImageBitmap(
        imageBitmap as JSAny,
      );

      // Swap frames
      final oldFrame = _currentFrame;
      _currentFrame = newFrame;
      _hasNewFrame = true;
      _frameNumber++;

      if (_frameNumber == 1) {
        debugPrint(
            'DirectTrackCapture: First frame captured! ${_width}x$_height');
      }

      oldFrame?.dispose();
    } catch (e, stackTrace) {
      debugPrint('DirectTrackCapture: Frame capture error: $e');
      debugPrint('DirectTrackCapture: Stack: $stackTrace');
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
    debugPrint('DirectTrackCapture: Disposed');
  }
}

/// Video frame capture using HTMLVideoElement.
///
/// This is more reliable for remote WebRTC tracks because the video element
/// handles all the buffering, decoding, and frame timing internally.
/// It waits for the video to be ready before capturing frames.
///
/// Use this for remote tracks where MediaStreamTrackProcessor doesn't work reliably.
class VideoElementCapture {
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
          debugPrint('VideoElementCapture: Using provided MediaStream');
        } catch (e) {
          debugPrint('VideoElementCapture: jsStream cast failed: $e');
        }
      }

      // Fall back to creating a stream from the track
      if (stream == null && jsTrack != null) {
        final track = jsTrack as web.MediaStreamTrack;
        stream = web.MediaStream();
        stream.addTrack(track);
        debugPrint('VideoElementCapture: Created MediaStream from track (readyState=${track.readyState})');
      }

      if (stream == null) {
        debugPrint('VideoElementCapture: No stream or track available');
        return null;
      }

      // Log stream info
      final videoTracks = stream.getVideoTracks();
      debugPrint('VideoElementCapture: Stream has ${videoTracks.length} video tracks');
      if (videoTracks.length > 0) {
        final t = videoTracks.toDart[0];
        debugPrint('VideoElementCapture: Track readyState=${t.readyState}, enabled=${t.enabled}');
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
        debugPrint('VideoElementCapture: play() succeeded');
      } catch (e) {
        debugPrint('VideoElementCapture: play() failed: $e');
      }

      // Wait for video dimensions to be available
      var attempts = 0;
      while (video.videoWidth == 0 && attempts < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (video.videoWidth > 0) {
        debugPrint('VideoElementCapture: Video ready ${video.videoWidth}x${video.videoHeight} after $attempts attempts');
      } else {
        debugPrint('VideoElementCapture: Video dimensions not available after $attempts attempts');
      }

      return VideoElementCapture._(video, stream, ownsElement: true);
    } catch (e) {
      debugPrint('VideoElementCapture: createFromStream failed: $e');
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
        debugPrint('VideoElementCapture: Found existing video element for track ${track.id}');
        // Create a dummy stream (we don't own the element)
        final stream = web.MediaStream();
        return VideoElementCapture._(existingVideo, stream, ownsElement: false);
      }

      // No existing element found - create our own
      debugPrint('VideoElementCapture: Creating new video element for track ${track.id}');

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
      debugPrint('VideoElementCapture: Failed to create: $e');
      return null;
    }
  }

  /// Find an existing video element that has a track with the given ID.
  static web.HTMLVideoElement? _findExistingVideoElement(String trackId) {
    final videos = web.document.querySelectorAll('video');
    debugPrint('VideoElementCapture: Searching ${videos.length} video elements for track $trackId');

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
            debugPrint('VideoElementCapture: Found match in video[$i] - ${video.videoWidth}x${video.videoHeight}');
            return video;
          }
        }
      }
    }

    debugPrint('VideoElementCapture: No existing video element found for track $trackId');
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

      debugPrint('VideoElementCapture: createFromVideoElement ${width}x$height, readyState=${video.readyState}');

      // Get the stream from the video element
      final srcObject = video.srcObject;
      web.MediaStream stream;

      if (srcObject != null && srcObject.isA<web.MediaStream>()) {
        stream = srcObject as web.MediaStream;
      } else {
        // Create a dummy stream if no srcObject
        stream = web.MediaStream();
        debugPrint('VideoElementCapture: No srcObject on video, using empty stream');
      }

      return VideoElementCapture._(video, stream, ownsElement: false);
    } catch (e) {
      debugPrint('VideoElementCapture: createFromVideoElement failed: $e');
      return null;
    }
  }

  /// Find any video element with a live video track and capture from it.
  ///
  /// This is used after RTCVideoRenderer creates a video element.
  static VideoElementCapture? findAndCapture() {
    final videos = web.document.querySelectorAll('video');
    debugPrint('VideoElementCapture: Searching ${videos.length} video elements for live track');

    for (var i = 0; i < videos.length; i++) {
      final node = videos.item(i);
      if (node == null) continue;

      final video = node as web.HTMLVideoElement;
      final width = video.videoWidth;
      final height = video.videoHeight;

      debugPrint('VideoElementCapture: Video[$i] size=${width}x$height, readyState=${video.readyState}');

      // Skip videos with no real dimensions
      if (width < 10 || height < 10) continue;

      final srcObject = video.srcObject;
      if (srcObject == null) continue;

      if (srcObject.isA<web.MediaStream>()) {
        final stream = srcObject as web.MediaStream;
        final tracks = stream.getVideoTracks();

        debugPrint('VideoElementCapture: Video[$i] has ${tracks.length} video tracks');

        for (var j = 0; j < tracks.length; j++) {
          final t = tracks.toDart[j];
          debugPrint('VideoElementCapture: Track[$j] readyState=${t.readyState}, enabled=${t.enabled}');

          // Look for a live track
          if (t.readyState == 'live' && t.enabled) {
            debugPrint('VideoElementCapture: Found live track in video[$i]!');
            return VideoElementCapture._(video, stream, ownsElement: false);
          }
        }
      }
    }

    debugPrint('VideoElementCapture: No video element with live track found');
    return null;
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

    // Listen for when video has proper dimensions
    void onLoadedMetadata(web.Event e) {
      final w = _videoElement.videoWidth;
      final h = _videoElement.videoHeight;
      debugPrint('VideoElementCapture: Metadata loaded ${w}x$h');
    }
    _videoElement.addEventListener('loadedmetadata', onLoadedMetadata.toJS);

    // Start playback only if we own the element (existing elements are already playing)
    if (ownsElement) {
      _videoElement.play().toDart.catchError((e) {
        debugPrint('VideoElementCapture: Play failed: $e');
        return null;
      });
    }

    // Use timer to control frame rate (~15fps)
    _captureTimer = Timer.periodic(
      const Duration(milliseconds: 66),
      (_) => _captureFrame(),
    );

    debugPrint('VideoElementCapture: Started capture (ownsElement=$ownsElement)');
  }

  /// Stop capturing frames.
  void stopCapture() {
    _isCapturing = false;
    _captureTimer?.cancel();
    _captureTimer = null;
    // Don't pause the video - it causes AbortError if play() is still in progress
    // The video element will be cleaned up in dispose() anyway
    debugPrint('VideoElementCapture: Stopped capture');
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
      debugPrint('VideoElementCapture: Video ready ${videoWidth}x$videoHeight');
      // Log track state for debugging
      final tracks = _stream.getVideoTracks();
      debugPrint('VideoElementCapture: Stream has ${tracks.length} video tracks');
      if (tracks.length > 0) {
        final track = tracks.toDart[0];
        debugPrint('VideoElementCapture: Track enabled=${track.enabled}, readyState=${track.readyState}, muted=${(track as dynamic).muted}');
      }
    }

    _frameInFlight = true;

    try {
      _width = videoWidth;
      _height = videoHeight;

      // Use createImageBitmap to capture the current frame
      // This is GPU-efficient and doesn't require a canvas
      final imageBitmapPromise = web.window.createImageBitmap(
        _videoElement as web.ImageBitmapSource,
      );

      final imageBitmap = await imageBitmapPromise.toDart;

      // Convert to Flutter ui.Image
      final newFrame = await ui_web.createImageFromImageBitmap(
        imageBitmap as JSAny,
      );

      // Swap frames
      final oldFrame = _currentFrame;
      _currentFrame = newFrame;
      _hasNewFrame = true;
      _frameNumber++;

      if (_frameNumber == 1) {
        debugPrint(
            'VideoElementCapture: First frame captured! ${_width}x$_height');
      }

      oldFrame?.dispose();
    } catch (e) {
      debugPrint('VideoElementCapture: Frame capture error: $e');
    } finally {
      _frameInFlight = false;
    }
  }

  /// Mark the current frame as consumed.
  void markConsumed() {
    _hasNewFrame = false;
  }

  /// Get the current frame and transfer ownership to caller.
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
        debugPrint('VideoElementCapture: Error disposing: $e');
      }
    }

    debugPrint('VideoElementCapture: Disposed (ownsElement=$ownsElement)');
  }
}
