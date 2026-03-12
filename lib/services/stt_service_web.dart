// Web implementation of speech-to-text using browser's SpeechRecognition API.
//
// This file should only be imported on web platforms.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:logging/logging.dart';

final _log = Logger('SttService');

/// Speech-to-text service using browser's SpeechRecognition API.
class SttService {
  SttService() {
    _isSupported = globalContext.has('webkitSpeechRecognition') ||
        globalContext.has('SpeechRecognition');
    _log.info('SttService: supported=$_isSupported');
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
      _log.info('SttService: Not supported');
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
          _log.fine('SttService: Recognized: "$transcript"');
          if (!_resultCompleter!.isCompleted) {
            _resultCompleter!.complete(transcript);
          }
        } catch (e) {
          _log.warning('SttService: Result parse error', e);
          if (!_resultCompleter!.isCompleted) {
            _resultCompleter!.complete(null);
          }
        }
        _setListening(false);
      }.toJS;

      // Handle error
      _recognition!['onerror'] = (JSObject event) {
        final error = (event['error'] as JSString?)?.toDart;
        _log.warning('SttService: Error: $error');
        if (!_resultCompleter!.isCompleted) {
          _resultCompleter!.complete(null);
        }
        _setListening(false);
      }.toJS;

      // Handle end (no result)
      _recognition!['onend'] = (JSObject event) {
        _log.fine('SttService: Ended');
        if (!_resultCompleter!.isCompleted) {
          _resultCompleter!.complete(null);
        }
        _setListening(false);
      }.toJS;

      // Start listening
      _recognition!.callMethod('start'.toJS);
      _setListening(true);
      _log.info('SttService: Listening...');

      return await _resultCompleter!.future;
    } catch (e) {
      _log.warning('SttService: Exception', e);
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
        _log.warning('SttService: Stop error', e);
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
