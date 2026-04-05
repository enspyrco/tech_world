import 'package:tech_world/flame/maps/barrier_occlusion.dart';

/// Defines a wall style within a tileset sprite sheet.
///
/// Each style occupies a 10-tile × 2-row block in the sheet. The block
/// contains a full 3×3 autotile set: cap tiles (decorative top) and face
/// tiles (plain wall surface), with variants for corners, edges, fills,
/// and isolated segments.
///
/// ## Block layout
///
/// ```
/// Row 0: TL(0) T(1)  TR(2) LR(3) L(4) fill(5) R(6) L(7) fill(8) R(9)
/// Row 1: BL(0) B(1)  BR(2) BLR(3) _(4) LR(5)  _(6) BL(7) B(8)  BR(9)
/// ```
///
/// - **Set A** (cols 0–6): Cap/top tiles with decorative band.
/// - **Set B** (cols 7–9 × 2 rows): Face tiles — plain surface.
///
/// The 4-bit NESW bitmask from [computeWallBitmask] drives tile selection:
/// - **E/W** → left, middle, or right column
/// - **S** → whether the wall continues south (affects face bottom border)
/// - **N** → determines whether a cap is placed (not which cap)
class WallStyleDef {
  const WallStyleDef({
    required this.id,
    required this.tilesetId,
    required this.baseIndex,
    required this.columns,
  });

  /// Unique style identifier (e.g. `'modern_gray_07'`).
  final String id;

  /// Tileset this style's tiles live in (e.g. `'limezu_walls'`).
  final String tilesetId;

  /// Tile index of the top-left corner (position 0,0) of the 10×2 block.
  final int baseIndex;

  /// Column count of the tileset sheet (for row/col ↔ index conversion).
  final int columns;

  /// Absolute tile index for a position within the 10×2 block.
  int _tileAt(int localCol, int localRow) {
    final baseRow = baseIndex ~/ columns;
    final baseCol = baseIndex % columns;
    return (baseRow + localRow) * columns + (baseCol + localCol);
  }

  /// Cap tile index for a wall cell with the given neighbor [bitmask].
  ///
  /// Cap tiles sit at y-1 above a north-facing wall. Selection depends
  /// only on E/W neighbors — N and S are ignored.
  int capForBitmask(int bitmask) {
    final hasE = bitmask & WallBitmask.e != 0;
    final hasW = bitmask & WallBitmask.w != 0;

    if (hasE && hasW) return _tileAt(1, 0); // middle
    if (hasE) return _tileAt(0, 0); // left end
    if (hasW) return _tileAt(2, 0); // right end
    return _tileAt(3, 0); // isolated
  }

  /// Face tile index for a wall cell with the given neighbor [bitmask].
  ///
  /// Selection depends on E/W (left/mid/right) and S (bottom border).
  /// N is ignored — it determines cap placement, not face selection.
  int faceForBitmask(int bitmask) {
    final hasE = bitmask & WallBitmask.e != 0;
    final hasW = bitmask & WallBitmask.w != 0;
    final hasS = bitmask & WallBitmask.s != 0;

    if (hasE && hasW) return hasS ? _tileAt(8, 0) : _tileAt(8, 1);
    if (hasE) return hasS ? _tileAt(7, 0) : _tileAt(7, 1);
    if (hasW) return hasS ? _tileAt(9, 0) : _tileAt(9, 1);
    return hasS ? _tileAt(5, 1) : _tileAt(3, 1); // isolated
  }
}

// ---------------------------------------------------------------------------
// Wall style registry
// ---------------------------------------------------------------------------

/// The wall tileset ID used by all LimeZu wall styles.
const wallTilesetId = 'limezu_walls';

/// Column count of the repacked LimeZu wall sheet (30 cols at 32px).
const _wallSheetColumns = 30;

/// Default wall style — clean light gray (#7 in the catalog).
const defaultWallStyleId = 'modern_gray_07';

/// All 54 LimeZu wall styles, keyed by style ID.
///
/// Styles are arranged in the repacked 30-column sheet as 3 groups of 10
/// columns across, with each style occupying 2 rows.
final Map<String, WallStyleDef> _wallStyles = _buildWallStyles();

Map<String, WallStyleDef> _buildWallStyles() {
  // Style names — 3 per row-pair (group 0, 1, 2), 18 row-pairs + extras.
  // Names are descriptive based on the catalog colors.
  const styleNames = <String>[
    // Row 0-1
    'diamond_wallpaper', 'warm_wood', 'coral_red',
    // Row 2-3
    'off_white', 'rustic_brown', 'dark_rose',
    // Row 4-5
    'modern_gray_07', 'striped_brown', 'lavender',
    // Row 6-7
    'cream', 'mahogany', 'cool_steel',
    // Row 8-9
    'warm_beige', 'mahogany_dark', 'sky_blue',
    // Row 10-11
    'sage_green', 'charcoal_brown', 'teal_check',
    // Row 12-13
    'olive_cream', 'cedar', 'deep_teal',
    // Row 14-15
    'khaki', 'walnut', 'powder_blue',
    // Row 16-17
    'golden_beige', 'burgundy', 'ice_blue',
    // Row 18-19
    'sunflower', 'espresso', 'mint',
    // Row 20-21
    'lemon', 'terracotta', 'muted_sage',
    // Row 22-23
    'sandstone', 'dark_cocoa', 'golden_stripe',
    // Row 24-25
    'mocha', 'oxblood', 'forest_green',
    // Row 26-27
    'driftwood', 'dusty_rose', 'forest_green_alt',
    // Row 28-29
    'tan_brick', 'peach', 'spring_green',
    // Row 30-31
    'slate', 'periwinkle', 'baby_blue',
    // Row 32-33
    'dark_slate', 'cherry_red', 'light_sky',
    // Row 34-35
    'charcoal', 'royal_blue', /* group 2 empty */
    // Row 36-37
    /* group 0 empty */ 'purple', /* group 2 empty */
  ];

  final styles = <String, WallStyleDef>{};
  var styleIndex = 0;

  for (var rowPair = 0; rowPair < 20; rowPair++) {
    for (var group = 0; group < 3; group++) {
      if (styleIndex >= styleNames.length) break;

      final name = styleNames[styleIndex];
      if (name.isEmpty) {
        styleIndex++;
        continue;
      }

      final baseRow = rowPair * 2;
      final baseCol = group * 10;
      final baseIndex = baseRow * _wallSheetColumns + baseCol;

      styles[name] = WallStyleDef(
        id: name,
        tilesetId: wallTilesetId,
        baseIndex: baseIndex,
        columns: _wallSheetColumns,
      );

      styleIndex++;
    }
  }

  return styles;
}

/// Look up a wall style by ID.
///
/// Returns `null` if the style is not found. Legacy `'gray_brick'` IDs
/// are mapped to the default style.
WallStyleDef? lookupWallStyle(String styleId) {
  if (styleId == 'gray_brick') return _wallStyles[defaultWallStyleId];
  return _wallStyles[styleId];
}
