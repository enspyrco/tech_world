// Web implementation of speech-to-text using browser's SpeechRecognition API.
//
// This file should only be imported on web platforms.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart' show debugPrint, ValueNotifier;

/// Speech-to-text service using browser's SpeechRecognition API.
class SttService {
  SttService() {
    _isSupported = globalContext.has('webkitSpeechRecognition') ||
        globalContext.has('SpeechRecognition');
    debugPrint('SttService: supported=$_isSupported');
  }

  bool _isSupported = false;
  JSObject? _recognition;
  bool _isListening = false;
  Completer<String?>? _resultCompleter;

  /// Whether speech recognition is supported in this browser.
  bool get isSupported => _isSupported;

  /// Whether currently listening for speech.
  final ValueNotifier<bool> listening = ValueNotifier(false);

  /// Start listening for speech and return the recognized text.
  ///
  /// Returns null if cancelled, unsupported, or error.
  Future<String?> listen() async {
    if (!_isSupported) {
      debugPrint('SttService: Not supported');
      return null;
    }

    if (_isListening) {
      stop();
      return null;
    }

    _resultCompleter = Completer<String?>();

    try {
      // Create SpeechRecognition instance
      final constructor = globalContext.has('webkitSpeechRecognition')
          ? globalContext['webkitSpeechRecognition'] as JSFunction
          : globalContext['SpeechRecognition'] as JSFunction;

      _recognition = constructor.callAsConstructor<JSObject>();

      // Configure
      _recognition!['continuous'] = false.toJS;
      _recognition!['interimResults'] = false.toJS;
      _recognition!['lang'] = 'en-US'.toJS;

      // Handle result
      _recognition!['onresult'] = (JSObject event) {
        try {
          final results = event['results']! as JSObject;
          final firstResult = results['0'] as JSObject;
          final firstAlt = firstResult['0'] as JSObject;
          final transcript = (firstAlt['transcript'] as JSString).toDart;
          debugPrint('SttService: Recognized: "$transcript"');
          if (!_resultCompleter!.isCompleted) {
            _resultCompleter!.complete(transcript);
          }
        } catch (e) {
          debugPrint('SttService: Result parse error: $e');
          if (!_resultCompleter!.isCompleted) {
            _resultCompleter!.complete(null);
          }
        }
        _setListening(false);
      }.toJS;

      // Handle error
      _recognition!['onerror'] = (JSObject event) {
        final error = (event['error'] as JSString?)?.toDart;
        debugPrint('SttService: Error: $error');
        if (!_resultCompleter!.isCompleted) {
          _resultCompleter!.complete(null);
        }
        _setListening(false);
      }.toJS;

      // Handle end (no result)
      _recognition!['onend'] = (JSObject event) {
        debugPrint('SttService: Ended');
        if (!_resultCompleter!.isCompleted) {
          _resultCompleter!.complete(null);
        }
        _setListening(false);
      }.toJS;

      // Start listening
      _recognition!.callMethod('start'.toJS);
      _setListening(true);
      debugPrint('SttService: Listening...');

      return await _resultCompleter!.future;
    } catch (e) {
      debugPrint('SttService: Exception: $e');
      _setListening(false);
      if (_resultCompleter != null && !_resultCompleter!.isCompleted) {
        _resultCompleter!.complete(null);
      }
      return null;
    }
  }

  /// Stop listening.
  void stop() {
    if (_recognition != null) {
      try {
        _recognition!.callMethod('stop'.toJS);
      } catch (e) {
        debugPrint('SttService: Stop error: $e');
      }
    }
    _setListening(false);
  }

  void _setListening(bool value) {
    _isListening = value;
    listening.value = value;
  }

  void dispose() {
    stop();
    listening.dispose();
  }
}
