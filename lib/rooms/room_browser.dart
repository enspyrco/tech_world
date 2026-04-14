import 'package:flutter/material.dart';
import 'package:tech_world/auth/user_profile_service.dart';
import 'package:tech_world/flame/maps/map_identity.dart';
import 'package:tech_world/rooms/manage_editors_dialog.dart';
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
    this.joiningRoomId,
    this.joinProgress,
    this.joinMessage,
    super.key,
  });

  final RoomService roomService;
  final String userId;

  /// Whether the current user can create rooms (false for anonymous guests).
  final bool canCreateRoom;

  /// Called when the user taps "Sign out".
  final VoidCallback? onSignOut;

  /// Called when the user selects a room to join.
  final void Function(RoomData room) onJoinRoom;

  /// Called when the user taps "Create Room" — should open the editor.
  final VoidCallback onCreateRoom;

  /// The room ID currently being joined (null when idle).
  final String? joiningRoomId;

  /// Join progress 0.0–1.0 for the card identified by [joiningRoomId].
  final double? joinProgress;

  /// Step message shown on the joining card (e.g. "Connecting to server…").
  final String? joinMessage;

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

    final joiningId = widget.joiningRoomId;

    return RefreshIndicator(
      onRefresh: _loadRooms,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: rooms.length,
        itemBuilder: (context, index) {
          final room = rooms[index];
          final isJoining = joiningId != null && room.id == joiningId;
          final isOtherJoining = joiningId != null && room.id != joiningId;

          return _RoomCard(
            room: room,
            isOwner: room.isOwner(widget.userId),
            onTap: () => widget.onJoinRoom(room),
            onDelete: room.isOwner(widget.userId)
                ? () => _deleteRoom(room)
                : null,
            onManageEditors: room.isOwner(widget.userId)
                ? () => _showManageEditors(room)
                : null,
            joinProgress: isJoining ? widget.joinProgress : null,
            joinMessage: isJoining ? widget.joinMessage : null,
            disabled: isOtherJoining,
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
///
/// When [joinProgress] is non-null the card shows an animated color fill
/// sweeping left-to-right with [joinMessage] replacing the room name.
/// When [disabled] is true the card is dimmed and non-interactive (used for
/// cards that are not the one being joined).
class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.isOwner,
    required this.onTap,
    this.onDelete,
    this.onManageEditors,
    this.joinProgress,
    this.joinMessage,
    this.disabled = false,
  });

  final RoomData room;
  final bool isOwner;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onManageEditors;

  /// 0.0–1.0 join progress, or null when not joining this room.
  final double? joinProgress;

  /// Step label shown while joining (e.g. "Connecting to server…").
  final String? joinMessage;

  /// True for cards that are not the joining card while a join is in progress.
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final isJoining = joinProgress != null;

    return AnimatedOpacity(
      opacity: disabled ? 0.45 : 1.0,
      duration: const Duration(milliseconds: 250),
      child: Card(
        color: const Color(0xFF16213E),
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isJoining
                ? const Color(0xFF4FC3F7).withValues(alpha: 0.6)
                : const Color(0xFF2D2D5C),
          ),
        ),
        child: InkWell(
          onTap: (isJoining || disabled) ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              // Animated progress fill
              if (isJoining)
                Positioned.fill(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: joinProgress!),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    builder: (context, value, _) {
                      return FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: value.clamp(0.0, 1.0),
                        child: Container(
                          color: const Color(0xFF4FC3F7).withValues(alpha: 0.15),
                        ),
                      );
                    },
                  ),
                ),
              // Card content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Map icon
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: MapIdentity.of(name: room.name).color
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: isJoining
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF4FC3F7),
                                  ),
                                ),
                              ),
                            )
                          : Icon(
                              MapIdentity.of(name: room.name).icon,
                              color: MapIdentity.of(name: room.name).color,
                              size: 24,
                            ),
                    ),
                    const SizedBox(width: 16),
                    // Room info / join message
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isJoining ? (joinMessage ?? 'Joining\u2026') : room.name,
                            style: TextStyle(
                              color: isJoining
                                  ? const Color(0xFF4FC3F7)
                                  : Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (isJoining)
                            Text(
                              room.name,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            )
                          else
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
                    // Owner badge (hidden while joining)
                    if (!isJoining && isOwner)
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
                    // Manage editors button (hidden while joining)
                    if (!isJoining && onManageEditors != null)
                      IconButton(
                        onPressed: onManageEditors,
                        icon: const Icon(Icons.people_outline, size: 18),
                        color: const Color(0xFF4FC3F7),
                        tooltip: 'Manage editors',
                      ),
                    // Delete button (hidden while joining)
                    if (!isJoining && onDelete != null)
                      IconButton(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: Colors.red.shade300,
                        tooltip: 'Delete room',
                      ),
                    // Join arrow (hidden while joining)
                    if (!isJoining)
                      const Icon(Icons.chevron_right, color: Colors.white38),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
