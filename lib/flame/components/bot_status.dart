import 'package:flutter/foundation.dart';

/// Status of the Claude bot for UI display.
enum BotStatus {
  /// Bot is idle/sleeping - shows "zzz" indicator
  idle,

  /// Bot is thinking/processing - shows animated bouncing dots
  thinking,
}

/// Global notifier for bot status changes.
/// UI components can listen to this to update their display.
final botStatusNotifier = ValueNotifier<BotStatus>(BotStatus.idle);
