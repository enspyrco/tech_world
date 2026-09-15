import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flame/image_composition.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:tech_world/avatar/avatar_spec.dart';

final _log = Logger('AvatarComposer');

/// Width of a character sheet in pixels: 16 cells of 32.
///
/// 12 walk cells (4 direction strips x 3 frames) followed by a 4-cell wave
/// strip — see `player_component.dart:_buildAnimations`. The wave cells are
/// the part of the contract most easily missed: a part authored as "3 frames,
/// 4 strips" is only 384 wide, and a character composed from it would lose the
/// wave emote entirely. [_assertSheetContract] names that in its message.
const int kSheetWidth = 512;

/// Height of a character sheet in pixels — one row, 64 tall.
const int kSheetHeight = 64;

/// Composes [AvatarSpec]s into single sprite sheets and shares the results
/// between everyone displaying the same character.
///
/// ## Why refcounting rather than a plain cache
///
/// Two peers wearing the same parts must render from **one** composed image —
/// otherwise a room of twenty identically-dressed players holds twenty copies
/// of the same 512x64 texture. Sharing means the image outlives any single
/// holder, so its lifetime is owned by the count of live holders, not by
/// whoever happened to ask first: when one of two peers leaves, the image must
/// survive for the other. That is the whole reason [acquire] and [release]
/// exist as a pair instead of a `getImage()`.
///
/// ## The invariant that decides every eviction
///
/// **A referenced image is never evicted.** LRU pressure only ever chooses
/// among entries at refcount 0. If the cache is over capacity and *every*
/// entry is still referenced, it grows past [maxCached] and logs rather than
/// disposing an image someone is still drawing with — an over-cap cache costs
/// memory, whereas rendering from a disposed `ui.Image` is a crash. The fail
/// direction is not symmetric, so the policy isn't either.
///
/// Entries at refcount 0 are *kept*, not dropped: a peer who walks out of
/// range and back, or a player toggling between two outfits in the picker,
/// should hit a warm cache. Refcount 0 means "evictable", never "dead".
class AvatarComposer {
  AvatarComposer({
    required ui.Image Function(String asset) loadImage,
    this.maxCached = 32,
  }) : _loadImage = loadImage;

  final ui.Image Function(String asset) _loadImage;

  /// Soft cap on retained composed images. Soft because the no-evictable-entry
  /// case above is allowed to exceed it.
  final int maxCached;

  /// Insertion-ordered so the first evictable entry encountered is the least
  /// recently used. [acquire] re-inserts on hit to move an entry to the young
  /// end.
  final LinkedHashMap<AvatarSpec, _Entry> _entries = LinkedHashMap();

  /// Number of retained composed images, referenced or not.
  int get cachedCount => _entries.length;

  /// Live holders of [spec], or 0 if it isn't cached.
  @visibleForTesting
  int refCountOf(AvatarSpec spec) => _entries[spec]?.refCount ?? 0;

  /// Take a reference on the composed sheet for [spec], composing it if this
  /// is the first holder.
  ///
  /// Every call must be paired with exactly one [release]. The returned image
  /// belongs to the composer — callers draw with it and must not dispose it.
  ui.Image acquire(AvatarSpec spec) {
    final existing = _entries.remove(spec);
    if (existing != null) {
      // Re-insert to mark as most recently used.
      existing.refCount++;
      _entries[spec] = existing;
      return existing.image;
    }

    final entry = _Entry(_compose(spec))..refCount = 1;
    _entries[spec] = entry;
    _evictDownToCap();
    return entry.image;
  }

  /// Drop a reference taken by [acquire].
  ///
  /// At zero the image is retained as an eviction candidate, not disposed —
  /// see the class doc. Releasing something never acquired is a no-op that
  /// logs, because the alternative (throwing during a teardown path) would
  /// turn a bookkeeping slip into a crash while a player is leaving a room.
  void release(AvatarSpec spec) {
    final entry = _entries[spec];
    if (entry == null) {
      _log.warning('release() for a spec that is not cached: $spec');
      return;
    }
    if (entry.refCount == 0) {
      _log.warning('release() below zero for $spec — unbalanced acquire');
      return;
    }
    entry.refCount--;
    if (entry.refCount == 0) {
      _evictDownToCap();
    }
  }

  /// Dispose every composed image. Call on world teardown.
  void clear() {
    for (final entry in _entries.values) {
      entry.image.dispose();
    }
    _entries.clear();
  }

  /// Evict least-recently-used **unreferenced** entries until at or under
  /// [maxCached]. Stops early when nothing is evictable.
  void _evictDownToCap() {
    if (_entries.length <= maxCached) return;

    final evictable = _entries.entries
        .where((e) => e.value.refCount == 0)
        .map((e) => e.key)
        .toList();

    var over = _entries.length - maxCached;
    for (final spec in evictable) {
      if (over <= 0) break;
      _entries.remove(spec)!.image.dispose();
      over--;
    }

    if (over > 0) {
      _log.fine(
        'Avatar cache over cap by $over with no evictable entries — every '
        'composed sheet is still referenced. Growing rather than disposing a '
        'sheet in use.',
      );
    }
  }

  /// Draw every contributing part into one sheet, in paint order.
  ///
  /// A single-part spec is composed rather than short-circuited to the source
  /// image on purpose: the returned image is owned by this cache and disposed
  /// on eviction, and the source belongs to Flame's image cache. Handing back
  /// a borrowed image would mean disposing something the rest of the game is
  /// still using.
  ui.Image _compose(AvatarSpec spec) {
    final composition = ImageComposition();
    for (final part in spec.parts.layers) {
      final image = _loadImage(part.asset!);
      _assertSheetContract(part.asset!, image);
      composition.add(image, Vector2.zero());
    }
    return composition.composeSync();
  }

  void _assertSheetContract(String asset, ui.Image image) {
    if (image.width == kSheetWidth && image.height == kSheetHeight) return;
    throw StateError(
      'Avatar part "$asset" is ${image.width}x${image.height}, expected '
      '${kSheetWidth}x$kSheetHeight. A sheet is 16 cells of 32x64: 12 walk '
      '(4 direction strips x 3 frames) then a 4-cell wave strip. A part '
      'authored as 4 strips of 3 frames only is 384 wide and is missing its '
      'wave frames.',
    );
  }
}

class _Entry {
  _Entry(this.image);

  final ui.Image image;
  int refCount = 0;
}
