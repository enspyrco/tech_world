// Web implementation of text-to-speech using browser's speechSynthesis API.
//
// This file should only be imported on web platforms.

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;

/// Text-to-speech service using browser's speechSynthesis API.
class TtsService {
  TtsService() {
    _loadVoices();
  }

  web.SpeechSynthesisVoice? _selectedVoice;
  bool _isReady = false;
  double _rate = 1.0;
  double _pitch = 1.0;

  /// Whether the TTS service is ready to speak.
  bool get isReady => _isReady;

  /// Load available voices.
  void _loadVoices() {
    // Voices may not be available immediately
    final voices = web.window.speechSynthesis.getVoices();
    if (voices.length > 0) {
      _selectBestVoice(voices);
      _isReady = true;
    } else {
      // Wait for voices to load
      web.window.speechSynthesis.onvoiceschanged = (web.Event event) {
        final loadedVoices = web.window.speechSynthesis.getVoices();
        _selectBestVoice(loadedVoices);
        _isReady = true;
      }.toJS;
    }
  }

  /// Select the best voice for Clawd.
  void _selectBestVoice(JSArray<web.SpeechSynthesisVoice> voices) {
    final voiceList = voices.toDart;
    debugPrint('TtsService: ${voiceList.length} voices available');

    // Preference order for a friendly tutor voice:
    // 1. Google UK English (clear, friendly)
    // 2. Any UK English voice
    // 3. Google US English
    // 4. Any US English voice
    // 5. First English voice
    // 6. Default

    for (final voice in voiceList) {
      debugPrint('TtsService: Voice: ${voice.name} (${voice.lang})');
    }

    // Try to find a good English voice
    _selectedVoice = voiceList.cast<web.SpeechSynthesisVoice?>().firstWhere(
          (v) => v!.name.contains('Google UK English'),
          orElse: () => voiceList.cast<web.SpeechSynthesisVoice?>().firstWhere(
                (v) => v!.lang.startsWith('en-GB'),
                orElse: () => voiceList.cast<web.SpeechSynthesisVoice?>().firstWhere(
                      (v) => v!.name.contains('Google US English'),
                      orElse: () => voiceList.cast<web.SpeechSynthesisVoice?>().firstWhere(
                            (v) => v!.lang.startsWith('en'),
                            orElse: () => voiceList.isNotEmpty ? voiceList.first : null,
                          ),
                    ),
              ),
        );

    if (_selectedVoice != null) {
      debugPrint('TtsService: Selected voice: ${_selectedVoice!.name}');
    }
  }

  /// Speak the given text.
  Future<void> speak(String text) async {
    if (text.isEmpty) return;

    // Cancel any ongoing speech
    web.window.speechSynthesis.cancel();

    final utterance = web.SpeechSynthesisUtterance(text);

    if (_selectedVoice != null) {
      utterance.voice = _selectedVoice;
    }

    utterance.rate = _rate;
    utterance.pitch = _pitch;

    final completer = Completer<void>();

    utterance.onend = (web.Event event) {
      if (!completer.isCompleted) completer.complete();
    }.toJS;

    utterance.onerror = (web.Event event) {
      debugPrint('TtsService: Speech error');
      if (!completer.isCompleted) completer.complete();
    }.toJS;

    web.window.speechSynthesis.speak(utterance);

    // Don't wait for completion - let it speak in background
    // return completer.future;
  }

  /// Stop any ongoing speech.
  void stop() {
    web.window.speechSynthesis.cancel();
  }

  /// Set speech rate (0.1 to 10, default 1.0).
  void setRate(double rate) {
    _rate = rate.clamp(0.1, 10.0);
  }

  /// Set speech pitch (0 to 2, default 1.0).
  void setPitch(double pitch) {
    _pitch = pitch.clamp(0.0, 2.0);
  }

  void dispose() {
    stop();
  }
}
