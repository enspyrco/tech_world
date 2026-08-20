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
/// Holds two kinds of value while the migration finishes: three legacy sheets
/// that are whole dressed characters, and real bare bodies from the part
/// pipeline. The composer cannot tell them apart — a legacy sheet is just a
/// spec whose only layer happens to include clothes — which is what makes
/// keeping both safe rather than a special case.
enum BodyId implements AvatarPart {
  // Legacy whole-character sheets. These predate the part pipeline: each is a
  // fully-dressed character rather than a bare body, kept so existing profiles
  // (which store `npc11` and friends) keep rendering the person they chose.
  // Retire them once a parts combination can reproduce each one.
  npc11('npc11', 'NPC11.png'),
  npc12('npc12', 'NPC12.png'),
  npc13('npc13', 'NPC13.png'),

  // Real bodies, extracted by tool/extract_character_parts.py. Bare skin plus
  // the face that the source art draws into the body layer, so they need an
  // outfit to be dressed.
  body01('body_01', 'parts/body/body_01.png'),
  body03('body_03', 'parts/body/body_03.png'),
  body05('body_05', 'parts/body/body_05.png'),
  body07('body_07', 'parts/body/body_07.png'),
  body09('body_09', 'parts/body/body_09.png'),
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
  hair01c01('hair_01_c01', 'parts/hair/hair_01_c01.png'),
  hair01c04('hair_01_c04', 'parts/hair/hair_01_c04.png'),
  hair02c02('hair_02_c02', 'parts/hair/hair_02_c02.png'),
  hair02c06('hair_02_c06', 'parts/hair/hair_02_c06.png'),
  hair03c01('hair_03_c01', 'parts/hair/hair_03_c01.png'),
  hair04c03('hair_04_c03', 'parts/hair/hair_04_c03.png'),
  hair05c05('hair_05_c05', 'parts/hair/hair_05_c05.png'),
  hair06c02('hair_06_c02', 'parts/hair/hair_06_c02.png'),
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
  outfit01c01('outfit_01_c01', 'parts/outfit/outfit_01_c01.png'),
  outfit02c01('outfit_02_c01', 'parts/outfit/outfit_02_c01.png'),
  outfit03c02('outfit_03_c02', 'parts/outfit/outfit_03_c02.png'),
  outfit05c01('outfit_05_c01', 'parts/outfit/outfit_05_c01.png'),
  outfit07c03('outfit_07_c03', 'parts/outfit/outfit_07_c03.png'),
  outfit09c02('outfit_09_c02', 'parts/outfit/outfit_09_c02.png'),
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
  backpack('accessory_backpack', 'parts/accessory/accessory_backpack.png'),
  glasses('accessory_glasses', 'parts/accessory/accessory_glasses.png'),
  snapback('accessory_snapback', 'parts/accessory/accessory_snapback.png'),
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

/// Every part asset the game can composite, deduplicated.
///
/// Flame's image cache is populated by an explicit `loadAll`, and
/// [AvatarComposer] reads through `fromCache` — so a part that isn't in this
/// list throws at the moment a player first wears it, which is exactly the
/// kind of failure that only shows up for the one person who picked it.
/// Deriving the list from the enums means adding a part cannot forget it.
Set<String> get allPartAssets => <AvatarPart>[
      ...BodyId.values,
      ...HairId.values,
      ...OutfitId.values,
      ...AccessoryId.values,
    ].map((p) => p.asset).whereType<String>().toSet();
