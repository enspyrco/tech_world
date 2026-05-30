/// Web implementation: reports `'web'` and the browser's userAgent string.
library;

import 'package:web/web.dart' as web;

String agentHelloPlatform() => 'web';

String? agentHelloUserAgent() {
  try {
    return web.window.navigator.userAgent;
  } catch (_) {
    // Defensive — userAgent should always be present, but a sandboxed iframe
    // or freezing browser shouldn't crash the connect path.
    return null;
  }
}
