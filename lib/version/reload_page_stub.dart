/// Native stub for [reloadPage] — does nothing.
///
/// On non-web platforms there's no `window.location.reload()` equivalent;
/// the user has to relaunch the app. We surface the banner regardless so
/// they at least know a new version exists, but the "Refresh" button is a
/// no-op on native. (In practice the version check only runs against a
/// versioned web bundle anyway.)
void reloadPage() {}
