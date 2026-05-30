import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'reload_page.dart';

/// A subtle amber banner that appears at the top of the app when
/// [updateAvailable] flips to true and stays up until the user either hits
/// "Refresh" (full page reload) or "Dismiss" (hides for the rest of this
/// session — re-appears on next app start).
///
/// We use a plain [Container] rather than [MaterialBanner] / [SnackBar] so
/// the banner stacks above the existing toolbar without depending on the
/// [ScaffoldMessenger] queue (which is already used for room-action
/// feedback elsewhere in the app).
class UpdateAvailableBanner extends StatefulWidget {
  const UpdateAvailableBanner({
    super.key,
    required this.updateAvailable,
  });

  final ValueListenable<bool> updateAvailable;

  @override
  State<UpdateAvailableBanner> createState() => _UpdateAvailableBannerState();
}

class _UpdateAvailableBannerState extends State<UpdateAvailableBanner> {
  /// Per-session dismissal flag. Resets on next app start (rebuild) by
  /// virtue of being state on this widget.
  final ValueNotifier<bool> _dismissed = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _dismissed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.updateAvailable,
      builder: (context, available, _) {
        if (!available) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: _dismissed,
          builder: (context, dismissed, _) {
            if (dismissed) return const SizedBox.shrink();
            return Material(
              color: Colors.transparent,
              child: Container(
                width: double.infinity,
                color: const Color(0xFFFFF3CD), // soft amber
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Color(0xFF8A6D3B),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'A new version is available. Refresh to update.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF8A6D3B),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: reloadPage,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF8A6D3B),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('Refresh'),
                    ),
                    IconButton(
                      tooltip: 'Dismiss',
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: Color(0xFF8A6D3B),
                      ),
                      onPressed: () => _dismissed.value = true,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
