import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/generators/map_generator.dart';
import 'package:tech_world/flame/maps/predefined_maps.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/rooms/room_data.dart';
import 'package:tech_world/rooms/room_service.dart';

final _log = Logger('MapSelector');

/// Dropdown for switching the active game map at runtime.
///
/// Shows predefined maps, the user's saved rooms (if [roomService] and
/// [userId] are provided), and procedural generation options.
class MapSelector extends StatefulWidget {
  const MapSelector({
    super.key,
    required this.techWorld,
    this.roomService,
    this.userId,
    this.onLoadRoom,
    this.onDeleteRoom,
    this.savedRooms,
    this.onPopupOpened,
  });

  final TechWorld techWorld;

  /// Room service for fetching user's saved rooms.
  final RoomService? roomService;

  /// Current user's ID for filtering owned rooms.
  final String? userId;

  /// Called when the user selects a saved room to load.
  final void Function(RoomData room)? onLoadRoom;

  /// Called when the user deletes a saved room.
  final void Function(RoomData room)? onDeleteRoom;

  /// Pre-fetched list of the user's saved rooms. If null and [roomService]
  /// is provided, rooms are fetched lazily when the popup opens.
  final List<RoomData>? savedRooms;

  /// Called when the popup is about to open, allowing the parent to
  /// trigger a refresh of [savedRooms].
  final VoidCallback? onPopupOpened;

  @override
  State<MapSelector> createState() => _MapSelectorState();
}

class _MapSelectorState extends State<MapSelector> {
  List<RoomData>? _cachedRooms;
  bool _loading = false;

  List<RoomData>? get _rooms => widget.savedRooms ?? _cachedRooms;

  Future<void> _loadRooms() async {
    if (widget.roomService == null || widget.userId == null) return;
    if (_loading) return;

    setState(() => _loading = true);
    try {
      final rooms = await widget.roomService!.listMyRooms(widget.userId!);
      if (mounted) {
        setState(() {
          _cachedRooms = rooms;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _log.warning('Failed to load saved rooms', e);
    }
  }

  Future<void> _confirmDelete(RoomData room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Room'),
        content: Text('Delete "${room.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onDeleteRoom?.call(room);
      // Remove from local cache immediately for responsive UI.
      setState(() {
        _cachedRooms?.removeWhere((r) => r.id == room.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GameMap>(
      valueListenable: widget.techWorld.currentMap,
      builder: (context, activeMap, _) {
        return PopupMenuButton<_MapAction>(
          offset: const Offset(0, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onOpened: () {
            widget.onPopupOpened?.call();
            if (widget.savedRooms == null) _loadRooms();
          },
          onSelected: (action) {
            switch (action) {
              case _LoadPredefinedMap(:final map):
                widget.techWorld.loadMap(map);
              case _GenerateMap(:final algorithm):
                final map = generateMap(algorithm: algorithm);
                widget.techWorld.loadMap(map);
              case _LoadSavedRoom(:final room):
                widget.onLoadRoom?.call(room);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map, color: Colors.white70, size: 18),
                const SizedBox(width: 6),
                Text(
                  activeMap.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down,
                    color: Colors.white70, size: 18),
              ],
            ),
          ),
          itemBuilder: (context) => [
            // --- Predefined Maps ---
            const PopupMenuItem<_MapAction>(
              enabled: false,
              height: 28,
              child: Text(
                'Predefined Maps',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final map in allMaps)
              PopupMenuItem<_MapAction>(
                value: _LoadPredefinedMap(map),
                child: Row(
                  children: [
                    Icon(
                      _mapIcon(map.id),
                      size: 16,
                      color: _mapIconColor(map.id),
                    ),
                    const SizedBox(width: 8),
                    Text(map.name),
                  ],
                ),
              ),

            // --- My Maps ---
            if (widget.roomService != null) ...[
              const PopupMenuDivider(),
              const PopupMenuItem<_MapAction>(
                enabled: false,
                height: 28,
                child: Text(
                  'My Maps',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_loading)
                const PopupMenuItem<_MapAction>(
                  enabled: false,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_rooms == null || _rooms!.isEmpty)
                const PopupMenuItem<_MapAction>(
                  enabled: false,
                  child: Text(
                    'No saved maps',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                )
              else
                for (final room in _rooms!)
                  PopupMenuItem<_MapAction>(
                    value: _LoadSavedRoom(room),
                    child: Row(
                      children: [
                        const SizedBox(width: 24),
                        Expanded(
                          child: Text(
                            room.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Delete button (only for owned rooms)
                        if (widget.userId != null &&
                            room.isOwner(widget.userId!))
                          InkWell(
                            onTap: () {
                              Navigator.pop(context);
                              _confirmDelete(room);
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.delete_outline,
                                  size: 16, color: Colors.red),
                            ),
                          ),
                      ],
                    ),
                  ),
            ],

            // --- Generate ---
            const PopupMenuDivider(),
            for (final algo in MapAlgorithm.values)
              PopupMenuItem<_MapAction>(
                value: _GenerateMap(algo),
                child: Row(
                  children: [
                    const Icon(Icons.casino, size: 16, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text('Generate ${algo.displayName}'),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Icon for each predefined map in the dropdown.
IconData _mapIcon(String mapId) => switch (mapId) {
      'l_room' => Icons.auto_awesome,
      'open_arena' => Icons.crop_free,
      'four_corners' => Icons.grid_4x4,
      'simple_maze' => Icons.route,
      'the_library' => Icons.menu_book,
      'the_workshop' => Icons.construction,
      _ => Icons.map_outlined,
    };

/// Accent color for each map icon.
Color _mapIconColor(String mapId) => switch (mapId) {
      'l_room' => const Color(0xFFFFD54F),
      'open_arena' => const Color(0xFF81C784),
      'four_corners' => const Color(0xFFE57373),
      'simple_maze' => const Color(0xFFBA68C8),
      'the_library' => const Color(0xFF4DD0E1),
      'the_workshop' => const Color(0xFFFFB74D),
      _ => const Color(0xFF90A4AE),
    };

/// Sealed class representing popup menu actions.
sealed class _MapAction {}

class _LoadPredefinedMap extends _MapAction {
  _LoadPredefinedMap(this.map);
  final GameMap map;
}

class _GenerateMap extends _MapAction {
  _GenerateMap(this.algorithm);
  final MapAlgorithm algorithm;
}

class _LoadSavedRoom extends _MapAction {
  _LoadSavedRoom(this.room);
  final RoomData room;
}

