import 'package:flutter/material.dart';
import 'package:tech_world/diagnostics/diagnostics_service.dart';

/// Toolbar developer-affordance menu for flipping runtime diagnostic toggles.
///
/// Binds to [DiagnosticsService.avEnabled] / [DiagnosticsService.errorLoggingEnabled]
/// via [ValueListenableBuilder] so flips are reflected instantly in the
/// checkmark UI without rebuilding the parent.
///
/// Constructed with the service injected (not located) so widget tests can
/// pass a fake without touching the global [Locator]. Production callers
/// pass `locate<DiagnosticsService>()`.
///
/// **Visibility:** gate the *call site* behind `kDebugMode` rather than
/// embedding the check here — keeps this widget trivially testable in
/// release-mode test runs and lets debug-only inclusion be one grep.
///
/// Spiral F6 from PR #465 review (cage-match): the architecture work
/// (Locator-registered service exposing `ValueListenable<bool>`) landed in
/// #466; this is the UI affordance that closes the loop so a developer
/// can actually flip the toggles from the running app.
class DiagnosticsMenu extends StatelessWidget {
  const DiagnosticsMenu({super.key, required this.diagnostics});

  final DiagnosticsService diagnostics;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: diagnostics.avEnabled,
      builder: (context, avOn, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: diagnostics.errorLoggingEnabled,
          builder: (context, errOn, _) {
            final anyOn = avOn || errOn;
            return PopupMenuButton<String>(
              tooltip: 'Diagnostics',
              offset: const Offset(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              onSelected: (value) async {
                switch (value) {
                  case 'av':
                    await diagnostics.setAvEnabled(!avOn);
                  case 'err':
                    await diagnostics.setErrorLoggingEnabled(!errOn);
                }
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem<String>(
                  value: 'av',
                  checked: avOn,
                  child: const Text('AV diagnostics'),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'err',
                  checked: errOn,
                  child: const Text('Error logging'),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: anyOn
                      ? Colors.amber.shade300.withValues(alpha: 0.2)
                      : Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.bug_report,
                  color: anyOn ? Colors.amber.shade300 : Colors.white70,
                  size: 20,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
