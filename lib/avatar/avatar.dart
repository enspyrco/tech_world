/// Represents a selectable player avatar with its sprite asset.
class Avatar {
  const Avatar({
    required this.id,
    required this.displayName,
    required this.spriteAsset,
  });

  /// Unique identifier for this avatar.
  final String id;

  /// Human-readable name shown in the selection UI.
  final String displayName;

  /// Filename of the sprite sheet in `assets/images/`.
  final String spriteAsset;

  /// Deserialize from a JSON map (Firestore / LiveKit data channel).
  factory Avatar.fromJson(Map<String, dynamic> json) {
    return Avatar(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      spriteAsset: json['spriteAsset'] as String,
    );
  }

  /// Serialize to a JSON map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'spriteAsset': spriteAsset,
      };

  @override
  bool operator ==(Object other) => other is Avatar && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Avatar($id, $displayName)';
}
