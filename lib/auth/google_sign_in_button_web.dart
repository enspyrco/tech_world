import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// Renders the official Google Identity Services sign-in button.
///
/// `GoogleSignIn.instance.initialize(...)` must have been called first (the
/// auth gate does this in `initState` before subscribing to
/// `authenticationEvents`). When the user clicks the button, GIS runs its
/// popup / FedCM flow and emits a `GoogleSignInAuthenticationEvent` on
/// `authenticationEvents`, which the auth gate forwards to Firebase.
Widget googleSignInButton() => web.renderButton(
      configuration: web.GSIButtonConfiguration(
        theme: web.GSIButtonTheme.outline,
        size: web.GSIButtonSize.large,
        text: web.GSIButtonText.signinWith,
        shape: web.GSIButtonShape.rectangular,
        logoAlignment: web.GSIButtonLogoAlignment.left,
      ),
    );
