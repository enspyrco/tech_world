/// Web implementation of the Dreamfinder avatar bridge.
///
/// Creates a same-origin iframe that renders a 3D avatar via Three.js +
/// TalkingHead. Captures frames from the iframe's canvas via
/// [CanvasCapture] and forwards LiveKit data channels (audio, mood) to
/// the iframe's window functions for lip-sync and expression changes.
///
/// ## Same-origin requirement
///
/// The iframe MUST be served from the same origin as the Flutter app so
/// that the parent can access `iframe.contentWindow` and its canvas.
/// In production, Caddy/nginx on OCI serves both Flutter (`/`) and the
/// avatar renderer (`/avatar`) from the same domain.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:logging/logging.dart';
import 'package:web/web.dart' as web;

import '../bots/bot_config.dart';
import '../native/canvas_capture_web.dart';
import 'livekit_service.dart';

final _log = Logger('DreamfinderAvatarBridge');

/// URL path for the avatar renderer (same-origin).
/// No ?muted — the iframe handles audio playback via Web Audio since DF's
/// voice comes through the data channel, not a LiveKit audio track.
const _avatarPath = '/avatar';

class DreamfinderAvatarBridge {
  DreamfinderAvatarBridge({required LiveKitService liveKitService})
      : _liveKitService = liveKitService;

  final LiveKitService _liveKitService;

  web.HTMLIFrameElement? _iframe;
  CanvasCapture? _canvasCapture;
  bool _isReady = false;
  StreamSubscription<DataChannelMessage>? _audioSubscription;
  StreamSubscription<DataChannelMessage>? _moodSubscription;
  JSFunction? _messageListener;

  /// The canvas capture instance, available after the iframe is ready.
  CanvasCapture? get canvasCapture => _canvasCapture;

  /// Whether the iframe has loaded and the canvas is being captured.
  bool get isReady => _isReady;

  /// Create the hidden iframe and start capturing once the renderer is ready.
  Future<void> initialize() async {
    if (_iframe != null) return; // Already initialized

    _iframe = _createHiddenIframe();
    web.document.body?.appendChild(_iframe!);

    // Listen for the renderer-ready postMessage from the iframe.
    final readyCompleter = Completer<void>();
    _messageListener = ((web.MessageEvent event) {
      final data = event.data;
      if (data == null) return;

      // Check for renderer-ready message
      try {
        final jsObj = data as JSObject;
        final type = jsObj.getProperty('type'.toJS);
        final typeStr = (type as JSString?)?.toDart;

        if (typeStr == 'renderer-ready') {
          if (!readyCompleter.isCompleted) readyCompleter.complete();
        }
      } catch (e) {
        _log.fine('postMessage parse error: $e');
      }
    }).toJS;

    web.window.addEventListener('message', _messageListener!);

    // Set the iframe src to trigger loading.
    _iframe!.src = _avatarPath;
    _log.info('Loading avatar renderer from $_avatarPath');

    // Wait for the renderer to signal ready (with timeout).
    // The 3D avatar GLB model (~42MB) can take over 30s on first load.
    // Browser caches it after the first download, so subsequent loads are fast.
    try {
      await readyCompleter.future.timeout(const Duration(seconds: 120));
    } on TimeoutException {
      _log.severe('Avatar renderer did not signal ready within 120 seconds');
      return;
    }

    _log.info('Avatar renderer is ready');

    // Access the iframe's canvas (same-origin).
    final canvas = _findIframeCanvas();
    if (canvas == null) {
      _log.severe('Could not find canvas in avatar iframe');
      return;
    }

    _canvasCapture = CanvasCapture.create(canvas, fps: 15);
    _canvasCapture?.startCapture();
    _isReady = true;

    // Start forwarding data channels to the iframe.
    _subscribeToDataChannels();

    _log.info('Dreamfinder avatar bridge initialized');
  }

  /// Create a hidden iframe positioned offscreen.
  ///
  /// Not `display:none` — the browser won't render Three.js in a hidden
  /// element. Instead, position it far offscreen with a small viewport.
  web.HTMLIFrameElement _createHiddenIframe() {
    final iframe =
        web.document.createElement('iframe') as web.HTMLIFrameElement;
    iframe.style.position = 'fixed';
    iframe.style.top = '-9999px';
    iframe.style.left = '-9999px';
    iframe.style.width = '256px';
    iframe.style.height = '256px';
    iframe.style.border = 'none';
    return iframe;
  }

  /// Find the Three.js canvas inside the iframe.
  web.HTMLCanvasElement? _findIframeCanvas() {
    try {
      final contentWindow = _iframe?.contentWindow;
      if (contentWindow == null) {
        _log.warning('iframe contentWindow is null');
        return null;
      }
      final contentDoc = contentWindow.document;
      final canvas = contentDoc.querySelector('canvas');
      if (canvas == null) {
        _log.warning('No canvas found in iframe');
        return null;
      }
      return canvas as web.HTMLCanvasElement;
    } catch (e) {
      _log.severe('Cannot access iframe canvas (cross-origin?): $e');
      return null;
    }
  }

  /// Forward LiveKit data channels to the iframe's window functions.
  void _subscribeToDataChannels() {
    // Audio: raw PCM16 bytes → base64-encode → __onAudioChunk(base64)
    _audioSubscription = _liveKitService.dataReceived
        .where((msg) =>
            msg.topic == 'dreamfinder-audio' &&
            msg.senderId != null &&
            isDreamfinderIdentity(msg.senderId!))
        .listen(_forwardAudio);

    // Mood: JSON → __setMood(mood) or __interruptPlayback()
    _moodSubscription = _liveKitService.dataReceived
        .where((msg) =>
            msg.topic == 'dreamfinder-mood' &&
            msg.senderId != null &&
            isDreamfinderIdentity(msg.senderId!))
        .listen(_forwardMood);
  }

  void _forwardAudio(DataChannelMessage msg) {
    try {
      final contentWindow = _iframe?.contentWindow;
      if (contentWindow == null) return;

      // Convert raw bytes to base64 for the renderer's __onAudioChunk.
      final base64 = base64Encode(msg.data);
      _callIframeFunction('__onAudioChunk', base64);
    } catch (e) {
      _log.fine('Audio forward error: $e');
    }
  }

  void _forwardMood(DataChannelMessage msg) {
    try {
      final json = msg.json;
      if (json == null) return;

      if (json['type'] == 'interrupt') {
        _callIframeFunction('__interruptPlayback', null);
      } else if (json['mood'] != null) {
        _callIframeFunction('__setMood', json['mood'] as String);
      }
    } catch (e) {
      _log.fine('Mood forward error: $e');
    }
  }

  /// Call a window function on the iframe's contentWindow.
  void _callIframeFunction(String functionName, String? argument) {
    try {
      final contentWindow = _iframe?.contentWindow;
      if (contentWindow == null) return;

      final win = contentWindow as JSObject;
      if (argument != null) {
        win.callMethod(functionName.toJS, argument.toJS);
      } else {
        win.callMethod(functionName.toJS);
      }
    } catch (e) {
      _log.fine('Call $functionName failed: $e');
    }
  }

  void dispose() {
    _audioSubscription?.cancel();
    _moodSubscription?.cancel();
    _canvasCapture?.dispose();
    _canvasCapture = null;

    if (_messageListener != null) {
      web.window.removeEventListener('message', _messageListener!);
      _messageListener = null;
    }

    _iframe?.remove();
    _iframe = null;
    _isReady = false;

    _log.info('Dreamfinder avatar bridge disposed');
  }
}
