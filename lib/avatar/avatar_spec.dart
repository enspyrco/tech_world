import 'package:tech_world/avatar/parts/avatar_part.dart';

/// A character built from one part per slot.
///
/// Value-equality is load-bearing, not a convenience: this is the cache key in
/// [AvatarComposer], so two peers who picked the same parts must produce
/// equal keys and share one composed image. Identity equality would give every
/// peer their own copy of a byte-identical sheet.
class CompositeAvatar {
  const CompositeAvatar({
    required this.body,
    this.hair = HairId.none,
    this.outfit = OutfitId.none,
    this.accessory = AccessoryId.none,
  });

  /// The three shipping presets, expressed as composites. Same characters the
  /// player already picks from — they simply arrive through the part pipeline
  /// now, which is what makes the pipeline exercised rather than dark.
  static const CompositeAvatar npc11 = CompositeAvatar(body: BodyId.npc11);
  static const CompositeAvatar npc12 = CompositeAvatar(body: BodyId.npc12);
  static const CompositeAvatar npc13 = CompositeAvatar(body: BodyId.npc13);

  static const CompositeAvatar fallback = npc11;

  final BodyId body;
  final HairId hair;
  final OutfitId outfit;
  final AccessoryId accessory;

  /// Parts that actually contribute a layer, in paint order.
  ///
  /// Empty slots are dropped here so the composer never has to reason about
  /// them, and the sort is by [AvatarPart.zPos] rather than by declaration
  /// order so inserting a future slot cannot silently reorder the existing
  /// ones.
  List<AvatarPart> get layers {
    final parts = <AvatarPart>[body, hair, outfit, accessory]
        .where((p) => p.asset != null)
        .toList()
      ..sort((a, b) => a.zPos.compareTo(b.zPos));
    return List.unmodifiable(parts);
  }

  CompositeAvatar copyWith({
    BodyId? body,
    HairId? hair,
    OutfitId? outfit,
    AccessoryId? accessory,
  }) =>
      CompositeAvatar(
        body: body ?? this.body,
        hair: hair ?? this.hair,
        outfit: outfit ?? this.outfit,
        accessory: accessory ?? this.accessory,
      );

  @override
  bool operator ==(Object other) =>
      other is CompositeAvatar &&
      other.body == body &&
      other.hair == hair &&
      other.outfit == outfit &&
      other.accessory == accessory;

  @override
  int get hashCode => Object.hash(body, hair, outfit, accessory);

  @override
  String toString() => 'CompositeAvatar(${body.wireName}, ${hair.wireName}, '
      '${outfit.wireName}, ${accessory.wireName})';
}

/// A player-authored pixel layer on top of [CompositeAvatar].
///
/// Sealed so the render branch is an exhaustive switch: the two variants are
/// composited differently ([OverlayEdit] paints over the live parts,
/// [CanvasEdit] replaces them), and a third variant would fail to compile at
/// every consumer rather than silently falling through to one of them.
///
/// Defined now, exercised in step 3. Nothing constructs these yet — they are
/// here because [AvatarSpec]'s equality has to account for them from the
/// start, and retrofitting an equality contract onto a live cache key is how
/// you get two peers sharing an image that is only equal on its parts.
sealed class PixelEdit {
  const PixelEdit({required this.uid, required this.hash});

  /// Owner of the blob. Half of the storage path; the read gate is
  /// get-by-exact-path, so both halves must travel together.
  final String uid;

  /// SHA-256 of the 131072-byte buffer, verified on receive before the bytes
  /// are ever decoded.
  final String hash;
}

/// A delta painted over the live parts. Changing a part underneath re-renders
/// with the overlay still on top, so "decorate" survives a wardrobe change.
class OverlayEdit extends PixelEdit {
  const OverlayEdit({
    required super.uid,
    required super.hash,
    required this.basePartsHash,
  });

  /// The parts the overlay was drawn against. Recorded so a client can tell
  /// when an overlay is being shown over parts it was never aligned to.
  final String basePartsHash;

  @override
  bool operator ==(Object other) =>
      other is OverlayEdit &&
      other.uid == uid &&
      other.hash == hash &&
      other.basePartsHash == basePartsHash;

  @override
  int get hashCode => Object.hash(uid, hash, basePartsHash);
}

/// A full sheet that replaces the parts entirely — the "make it mine"
/// promotion, which the UI gates behind one confirm because it locks the
/// player out of the part pickers.
class CanvasEdit extends PixelEdit {
  const CanvasEdit({required super.uid, required super.hash});

  @override
  bool operator ==(Object other) =>
      other is CanvasEdit && other.uid == uid && other.hash == hash;

  @override
  int get hashCode => Object.hash(uid, hash);
}

/// The complete description of a player's appearance: parts, plus an optional
/// pixel edit.
///
/// The tier of an edit is part of the key, but not as a term written here:
/// an [OverlayEdit] and a [CanvasEdit] can carry the same uid and hash — the
/// same bytes, promoted from one tier to the other — while rendering
/// completely differently, so a promotion must miss the cache rather than
/// keep showing the old render. That falls out of each subclass's `==`
/// testing `other is <its own type>`, which makes cross-tier equality
/// impossible. DESIGN.md specifies the key as `parts + edit?.hash + edit
/// runtime-type`; comparing whole edit values subsumes both of the last two,
/// and an explicit `runtimeType` term on top was verified redundant by
/// deleting it and watching the promotion test stay green.
class AvatarSpec {
  const AvatarSpec({required this.parts, this.edit});

  const AvatarSpec.preset(CompositeAvatar parts) : this(parts: parts);

  static const AvatarSpec fallback = AvatarSpec(parts: CompositeAvatar.fallback);

  final CompositeAvatar parts;
  final PixelEdit? edit;

  @override
  bool operator ==(Object other) =>
      other is AvatarSpec &&
      other.parts == parts &&
      other.edit == edit;

  @override
  int get hashCode => Object.hash(parts, edit);

  @override
  String toString() =>
      'AvatarSpec($parts${edit == null ? '' : ', ${edit.runtimeType}'})';
}
