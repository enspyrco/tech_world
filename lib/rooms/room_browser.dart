import 'package:flutter/material.dart';
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
    super.key,
  });

  final RoomService roomService;
  final String userId;

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
  List<RoomData>? _publicRooms;
  List<RoomData>? _myRooms;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRooms();
  }

  @override
  void dispose() {
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tech World Rooms',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Join a room or create your own',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
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
            TextButton.icon(
              onPressed: widget.onCreateRoom,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Create one'),
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
        itemBuilder: (context, index) => _RoomCard(
          room: rooms[index],
          isOwner: rooms[index].isOwner(widget.userId),
          onTap: () => widget.onJoinRoom(rooms[index]),
          onDelete: rooms[index].isOwner(widget.userId)
              ? () => _deleteRoom(rooms[index])
              : null,
        ),
      ),
    );
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
    this.onDelete,
  });

  final RoomData room;
  final bool isOwner;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF16213E),
      margin: const EdgeInsets.only(bottom: 8),
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
              // Map icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF4FC3F7).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.map,
                  color: Color(0xFF4FC3F7),
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
                  ],
                ),
              ),
              // Owner badge
              if (isOwner)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              // Delete button
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.red.shade300,
                  tooltip: 'Delete room',
                ),
              // Join arrow
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}
