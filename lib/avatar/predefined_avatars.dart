import 'avatar.dart';

/// The set of avatars available for player selection.
const predefinedAvatars = [
  Avatar(id: 'npc11', displayName: 'Explorer', spriteAsset: 'NPC11.png'),
  Avatar(id: 'npc12', displayName: 'Ranger', spriteAsset: 'NPC12.png'),
  Avatar(id: 'npc13', displayName: 'Scholar', spriteAsset: 'NPC13.png'),
];

/// The set of sprite-asset strings drawn from [predefinedAvatars].
///
/// Lifted to a top-level `final` so the wire-parse whitelist gate
/// (`AvatarUpdate.tryParse` in `lib/livekit/livekit_service.dart`)
/// doesn't rebuild it on every avatar broadcast. Cheap today (3 entries),
/// but the gate is on the hot path of every avatar update from every peer.
final Set<String> predefinedAvatarSpriteAssets = {
  for (final avatar in predefinedAvatars) avatar.spriteAsset,
};

/// The fallback avatar, matching the previously hardcoded NPC11 sprite.
const defaultAvatar = Avatar(
  id: 'npc11',
  displayName: 'Explorer',
  spriteAsset: 'NPC11.png',
);

/// Look up a predefined avatar by [id]. Returns `null` if not found.
Avatar? avatarById(String? id) {
  if (id == null) return null;
  for (final avatar in predefinedAvatars) {
    if (avatar.id == id) return avatar;
  }
  return null;
}
