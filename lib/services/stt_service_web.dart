// Web implementation of speech-to-text using browser's SpeechRecognition API.
//
// This file should only be imported on web platforms.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:logging/logging.dart';
import 'package:tech_world/services/stt_result.dart';

export 'package:tech_world/services/stt_result.dart' show SttResult;

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
  Completer<SttResult>? _resultCompleter;

  /// Whether speech recognition is supported in this browser.
  bool get isSupported => _isSupported;

  /// Whether currently listening for speech.
  final ValueNotifier<bool> listening = ValueNotifier(false);

  /// Start listening for speech and return the recognized text plus the
  /// browser's confidence score for the utterance.
  ///
  /// Returns `(null, null)` if cancelled, unsupported, or error. The
  /// confidence axis is consumed by [classifyComboCast] in
  /// `lib/spellbook/spell_algebra.dart` to drive the 2x2 cast lattice
  /// (Phase 3) — door-cast (Phase 2) ignores it.
  ///
  /// **Web Speech API note:** `confidence` is per-alternative, not
  /// per-word. We always read alternative 0, so this is one number for
  /// the whole utterance. Multi-word combos inherit it; if richer
  /// per-word confidence becomes useful we'd need to set
  /// `maxAlternatives > 1` and synthesise from alternative disagreement.
  Future<SttResult> listen() async {
    if (!_isSupported) {
      _log.info('SttService: Not supported');
      return const SttResult.empty();
    }

    if (_isListening) {
      stop();
      return const SttResult.empty();
    }

    _resultCompleter = Completer<SttResult>();

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
          // `confidence` is a `double` in the Web Speech API. Some
          // implementations return 0 when they can't compute one — we
          // surface that verbatim and let the algebra's noise floor
          // handle it.
          final confidence =
              (firstAlt['confidence'] as JSNumber?)?.toDartDouble;
          _log.fine('SttService: Recognized: "$transcript" '
              '(confidence: ${confidence?.toStringAsFixed(2) ?? "n/a"})');
          if (!_resultCompleter!.isCompleted) {
            _resultCompleter!.complete(SttResult(
              transcript: transcript,
              confidence: confidence,
            ));
          }
        } catch (e) {
          _log.warning('SttService: Result parse error', e);
          if (!_resultCompleter!.isCompleted) {
            _resultCompleter!.complete(const SttResult.empty());
          }
        }
        _setListening(false);
      }.toJS;

      // Handle error
      _recognition!['onerror'] = (JSObject event) {
        final error = (event['error'] as JSString?)?.toDart;
        _log.warning('SttService: Error: $error');
        if (!_resultCompleter!.isCompleted) {
          _resultCompleter!.complete(const SttResult.empty());
        }
        _setListening(false);
      }.toJS;

      // Handle end (no result)
      _recognition!['onend'] = (JSObject event) {
        _log.fine('SttService: Ended');
        if (!_resultCompleter!.isCompleted) {
          _resultCompleter!.complete(const SttResult.empty());
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
        _resultCompleter!.complete(const SttResult.empty());
      }
      return const SttResult.empty();
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
