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
  WebVideoFrameCapture._(this._videoElement);

  final web.HTMLVideoElement _videoElement;
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

    // Wait for video dimensions to be available
    var attempts = 0;
    while (video.videoWidth == 0 && attempts < 50) {
      await Future.delayed(const Duration(milliseconds: 50));
      attempts++;
    }

    if (video.videoWidth == 0) {
      debugPrint('WebVideoFrameCapture: Video dimensions not available');
      video.remove();
      return null;
    }

    debugPrint(
        'WebVideoFrameCapture: Created video element ${video.videoWidth}x${video.videoHeight}');
    return WebVideoFrameCapture._(video);
  }

  /// Create a capture instance from a MediaStreamTrack.
  static Future<WebVideoFrameCapture?> createFromTrack(
      web.MediaStreamTrack track) async {
    final stream = web.MediaStream();
    stream.addTrack(track);
    return createFromStream(stream);
  }

  /// Create a capture instance from an existing video element.
  /// Use this when LiveKit has already created a video element for the track.
  static Future<WebVideoFrameCapture?> createFromExistingVideo(
      web.HTMLVideoElement video) async {
    // Ensure video element has correct attributes for autoplay
    video.autoplay = true;
    video.muted = true;
    video.playsInline = true;

    // Try to play the video if it's paused
    if (video.paused) {
      try {
        await video.play().toDart;
      } catch (e) {
        debugPrint('WebVideoFrameCapture: play() failed: $e');
      }
    }

    // Wait for video dimensions
    var attempts = 0;
    while (video.videoWidth == 0 && attempts < 50) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    debugPrint(
        'WebVideoFrameCapture: Using existing video ${video.videoWidth}x${video.videoHeight}');
    return WebVideoFrameCapture._(video);
  }

  /// Find a video element by matching its MediaStream track ID or label.
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
            debugPrint('WebVideoFrameCapture: MATCH FOUND!');
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

  /// Capture the current video frame.
  Future<void> _captureFrame() async {
    if (!_isCapturing) return;
    if (_videoElement.readyState < 2) return; // HAVE_CURRENT_DATA

    final videoWidth = _videoElement.videoWidth;
    final videoHeight = _videoElement.videoHeight;
    if (videoWidth == 0 || videoHeight == 0) return;

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
    stopCapture();
    _currentFrame?.dispose();
    _currentFrame = null;

    // Remove the hidden video element
    _videoElement.srcObject = null;
    _videoElement.remove();
  }
}
