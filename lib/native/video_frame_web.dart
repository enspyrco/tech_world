// Web implementation for video frame capture.
//
// Uses a hidden HTMLVideoElement + createImageBitmap for GPU-efficient
// video frame capture on web platforms.
//
// This file should only be imported on web platforms.

import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;

/// Web-based video frame capture using createImageBitmap.
///
/// Creates a hidden HTMLVideoElement, attaches the MediaStream to it,
/// and captures frames for rendering in Flame/Flutter.
class WebVideoFrameCapture {
  WebVideoFrameCapture._(this._videoElement, {this.ownsElement = true});

  final web.HTMLVideoElement _videoElement;
  final bool ownsElement; // Whether we created this element (and should dispose it)
  ui.Image? _currentFrame;
  bool _hasNewFrame = false;
  bool _isCapturing = false;
  int _frameNumber = 0;
  Timer? _captureTimer;

  /// Create a capture instance from a MediaStream.
  ///
  /// Creates a hidden video element and attaches the stream to it.
  static Future<WebVideoFrameCapture?> createFromStream(
      web.MediaStream stream) async {
    // Create a hidden video element
    final video = web.document.createElement('video') as web.HTMLVideoElement;
    video.autoplay = true;
    video.muted = true;
    video.playsInline = true;
    video.style.display = 'none';

    // Attach the stream
    video.srcObject = stream;

    // Add to document (required for some browsers)
    web.document.body?.appendChild(video);

    // Wait for video to be ready
    try {
      await video.play().toDart;
    } catch (e) {
      debugPrint('WebVideoFrameCapture: play() failed: $e');
    }

    // Check if stream tracks are still alive after async operations
    final videoTracks = stream.getVideoTracks();
    if (videoTracks.length == 0) {
      debugPrint('WebVideoFrameCapture: No video tracks in stream after play()');
      video.srcObject = null;
      video.remove();
      return null;
    }
    final track = videoTracks.toDart[0];
    if (track.readyState != 'live') {
      debugPrint(
          'WebVideoFrameCapture: Track died during initialization (state: ${track.readyState})');
      video.srcObject = null;
      video.remove();
      return null;
    }

    // Wait for valid video dimensions (at least 32x32)
    // Remote tracks may need more time to start streaming real frames
    var attempts = 0;
    while (video.videoWidth < _minValidDimension && attempts < 50) {
      // Check if track is still alive
      if (track.readyState != 'live') {
        debugPrint(
            'WebVideoFrameCapture: Track died while waiting for dimensions');
        video.srcObject = null;
        video.remove();
        return null;
      }
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    if (video.videoWidth < _minValidDimension) {
      // Still no valid dimensions after 5 seconds
      debugPrint(
          'WebVideoFrameCapture: Created video element (dimensions pending: ${video.videoWidth}x${video.videoHeight})');
    } else {
      debugPrint(
          'WebVideoFrameCapture: Created video element ${video.videoWidth}x${video.videoHeight}');
    }

    return WebVideoFrameCapture._(video);
  }

  /// Create a capture instance from a MediaStreamTrack.
  static Future<WebVideoFrameCapture?> createFromTrack(
      web.MediaStreamTrack track) async {
    // Check if track is still alive
    if (track.readyState != 'live') {
      debugPrint(
          'WebVideoFrameCapture: Track not live (state: ${track.readyState}), skipping');
      return null;
    }
    // Check if track is enabled
    if (!track.enabled) {
      debugPrint('WebVideoFrameCapture: Track is disabled, enabling it');
      track.enabled = true;
    }
    debugPrint(
        'WebVideoFrameCapture: Creating capture from track ${track.id} '
        '(state: ${track.readyState}, enabled: ${track.enabled}, muted: ${track.muted})');

    final stream = web.MediaStream();
    stream.addTrack(track);
    return createFromStream(stream);
  }

  /// Create a capture instance from an existing video element.
  ///
  /// Use this when LiveKit has already created a video element for the track.
  /// Returns a Future because we may need to wait for the video to start playing.
  static Future<WebVideoFrameCapture?> createFromExistingVideo(
      web.HTMLVideoElement video) async {
    // Ensure video element has correct attributes for autoplay
    video.autoplay = true;
    video.muted = true;
    video.playsInline = true;

    // Try to play the video if it's not already playing
    if (video.paused || video.readyState == 0) {
      debugPrint('WebVideoFrameCapture: Existing video is paused/not ready (readyState=${video.readyState}), calling play()');
      try {
        await video.play().toDart;
        debugPrint('WebVideoFrameCapture: play() succeeded');
      } catch (e) {
        debugPrint('WebVideoFrameCapture: play() failed: $e');
      }
    }

    // Wait for valid dimensions (up to 5 seconds)
    var attempts = 0;
    while (video.videoWidth < _minValidDimension && attempts < 50) {
      if (attempts % 10 == 0) {
        debugPrint('WebVideoFrameCapture: Waiting for dimensions... readyState=${video.readyState}, size=${video.videoWidth}x${video.videoHeight}');
      }
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    if (video.videoWidth < _minValidDimension ||
        video.videoHeight < _minValidDimension) {
      debugPrint(
          'WebVideoFrameCapture: Existing video still has invalid dimensions after waiting: '
          '${video.videoWidth}x${video.videoHeight}, readyState=${video.readyState}');
      return null;
    }
    debugPrint(
        'WebVideoFrameCapture: Using existing video element '
        '${video.videoWidth}x${video.videoHeight}');
    // Don't remove this video element on dispose - we didn't create it
    return WebVideoFrameCapture._(video, ownsElement: false);
  }

  /// Find a video element by matching its MediaStream track ID or label.
  /// LiveKit uses different IDs internally, but puts the LiveKit track ID in the label.
  static web.HTMLVideoElement? findVideoElementByTrackId(String trackId) {
    final videos = web.document.querySelectorAll('video');
    debugPrint('WebVideoFrameCapture: Found ${videos.length} video elements');

    for (var i = 0; i < videos.length; i++) {
      final node = videos.item(i);
      if (node == null) continue;

      final video = node as web.HTMLVideoElement;
      final srcObject = video.srcObject;
      debugPrint(
          'WebVideoFrameCapture: Video[$i] srcObject=${srcObject != null}');

      if (srcObject == null) continue;

      // Check if srcObject is a MediaStream
      if (srcObject.isA<web.MediaStream>()) {
        final stream = srcObject as web.MediaStream;
        final tracks = stream.getVideoTracks();
        debugPrint(
            'WebVideoFrameCapture: Video[$i] has ${tracks.length} video tracks');

        for (var j = 0; j < tracks.length; j++) {
          final track = tracks.toDart[j];
          debugPrint('WebVideoFrameCapture: Track[$j] id=${track.id}, label=${track.label}');
          // Match by ID or by label (LiveKit puts its track ID in the label)
          if (track.id == trackId || track.label == trackId) {
            debugPrint('WebVideoFrameCapture: MATCH FOUND by ${track.id == trackId ? "id" : "label"}!');
            return video;
          }
        }
      }
    }
    return null;
  }

  /// Debug: List all video elements and their track IDs.
  static void debugListVideoElements() {
    final videos = web.document.querySelectorAll('video');
    debugPrint(
        'WebVideoFrameCapture DEBUG: Found ${videos.length} video elements');

    for (var i = 0; i < videos.length; i++) {
      final node = videos.item(i);
      if (node == null) continue;

      final video = node as web.HTMLVideoElement;
      debugPrint('  Video[$i]: id=${video.id}, readyState=${video.readyState}, '
          'size=${video.videoWidth}x${video.videoHeight}');

      final srcObject = video.srcObject;
      if (srcObject == null) {
        debugPrint('    srcObject: null');
        continue;
      }

      if (srcObject.isA<web.MediaStream>()) {
        final stream = srcObject as web.MediaStream;
        final videoTracks = stream.getVideoTracks();
        final audioTracks = stream.getAudioTracks();
        debugPrint(
            '    MediaStream: ${videoTracks.length} video, ${audioTracks.length} audio tracks');

        for (var j = 0; j < videoTracks.length; j++) {
          final track = videoTracks.toDart[j];
          debugPrint(
              '      VideoTrack[$j]: id=${track.id}, label=${track.label}, enabled=${track.enabled}');
        }
      }
    }
  }

  /// Whether a new frame is available.
  bool get hasNewFrame => _hasNewFrame;

  /// Whether capture is active.
  bool get isActive => _isCapturing;

  /// The current captured frame, or null if no frame available.
  ui.Image? get currentFrame => _currentFrame;

  /// Video width in pixels.
  int get width => _videoElement.videoWidth;

  /// Video height in pixels.
  int get height => _videoElement.videoHeight;

  /// Current frame number.
  int get frameNumber => _frameNumber;

  /// Start capturing frames.
  ///
  /// Uses a timer-based approach for compatibility.
  /// Captures at approximately 15fps (66ms interval).
  void startCapture() {
    if (_isCapturing) return;
    _isCapturing = true;

    // Use timer-based capture for broad compatibility
    // 66ms = ~15fps
    _captureTimer = Timer.periodic(
      const Duration(milliseconds: 66),
      (_) => _captureFrame(),
    );
  }

  /// Stop capturing frames.
  void stopCapture() {
    _isCapturing = false;
    _captureTimer?.cancel();
    _captureTimer = null;
  }

  /// Minimum dimensions to consider video valid (not a placeholder)
  static const int _minValidDimension = 32;

  /// Capture the current video frame.
  Future<void> _captureFrame() async {
    if (!_isCapturing) return;
    if (_videoElement.readyState < 2) return; // HAVE_CURRENT_DATA

    final videoWidth = _videoElement.videoWidth;
    final videoHeight = _videoElement.videoHeight;
    // Skip frames that are too small (placeholders or not yet streaming)
    if (videoWidth < _minValidDimension || videoHeight < _minValidDimension) {
      return;
    }

    try {
      // Create ImageBitmap from video element (GPU-efficient)
      final imageBitmapPromise = web.window.createImageBitmap(
        _videoElement as web.ImageBitmapSource,
      );

      final imageBitmap = await imageBitmapPromise.toDart;

      // Convert to Flutter ui.Image
      final newFrame = await ui_web.createImageFromImageBitmap(
        imageBitmap as JSAny,
      );

      // Swap frames (dispose old one)
      final oldFrame = _currentFrame;
      _currentFrame = newFrame;
      _hasNewFrame = true;
      _frameNumber++;

      // Log first successful frame
      if (_frameNumber == 1) {
        debugPrint(
            'WebVideoFrameCapture: First frame captured! ${videoWidth}x$videoHeight');
      }

      oldFrame?.dispose();
    } catch (e, stackTrace) {
      debugPrint('WebVideoFrameCapture: Frame capture error: $e');
      debugPrint('WebVideoFrameCapture: Stack trace: $stackTrace');
    }
  }

  /// Mark the current frame as consumed.
  void markConsumed() {
    _hasNewFrame = false;
  }

  /// Get the current frame (and transfer ownership to caller).
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
    debugPrint('WebVideoFrameCapture: Disposing capture (frame #$_frameNumber)');
    stopCapture();
    _currentFrame?.dispose();
    _currentFrame = null;

    // Only remove the video element if we created it
    if (ownsElement) {
      _videoElement.srcObject = null;
      _videoElement.remove();
    }
    debugPrint('WebVideoFrameCapture: Disposed');
  }
}
