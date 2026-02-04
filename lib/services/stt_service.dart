// Platform-aware STT service.
//
// Exports the appropriate implementation based on platform:
// - On web: Uses browser's SpeechRecognition API
// - On native: Uses a no-op stub

export 'stt_service_stub.dart' if (dart.library.js_interop) 'stt_service_web.dart';
