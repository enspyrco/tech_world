import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// A single, stable button configuration.
///
/// `renderButton()` (google_sign_in_web 1.1.3) builds its GIS `<div>` inside a
/// `FutureBuilder` keyed on `configuration.hashCode`, and
/// `GSIButtonConfiguration` uses *identity* hashCode. Allocating a fresh config
/// on every `build()` would therefore hand the FutureBuilder a new key each
/// time and remount the GIS button on every unrelated `AuthGate` rebuild
/// (error banner animating, `isLoading` toggling, …). Hoisting one instance
/// keeps the key — and the rendered button — stable.
final _config = web.GSIButtonConfiguration(
  theme: web.GSIButtonTheme.outline,
  size: web.GSIButtonSize.large,
  text: web.GSIButtonText.signinWith,
  shape: web.GSIButtonShape.rectangular,
  logoAlignment: web.GSIButtonLogoAlignment.left,
);

/// Renders the official Google Identity Services sign-in button.
///
/// `GoogleSignIn.instance.initialize(...)` must have been called first (the
/// auth gate does this in `initState` before subscribing to
/// `authenticationEvents`). When the user clicks the button, GIS runs its
/// popup / FedCM flow and emits a `GoogleSignInAuthenticationEvent` on
/// `authenticationEvents`, which the auth gate forwards to Firebase.
Widget googleSignInButton() => web.renderButton(configuration: _config);
