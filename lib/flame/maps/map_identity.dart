import 'package:flutter/material.dart';

/// Visual identity for predefined maps — icon and accent color.
///
/// Matches by map ID first (predefined maps in the dropdown), then falls back
/// to name substring matching (Firestore rooms in the browser). This means
/// user-created rooms with matching names (e.g. "My Arena") inherit the
/// corresponding icon, which is intentional.
class MapIdentity {
  const MapIdentity._({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  /// Default identity for unrecognized maps.
  static const _fallback = MapIdentity._(
    icon: Icons.map,
    color: Color(0xFF90A4AE),
  );

  static const _byId = <String, MapIdentity>{
    'l_room': MapIdentity._(
      icon: Icons.auto_awesome,
      color: Color(0xFFFFD54F),
    ),
    'open_arena': MapIdentity._(
      icon: Icons.crop_free,
      color: Color(0xFF81C784),
    ),
    'four_corners': MapIdentity._(
      icon: Icons.grid_4x4,
      color: Color(0xFFE57373),
    ),
    'simple_maze': MapIdentity._(
      icon: Icons.route,
      color: Color(0xFFBA68C8),
    ),
    'the_library': MapIdentity._(
      icon: Icons.menu_book,
      color: Color(0xFF4DD0E1),
    ),
    'the_workshop': MapIdentity._(
      icon: Icons.construction,
      color: Color(0xFFFFB74D),
    ),
    'wizards_tower': MapIdentity._(
      icon: Icons.auto_fix_high,
      color: Color(0xFFCE93D8),
    ),
  };

  /// Name substrings for fallback matching (Firestore rooms).
  static const _byNameSubstring = <String, String>{
    'imagination': 'l_room',
    'l-room': 'l_room',
    'arena': 'open_arena',
    'corner': 'four_corners',
    'maze': 'simple_maze',
    'library': 'the_library',
    'workshop': 'the_workshop',
    'wizard': 'wizards_tower',
    'tower': 'wizards_tower',
  };

  /// Look up map identity by ID (preferred) or name (fallback).
  static MapIdentity of({String? id, String? name}) {
    if (id != null) {
      final match = _byId[id];
      if (match != null) return match;
    }
    if (name != null) {
      final lower = name.toLowerCase();
      for (final entry in _byNameSubstring.entries) {
        if (lower.contains(entry.key)) {
          return _byId[entry.value]!;
        }
      }
    }
    return _fallback;
  }
}
