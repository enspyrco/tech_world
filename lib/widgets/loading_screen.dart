import 'package:flutter/material.dart';

/// A loading screen that displays during app initialization.
/// Matches the web loading screen design with dark theme and progress indicator.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({
    super.key,
    this.message = 'Loading...',
    this.progress,
  });

  /// The message to display below the progress indicator.
  final String message;

  /// Optional progress value between 0.0 and 1.0.
  /// If null, shows an indeterminate progress indicator.
  final double? progress;

  // Tech World brand colors
  static const _backgroundColor = Color(0xFF1a1a2e);
  static const _progressColor = Color(0xFF4ade80);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _backgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Tech World',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(_progressColor),
                  minHeight: 4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.5),
                decoration: TextDecoration.none,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
