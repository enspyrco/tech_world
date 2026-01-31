import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// FFI bindings for native video frame capture.
///
/// This provides zero-copy access to WebRTC video frames by directly
/// reading from shared memory allocated by the native plugin.
///
/// Currently only supports macOS. On other platforms, VideoFrameCapture
/// operations will return null/no-op.

/// Whether the current platform supports FFI video capture.
final bool _isSupported = Platform.isMacOS;

// Lazy-load the native library to avoid crashes on unsupported platforms
DynamicLibrary? _nativeLib;

DynamicLibrary? _getNativeLib() {
  if (!_isSupported) return null;
  return _nativeLib ??= DynamicLibrary.executable();
}

// C function signatures
typedef _VideoFrameCaptureCreateNative = Pointer<Void> Function(
  Pointer<Utf8> trackId,
  Int32 targetFps,
  Int32 maxWidth,
  Int32 maxHeight,
);
typedef _VideoFrameCaptureCreate = Pointer<Void> Function(
  Pointer<Utf8> trackId,
  int targetFps,
  int maxWidth,
  int maxHeight,
);

typedef _VideoFrameCaptureGetBufferNative = Pointer<VideoFrameBuffer> Function(
  Pointer<Void> capture,
);
typedef _VideoFrameCaptureGetBuffer = Pointer<VideoFrameBuffer> Function(
  Pointer<Void> capture,
);

typedef _VideoFrameCaptureMarkConsumedNative = Void Function(
  Pointer<Void> capture,
);
typedef _VideoFrameCaptureMarkConsumed = void Function(
  Pointer<Void> capture,
);

typedef _VideoFrameCaptureIsActiveNative = Int32 Function(
  Pointer<Void> capture,
);
typedef _VideoFrameCaptureIsActive = int Function(
  Pointer<Void> capture,
);

typedef _VideoFrameCaptureDestroyNative = Void Function(
  Pointer<Void> capture,
);
typedef _VideoFrameCaptureDestroy = void Function(
  Pointer<Void> capture,
);

typedef _VideoFrameCaptureListTracksNative = Int32 Function(
  Pointer<Utf8> buffer,
  Int32 bufferSize,
);
typedef _VideoFrameCaptureListTracks = int Function(
  Pointer<Utf8> buffer,
  int bufferSize,
);

typedef _VideoFrameCaptureInitNative = Void Function();
typedef _VideoFrameCaptureInit = void Function();

// Lazy-loaded native functions (null on unsupported platforms)
_VideoFrameCaptureCreate? _create;
_VideoFrameCaptureGetBuffer? _getBuffer;
_VideoFrameCaptureMarkConsumed? _markConsumed;
_VideoFrameCaptureIsActive? _isActive;
_VideoFrameCaptureDestroy? _destroy;
_VideoFrameCaptureListTracks? _listTracks;
_VideoFrameCaptureInit? _init;

void _ensureFunctionsLoaded() {
  if (!_isSupported) return;
  final lib = _getNativeLib();
  if (lib == null) return;

  _create ??= lib.lookupFunction<_VideoFrameCaptureCreateNative,
      _VideoFrameCaptureCreate>('video_frame_capture_create');
  _getBuffer ??= lib.lookupFunction<_VideoFrameCaptureGetBufferNative,
      _VideoFrameCaptureGetBuffer>('video_frame_capture_get_buffer');
  _markConsumed ??= lib.lookupFunction<_VideoFrameCaptureMarkConsumedNative,
      _VideoFrameCaptureMarkConsumed>('video_frame_capture_mark_consumed');
  _isActive ??= lib.lookupFunction<_VideoFrameCaptureIsActiveNative,
      _VideoFrameCaptureIsActive>('video_frame_capture_is_active');
  _destroy ??= lib.lookupFunction<_VideoFrameCaptureDestroyNative,
      _VideoFrameCaptureDestroy>('video_frame_capture_destroy');
  _listTracks ??= lib.lookupFunction<_VideoFrameCaptureListTracksNative,
      _VideoFrameCaptureListTracks>('video_frame_capture_list_tracks');
  _init ??= lib.lookupFunction<_VideoFrameCaptureInitNative,
      _VideoFrameCaptureInit>('video_frame_capture_init');
}

/// Video frame buffer structure matching the native C struct.
/// Memory layout must match VideoFrameCapture.h exactly.
final class VideoFrameBuffer extends Struct {
  @Uint32()
  external int width;

  @Uint32()
  external int height;

  @Uint32()
  external int bytesPerRow;

  @Uint32()
  external int format; // 0 = BGRA, 1 = RGBA

  @Uint64()
  external int timestamp;

  @Uint32()
  external int frameNumber;

  @Uint32()
  external int ready; // 1 = new frame available

  @Uint32()
  external int error;

  @Uint32()
  external int reserved;

  // Pixels follow immediately after the header (flexible array)
}

/// Size of the buffer header in bytes (must match native code)
const int videoFrameBufferHeaderSize = 40;

/// Captures video frames from a WebRTC video track via FFI.
///
/// Usage:
/// ```dart
/// final capture = VideoFrameCapture.create(trackId, targetFps: 15);
/// if (capture != null) {
///   // In game loop:
///   if (capture.hasNewFrame) {
///     final pixels = capture.getPixels();
///     // Use pixels to create ui.Image
///   }
///   // When done:
///   capture.dispose();
/// }
/// ```
class VideoFrameCapture {
  final Pointer<Void> _handle;
  Pointer<VideoFrameBuffer>? _buffer;
  int _lastFrameNumber = 0;
  bool _disposed = false;

  VideoFrameCapture._(this._handle) {
    _buffer = _getBuffer?.call(_handle);
  }

  /// Create a new frame capture for the given track.
  ///
  /// Returns null if the track cannot be found, capture fails, or
  /// the platform is not supported.
  static VideoFrameCapture? create(
    String trackId, {
    int targetFps = 15,
    int maxWidth = 640,
    int maxHeight = 480,
  }) {
    if (!_isSupported) return null;

    // Ensure native functions are loaded
    _ensureFunctionsLoaded();
    if (_create == null || _init == null) return null;

    // Initialize the capture system
    _init!();

    final trackIdPtr = trackId.toNativeUtf8();
    try {
      final handle = _create!(trackIdPtr, targetFps, maxWidth, maxHeight);
      if (handle == nullptr) {
        return null;
      }
      return VideoFrameCapture._(handle);
    } finally {
      calloc.free(trackIdPtr);
    }
  }

  /// Check if a new frame is available.
  bool get hasNewFrame {
    if (_disposed || _buffer == null || _buffer == nullptr) return false;
    final buf = _buffer!.ref;
    return buf.ready == 1 && buf.frameNumber != _lastFrameNumber;
  }

  /// Check if the capture session is active.
  bool get isActive {
    if (_disposed || _isActive == null) return false;
    return _isActive!(_handle) == 1;
  }

  /// Get the current frame's width.
  int get width => _buffer?.ref.width ?? 0;

  /// Get the current frame's height.
  int get height => _buffer?.ref.height ?? 0;

  /// Get the current frame's bytes per row.
  int get bytesPerRow => _buffer?.ref.bytesPerRow ?? 0;

  /// Get the current frame number.
  int get frameNumber => _buffer?.ref.frameNumber ?? 0;

  /// Get the current frame's timestamp in nanoseconds.
  int get timestamp => _buffer?.ref.timestamp ?? 0;

  /// Get the pixel data as a Uint8List.
  ///
  /// Returns the raw BGRA pixel data. The data is valid until the next
  /// call to markConsumed() or until a new frame arrives.
  ///
  /// Returns null if no frame is available.
  Uint8List? getPixels() {
    if (_disposed || _buffer == null || _buffer == nullptr) return null;
    final buf = _buffer!.ref;
    if (buf.ready != 1) return null;

    _lastFrameNumber = buf.frameNumber;

    // Calculate pixel data address (header + offset)
    final bufferAddress = _buffer!.address;
    final pixelsAddress = bufferAddress + videoFrameBufferHeaderSize;
    final pixelsPtr = Pointer<Uint8>.fromAddress(pixelsAddress);

    final dataSize = buf.height * buf.bytesPerRow;
    return pixelsPtr.asTypedList(dataSize);
  }

  /// Mark the current frame as consumed.
  ///
  /// Call this after reading pixels to allow the next frame to be written.
  void markConsumed() {
    if (_disposed || _markConsumed == null) return;
    _markConsumed!(_handle);
  }

  /// Dispose the capture session and free resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy?.call(_handle);
    _buffer = null;
  }

  /// List all available video track IDs.
  ///
  /// Returns a list of track IDs that can be used with [create].
  /// Returns an empty list on unsupported platforms.
  static List<String> listTracks() {
    if (!_isSupported) return [];

    _ensureFunctionsLoaded();
    if (_init == null || _listTracks == null) return [];

    _init!();

    // Allocate buffer for track IDs
    const bufferSize = 4096;
    final buffer = calloc<Uint8>(bufferSize);
    try {
      final count = _listTracks!(buffer.cast<Utf8>(), bufferSize);
      if (count == 0) return [];

      final trackIdsStr = buffer.cast<Utf8>().toDartString();
      return trackIdsStr.split(',').where((s) => s.isNotEmpty).toList();
    } finally {
      calloc.free(buffer);
    }
  }
}
