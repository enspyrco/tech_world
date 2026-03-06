import 'dart:ui';

/// Configuration for a bot character in Tech World.
///
/// Each bot has a unique LiveKit participant identity, display name, sprite
/// asset, and accent color used throughout the UI.
class BotConfig {
  const BotConfig({
    required this.identity,
    required this.displayName,
    required this.spriteAsset,
    required this.accentColor,
    required this.avatarLetter,
  });

  /// LiveKit participant identity (e.g. 'bot-claude', 'bot-gremlin').
  final String identity;

  /// Human-readable display name (e.g. 'Clawd', 'Gremlin').
  final String displayName;

  /// Asset filename for the bot's sprite (loaded from assets/images/).
  final String spriteAsset;

  /// Accent color for UI elements (avatars, badges, borders).
  final Color accentColor;

  /// Single character shown in avatar circles.
  final String avatarLetter;
}

/// Clawd — friendly coding tutor (orange).
const clawdBot = BotConfig(
  identity: 'bot-claude',
  displayName: 'Clawd',
  spriteAsset: 'claude_bot.png',
  accentColor: Color(0xFFD97757),
  avatarLetter: 'C',
);

/// Gremlin — chaotic hype creature (purple).
const gremlinBot = BotConfig(
  identity: 'bot-gremlin',
  displayName: 'Gremlin',
  spriteAsset: 'gremlin_bot.png',
  accentColor: Color(0xFF7B68EE),
  avatarLetter: 'G',
);

/// All registered bots, keyed by participant identity.
final botsByIdentity = <String, BotConfig>{
  clawdBot.identity: clawdBot,
  gremlinBot.identity: gremlinBot,
};

/// All bot identities as a set, for efficient lookups.
final allBotIdentities = botsByIdentity.keys.toSet();

/// Returns `true` if [identity] belongs to a registered bot.
bool isBotIdentity(String identity) => botsByIdentity.containsKey(identity);

/// Returns the [BotConfig] for [identity], or [clawdBot] as fallback.
BotConfig getBotConfig(String identity) =>
    botsByIdentity[identity] ?? clawdBot;
