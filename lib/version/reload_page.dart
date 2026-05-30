// Conditional export — picks the web implementation on JS targets and the
// no-op stub on native. See `feedback_no_dynamic_dispatch` / the project's
// conditional-export pattern in `lib/native/`.
export 'reload_page_stub.dart'
    if (dart.library.js_interop) 'reload_page_web.dart';
