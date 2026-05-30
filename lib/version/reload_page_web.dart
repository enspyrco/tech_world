import 'package:web/web.dart' as web;

/// Web implementation of [reloadPage] — triggers a full browser reload so
/// the user picks up the freshly-deployed bundle.
void reloadPage() {
  web.window.location.reload();
}
