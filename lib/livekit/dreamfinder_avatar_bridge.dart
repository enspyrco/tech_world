// Platform-aware Dreamfinder avatar bridge.
//
// Exports the appropriate implementation based on platform:
// - On web: Creates same-origin iframe with 3D avatar, forwards data channels
// - On native: Uses a no-op stub

export 'dreamfinder_avatar_bridge_stub.dart'
    if (dart.library.js_interop) 'dreamfinder_avatar_bridge_web.dart';
