// Platform-aware TTS service.
//
// Exports the appropriate implementation based on platform:
// - On web: Uses browser's speechSynthesis API
// - On native: Uses a no-op stub

export 'tts_service_stub.dart' if (dart.library.js_interop) 'tts_service_web.dart';
