import 'package:flutter/material.dart';

/// A grid of color swatches representing the 54 LimeZu wall styles.
///
/// Each swatch shows the dominant color of the wall style. Tapping a swatch
/// fires [onStyleSelected] with the style ID. The [selectedStyle] gets a
/// highlight border.
class WallStylePicker extends StatelessWidget {
  const WallStylePicker({
    required this.selectedStyle,
    required this.onStyleSelected,
    super.key,
  });

  final String selectedStyle;
  final ValueChanged<String> onStyleSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 9,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: wallStyleSwatches.length,
      itemBuilder: (context, index) {
        final entry = wallStyleSwatches[index];
        return WallStyleSwatch(
          styleId: entry.id,
          color: entry.color,
          isSelected: entry.id == selectedStyle,
          onTap: () => onStyleSelected(entry.id),
        );
      },
    );
  }
}

/// A single colored swatch representing a wall style.
class WallStyleSwatch extends StatelessWidget {
  const WallStyleSwatch({
    required this.styleId,
    required this.color,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final String styleId;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _displayName(styleId),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? Colors.white : Colors.black26,
              width: isSelected ? 2.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }

  /// Convert style_id to "Style Id" for display.
  static String _displayName(String id) {
    return id.split('_').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');
  }
}

// ---------------------------------------------------------------------------
// Swatch color definitions
// ---------------------------------------------------------------------------

/// A wall style entry with its representative color.
class WallStyleEntry {
  const WallStyleEntry(this.id, this.color);
  final String id;
  final Color color;
}

/// All wall styles with their representative swatch colors.
///
/// Colors are sampled from the face fill tile of each style in the
/// LimeZu Modern Interiors wall sheet. Arranged in sheet order:
/// 3 styles per row-pair, 18 row-pairs + 2 partial.
const wallStyleSwatches = <WallStyleEntry>[
  // Row 0-1
  WallStyleEntry('diamond_wallpaper', Color(0xFFB8D4C8)),
  WallStyleEntry('warm_wood', Color(0xFFC49A5C)),
  WallStyleEntry('coral_red', Color(0xFFD35F5F)),
  // Row 2-3
  WallStyleEntry('off_white', Color(0xFFF0ECE4)),
  WallStyleEntry('rustic_brown', Color(0xFF9C7045)),
  WallStyleEntry('dark_rose', Color(0xFF9C5068)),
  // Row 4-5
  WallStyleEntry('modern_gray_07', Color(0xFFB8B8B8)),
  WallStyleEntry('striped_brown', Color(0xFFA07840)),
  WallStyleEntry('lavender', Color(0xFF9888B8)),
  // Row 6-7
  WallStyleEntry('cream', Color(0xFFE8DCC8)),
  WallStyleEntry('mahogany', Color(0xFF784830)),
  WallStyleEntry('cool_steel', Color(0xFF7898B0)),
  // Row 8-9
  WallStyleEntry('warm_beige', Color(0xFFD0B890)),
  WallStyleEntry('mahogany_dark', Color(0xFF604028)),
  WallStyleEntry('sky_blue', Color(0xFF88B8D8)),
  // Row 10-11
  WallStyleEntry('sage_green', Color(0xFFA8B898)),
  WallStyleEntry('charcoal_brown', Color(0xFF584838)),
  WallStyleEntry('teal_check', Color(0xFF58A8A8)),
  // Row 12-13
  WallStyleEntry('olive_cream', Color(0xFFD0C8A0)),
  WallStyleEntry('cedar', Color(0xFF886848)),
  WallStyleEntry('deep_teal', Color(0xFF388888)),
  // Row 14-15
  WallStyleEntry('khaki', Color(0xFFC0B890)),
  WallStyleEntry('walnut', Color(0xFF786040)),
  WallStyleEntry('powder_blue', Color(0xFFA8C8E0)),
  // Row 16-17
  WallStyleEntry('golden_beige', Color(0xFFD8C090)),
  WallStyleEntry('burgundy', Color(0xFF883848)),
  WallStyleEntry('ice_blue', Color(0xFFC0D8E8)),
  // Row 18-19
  WallStyleEntry('sunflower', Color(0xFFE8C858)),
  WallStyleEntry('espresso', Color(0xFF504030)),
  WallStyleEntry('mint', Color(0xFF90D0B0)),
  // Row 20-21
  WallStyleEntry('lemon', Color(0xFFE8D878)),
  WallStyleEntry('terracotta', Color(0xFFC07850)),
  WallStyleEntry('muted_sage', Color(0xFF98B898)),
  // Row 22-23
  WallStyleEntry('sandstone', Color(0xFFD0B898)),
  WallStyleEntry('dark_cocoa', Color(0xFF483828)),
  WallStyleEntry('golden_stripe', Color(0xFFD0A860)),
  // Row 24-25
  WallStyleEntry('mocha', Color(0xFFA88868)),
  WallStyleEntry('oxblood', Color(0xFF783838)),
  WallStyleEntry('forest_green', Color(0xFF487848)),
  // Row 26-27
  WallStyleEntry('driftwood', Color(0xFFB8A080)),
  WallStyleEntry('dusty_rose', Color(0xFFC89898)),
  WallStyleEntry('forest_green_alt', Color(0xFF386838)),
  // Row 28-29
  WallStyleEntry('tan_brick', Color(0xFFB89878)),
  WallStyleEntry('peach', Color(0xFFE0B898)),
  WallStyleEntry('spring_green', Color(0xFF78C888)),
  // Row 30-31
  WallStyleEntry('slate', Color(0xFF808890)),
  WallStyleEntry('periwinkle', Color(0xFF9898C8)),
  WallStyleEntry('baby_blue', Color(0xFFB0C8E0)),
  // Row 32-33
  WallStyleEntry('dark_slate', Color(0xFF586068)),
  WallStyleEntry('cherry_red', Color(0xFFC84848)),
  WallStyleEntry('light_sky', Color(0xFFC8D8F0)),
  // Row 34-35
  WallStyleEntry('charcoal', Color(0xFF484848)),
  WallStyleEntry('royal_blue', Color(0xFF4868A8)),
  // Row 36-37
  WallStyleEntry('purple', Color(0xFF786898)),
];
