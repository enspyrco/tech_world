/// Native-platform implementation.
///
/// Web safe mode exists to defend the *web* build's world-entry path on old
/// mobile Safari (the iPhone 8 / iOS 16 OOM crash). Native builds don't run the
/// CanvasKit/WebGL web pipeline that OOMs, so they always report `false` and
/// keep full fidelity.
library;

bool requiresWebSafeMode() => false;
