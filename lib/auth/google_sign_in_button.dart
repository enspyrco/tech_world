/// Platform-conditional Google sign-in button.
///
/// On **web**, Google Identity Services (GIS) only initiates the interactive
/// sign-in flow from a Google-rendered button — a custom `ElevatedButton`
/// calling `attemptLightweightAuthentication()` can at best surface One Tap,
/// which is routinely suppressed (dismissal cooldown, third-party-cookie /
/// FedCM restrictions). So on web we render the official GIS button via
/// `google_sign_in_web`'s `renderButton()`; clicking it emits a
/// `GoogleSignInAuthenticationEvent` on the `authenticationEvents` stream,
/// which the auth gate already listens to and forwards to Firebase.
///
/// On **native** (iOS / macOS / Android) the GIS button doesn't exist; the
/// stub renders nothing and the auth gate shows its own button wired to
/// `GoogleSignIn.instance.authenticate()`.
///
/// The conditional export keeps the web-only `google_sign_in_web/web_only.dart`
/// import out of native (and VM test) builds — same idiom as the other
/// `dart.library.js_interop` seams in this repo.
library;

export 'google_sign_in_button_stub.dart'
    if (dart.library.js_interop) 'google_sign_in_button_web.dart';
