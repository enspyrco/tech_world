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
    this.spriteSheetAsset,
    this.spriteFrameCount = 3,
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

  /// Optional sprite sheet for animated walk cycles.
  /// When set, the bot uses [PlayerComponent] instead of
  /// [BotCharacterComponent] for animated movement.
  final String? spriteSheetAsset;

  /// Number of animation frames per direction in the sprite sheet.
  final int spriteFrameCount;
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

/// Dreamfinder — voice-interactive imagination facilitator (gold).
const dreamfinderBot = BotConfig(
  identity: 'bot-dreamfinder',
  displayName: 'Dreamfinder',
  spriteAsset: 'dreamfinder_bot.png',
  accentColor: Color(0xFFDAA520),
  avatarLetter: 'D',
  spriteSheetAsset: 'dreamfinder_bot_sheet.png',
  spriteFrameCount: 4,
);

/// All registered bots, keyed by participant identity.
final botsByIdentity = <String, BotConfig>{
  clawdBot.identity: clawdBot,
  gremlinBot.identity: gremlinBot,
  dreamfinderBot.identity: dreamfinderBot,
};

/// All bot identities as a set, for efficient lookups.
final allBotIdentities = botsByIdentity.keys.toSet();

/// Returns `true` if [identity] belongs to a registered bot.
///
/// Also matches `agent-` prefixed identities from the `@livekit/agents`
/// SDK, which assigns identities like `agent-{jobId}` when the worker
/// doesn't override the identity via `requestFunc`.
bool isBotIdentity(String identity) =>
    botsByIdentity.containsKey(identity) || identity.startsWith('agent-');

/// Returns `true` if [identity] belongs to Dreamfinder, including the
/// auto-generated `agent-*` identities used by the LiveKit agents SDK.
bool isDreamfinderIdentity(String identity) =>
    getBotConfig(identity) == dreamfinderBot;

/// Returns the [BotConfig] for [identity], or [clawdBot] as fallback.
///
/// Identities starting with `agent-` are mapped to [dreamfinderBot],
/// since only Dreamfinder uses the `@livekit/agents` SDK directly.
BotConfig getBotConfig(String identity) =>
    botsByIdentity[identity] ??
    (identity.startsWith('agent-') ? dreamfinderBot : clawdBot);
