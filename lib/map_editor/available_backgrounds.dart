/// A selectable background image for the map editor.
class BackgroundOption {
  const BackgroundOption({required this.label, required this.filename});

  /// Display name shown in the dropdown.
  final String label;

  /// Filename relative to `assets/images/` (e.g. `'single_room.png'`).
  final String filename;
}

/// Background images available in the map editor dropdown.
///
/// Add new composed backgrounds here — they will be auto-preloaded
/// by [TechWorldGame] and selectable in the editor toolbar.
const availableBackgrounds = [
  BackgroundOption(label: 'Single Room', filename: 'single_room.png'),
];
