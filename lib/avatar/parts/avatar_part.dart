/// One layer of a composed character.
///
/// The four slot enums below all implement this so [AvatarComposer] can walk
/// them uniformly without knowing which slot it is holding. A slot's `none`
/// value is a real part with a null [asset] — the composer skips it rather
/// than the caller having to filter nulls at four separate sites.
abstract interface class AvatarPart {
  /// Stable identifier used on the wire and in Firestore. Never
  /// `enum.name` — see the enhanced-enum rule in CLAUDE.md.
  String get wireName;

  /// Sprite-sheet filename under `assets/images/`, or `null` for an empty
  /// slot. Every non-null asset must satisfy the 512×64 sheet contract
  /// asserted in [AvatarComposer].
  String? get asset;

  /// Paint order, low to high. Layers with a larger [zPos] are drawn on top.
  int get zPos;
}

/// Paint order for the four slots.
///
/// Spaced by 10 so a future slot (a back-layer cape, a front-layer held item)
/// can be inserted without renumbering the ones already persisted in player
/// profiles. The values are only ever compared, never stored.
abstract final class ZPos {
  static const int body = 0;
  static const int outfit = 10;
  static const int hair = 20;
  static const int accessory = 30;
}

/// The base character: skin, face, and the walk/wave animation itself.
///
/// The only slot with no `none` — a character without a body has nothing to
/// animate, so the type makes that unrepresentable rather than defending
/// against it at render time.
///
/// The three values are today's shipping presets, which are *whole* character
/// sheets rather than isolated bodies. That is a content fact, not a structural
/// one: the composer treats them exactly as it will treat a real body part, so
/// when authored parts land (OV2, still open) they join this enum and nothing
/// downstream changes. Composing a single layer is the degenerate case of the
/// same operation, which is why the substrate is worth having before the art.
enum BodyId implements AvatarPart {
  npc11('npc11', 'NPC11.png'),
  npc12('npc12', 'NPC12.png'),
  npc13('npc13', 'NPC13.png'),
  ;

  const BodyId(this.wireName, this.asset);

  @override
  final String wireName;

  @override
  final String asset;

  @override
  int get zPos => ZPos.body;

  /// The body used when a wire value is unknown or absent. Matches the
  /// historical hardcoded NPC11 sprite.
  static const BodyId fallback = BodyId.npc11;

  static BodyId? parse(String wire) {
    for (final id in values) {
      if (id.wireName == wire) return id;
    }
    return null;
  }

  /// The body drawn from [asset], or null if no body uses that sheet.
  ///
  /// The bridge from the legacy string API: a component still holding a
  /// sprite-asset filename asks whether that sheet is a composable character.
  /// Bot sheets answer null and keep their existing render path. Goes away
  /// with the string `Avatar` type in step 1.5.
  static BodyId? forAsset(String asset) {
    for (final id in values) {
      if (id.asset == asset) return id;
    }
    return null;
  }
}

/// Hair, drawn over the outfit so a collar doesn't clip long hair.
enum HairId implements AvatarPart {
  none('hair_none', null),
  ;

  const HairId(this.wireName, this.asset);

  @override
  final String wireName;

  @override
  final String? asset;

  @override
  int get zPos => ZPos.hair;

  static HairId? parse(String wire) {
    for (final id in values) {
      if (id.wireName == wire) return id;
    }
    return null;
  }
}

/// Clothing, drawn over the body and under the hair.
enum OutfitId implements AvatarPart {
  none('outfit_none', null),
  ;

  const OutfitId(this.wireName, this.asset);

  @override
  final String wireName;

  @override
  final String? asset;

  @override
  int get zPos => ZPos.outfit;

  static OutfitId? parse(String wire) {
    for (final id in values) {
      if (id.wireName == wire) return id;
    }
    return null;
  }
}

/// Held or worn extras — the cane NPC13 already carries is this slot, proving
/// it is native to the house style rather than a speculative addition (see
/// `docs/crucible/character-maker/step0/FINDINGS.md`).
enum AccessoryId implements AvatarPart {
  none('accessory_none', null),
  ;

  const AccessoryId(this.wireName, this.asset);

  @override
  final String wireName;

  @override
  final String? asset;

  @override
  int get zPos => ZPos.accessory;

  static AccessoryId? parse(String wire) {
    for (final id in values) {
      if (id.wireName == wire) return id;
    }
    return null;
  }
}
