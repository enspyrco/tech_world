import 'package:flutter/widgets.dart';

/// Native stub — there is no GIS-rendered button off the web, so render
/// nothing. Native platforms use the auth gate's own button + the
/// `GoogleSignIn.instance.authenticate()` flow instead.
///
/// Returns an empty box; callers only mount this when `kIsWeb` is true.
Widget googleSignInButton() => const SizedBox.shrink();
