import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tech_world/auth/user_profile_service.dart';
import 'package:tech_world/flame/maps/map_identity.dart';
import 'package:tech_world/rooms/manage_editors_dialog.dart';
import 'package:tech_world/rooms/presence_entry.dart';
import 'package:tech_world/rooms/presence_service.dart';
import 'package:tech_world/rooms/room_data.dart';
import 'package:tech_world/rooms/room_service.dart';

/// Lobby screen shown after authentication — browse and join rooms.
///
/// Displays public rooms and the user's own rooms in separate tabs.
/// Tap a room to join, or create a new room via the editor.
class RoomBrowser extends StatefulWidget {
  const RoomBrowser({
    required this.roomService,
    required this.userId,
    required this.onJoinRoom,
    required this.onCreateRoom,
    this.canCreateRoom = true,
    this.onSignOut,
    this.presenceService,
    super.key,
  });

  final RoomService roomService;
  final String userId;

  /// Source of room occupancy ("who is in each room"). Injectable for tests;
  /// defaults to a Firestore-backed [PresenceService] in production.
  final PresenceService? presenceService;

  /// Whether the current user can create rooms (false for anonymous guests).
  final bool canCreateRoom;

  /// Called when the user taps "Sign out".
  final VoidCallback? onSignOut;

  /// Called when the user selects a room to join.
  final void Function(RoomData room) onJoinRoom;

  /// Called when the user taps "Create Room" — should open the editor.
  final VoidCallback onCreateRoom;

  @override
  State<RoomBrowser> createState() => _RoomBrowserState();
}

class _RoomBrowserState extends State<RoomBrowser>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final PresenceService _presenceService;
  List<RoomData>? _publicRooms;
  List<RoomData>? _myRooms;
  bool _loading = true;
  String? _error;

  /// Live room occupancy, keyed by room id. One subscription over the whole
  /// `/presence` collection feeds every card.
  Map<String, List<PresenceEntry>> _occupancy = const {};
  StreamSubscription<List<PresenceEntry>>? _presenceSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _presenceService = widget.presenceService ?? PresenceService();
    _loadRooms();
    _presenceSub = _presenceService.watchAll().listen((entries) {
      if (mounted) {
        setState(() => _occupancy = PresenceService.groupByRoom(entries));
      }
    });
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.roomService.listPublicRooms(),
        widget.roomService.listMyRooms(widget.userId),
      ]);
      if (mounted) {
        setState(() {
          _publicRooms = results[0];
          _myRooms = results[1];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabs(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Row(
        children: [
          const Icon(Icons.meeting_room, color: Color(0xFF4FC3F7), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tech World Rooms',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.canCreateRoom
                      ? 'Join a room or create your own'
                      : 'Join a room to start exploring',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
          if (widget.canCreateRoom)
            ElevatedButton.icon(
              onPressed: widget.onCreateRoom,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create Room'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            )
          else
            Text(
              'Sign in to create rooms',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
            ),
          if (widget.onSignOut != null)
            IconButton(
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout, size: 20),
              tooltip: 'Sign out',
              color: Colors.white54,
            ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF3D3D5C))),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xFF4FC3F7),
        labelColor: const Color(0xFF4FC3F7),
        unselectedLabelColor: Colors.white54,
        tabs: [
          Tab(
            text: 'Public Rooms'
                '${_publicRooms != null ? ' (${_publicRooms!.length})' : ''}',
          ),
          Tab(
            text: 'My Rooms'
                '${_myRooms != null ? ' (${_myRooms!.length})' : ''}',
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF4FC3F7)),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              'Failed to load rooms',
              style: TextStyle(color: Colors.red.shade300, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadRooms,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildRoomList(_publicRooms ?? []),
        _buildRoomList(_myRooms ?? []),
      ],
    );
  }

  Widget _buildRoomList(List<RoomData> rooms) {
    if (rooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox, color: Colors.white.withValues(alpha: 0.3), size: 48),
            const SizedBox(height: 12),
            Text(
              'No rooms yet',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.canCreateRoom)
              TextButton.icon(
                onPressed: widget.onCreateRoom,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Create one'),
              )
            else
              Text(
                'Sign in to create rooms',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 13,
                ),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRooms,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: rooms.length,
        itemBuilder: (context, index) {
          final room = rooms[index];
          return _RoomCard(
            room: room,
            isOwner: room.isOwner(widget.userId),
            occupants: _occupancy[room.id] ?? const [],
            onTap: () => widget.onJoinRoom(room),
            onDelete: room.isOwner(widget.userId)
                ? () => _deleteRoom(room)
                : null,
            onManageEditors: room.isOwner(widget.userId)
                ? () => _showManageEditors(room)
                : null,
          );
        },
      ),
    );
  }

  Future<void> _showManageEditors(RoomData room) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => ManageEditorsDialog(
        room: room,
        roomService: widget.roomService,
        userProfileService: UserProfileService(),
      ),
    );
    // Refresh rooms to pick up editor changes.
    _loadRooms();
  }

  Future<void> _deleteRoom(RoomData room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D4D),
        title: const Text('Delete Room', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "${room.name}"? This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
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
      await widget.roomService.deleteRoom(room.id);
      _loadRooms();
    }
  }
}

/// A card representing a single room in the browser list.
class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.isOwner,
    required this.onTap,
    this.occupants = const [],
    this.onDelete,
    this.onManageEditors,
  });

  final RoomData room;
  final bool isOwner;

  /// Users currently in this room — rendered as a foyer presence row.
  final List<PresenceEntry> occupants;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onManageEditors;

  @override
  Widget build(BuildContext context) {
    final identity = MapIdentity.of(name: room.name);

    return Card(
      color: const Color(0xFF16213E),
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF2D2D5C)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Map icon — color and icon from MapIdentity
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: identity.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  identity.icon,
                  color: identity.color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // Room info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'by ${room.ownerDisplayName.isNotEmpty ? room.ownerDisplayName : 'Unknown'}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    if (occupants.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _OccupancyRow(occupants: occupants),
                    ],
                  ],
                ),
              ),
              if (isOwner)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Owner',
                    style: TextStyle(
                      color: Color(0xFF4CAF50),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (onManageEditors != null)
                IconButton(
                  onPressed: onManageEditors,
                  icon: const Icon(Icons.people_outline, size: 18),
                  color: const Color(0xFF4FC3F7),
                  tooltip: 'Manage editors',
                ),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.red.shade300,
                  tooltip: 'Delete room',
                ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}

/// The foyer "who's gathered" indicator: a horizontal stack of overlapping
/// occupant avatars, an overflow "+N" chip when there are more than fit, and a
/// count. This is the world-as-substrate moment — you see who's in a room
/// before you walk in, the way you'd glance into a tavern common-room.
class _OccupancyRow extends StatelessWidget {
  const _OccupancyRow({required this.occupants});

  final List<PresenceEntry> occupants;

  static const _maxVisible = 5;
  static const _size = 24.0;
  static const _overlap = 8.0;

  @override
  Widget build(BuildContext context) {
    final visible = occupants.take(_maxVisible).toList();
    final overflow = occupants.length - visible.length;
    final chipCount = visible.length + (overflow > 0 ? 1 : 0);
    final step = _size - _overlap;
    final stackWidth = _size + (chipCount - 1) * step;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _size,
          width: stackWidth,
          child: Stack(
            children: [
              for (var i = 0; i < visible.length; i++)
                Positioned(
                  left: i * step,
                  child: _OccupantAvatar(entry: visible[i], size: _size),
                ),
              if (overflow > 0)
                Positioned(
                  left: visible.length * step,
                  child: _OverflowChip(count: overflow, size: _size),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          occupants.length == 1 ? '1 here' : '${occupants.length} here',
          style: const TextStyle(
            color: Color(0xFF4CAF50),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// A single occupant rendered as a colored initial circle. Deterministic color
/// from the user id so a given person looks consistent across cards/sessions.
/// (Sprite-head avatars are a planned follow-up; an initial circle always
/// renders and reads instantly — the Gather/Slack foyer idiom.)
class _OccupantAvatar extends StatelessWidget {
  const _OccupantAvatar({required this.entry, required this.size});

  final PresenceEntry entry;
  final double size;

  static const _palette = [
    Color(0xFF4FC3F7),
    Color(0xFFD97757),
    Color(0xFF81C784),
    Color(0xFFBA68C8),
    Color(0xFFFFB74D),
    Color(0xFF4DB6AC),
    Color(0xFFF06292),
  ];

  // Explicit polynomial (Java-style, *31) hash over code units — unlike
  // String.hashCode this is stable across runs/platforms, so a given user keeps
  // the same color between sessions, not just within one process.
  static int _stableHash(String s) {
    var h = 0;
    for (final unit in s.codeUnits) {
      h = (h * 31 + unit) & 0x7fffffff;
    }
    return h;
  }

  Color get _color => _palette[_stableHash(entry.userId) % _palette.length];

  String get _initial {
    final name = entry.displayName.trim();
    // characters.first, not substring(0, 1): grapheme-safe so a leading emoji
    // or surrogate-pair name doesn't render a broken half-character.
    return name.isEmpty ? '?' : name.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: entry.displayName.isEmpty ? 'Someone' : entry.displayName,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _color,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF16213E), width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          _initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.45,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// The "+N" chip shown when a room has more occupants than fit in the stack.
class _OverflowChip extends StatelessWidget {
  const _OverflowChip({required this.count, required this.size});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF3D3D5C),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF16213E), width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '+$count',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.34,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
