/// Status of the Claude bot for UI display.
///
/// Owned by [ChatService] — access via `chatService.botStatus`.
enum BotStatus {
  /// Bot is not present in the LiveKit room.
  absent,

  /// Bot is idle/sleeping - shows "zzz" indicator
  idle,

  /// Bot is thinking/processing - shows animated bouncing dots
  thinking,
}
