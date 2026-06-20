/// Cross-platform alarm sound for the shared timer.
///
/// Conditional export — the web implementation uses the Web Audio API (a short
/// three-beep oscillator burst, WASM-safe via `package:web`), the native stub
/// uses `SystemSound.alert`. No audio package, no bundled asset: the simplest
/// path that works on `flutter build web --wasm` (the production target).
///
/// See the project's conditional-export pattern in `lib/native/` and
/// `lib/version/reload_page.dart`.
library;

export 'alarm_player_stub.dart'
    if (dart.library.js_interop) 'alarm_player_web.dart';
