import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tech_world/auth/user_profile_service.dart';
import 'package:tech_world/rooms/room_data.dart';
import 'package:tech_world/rooms/room_service.dart';

/// Dialog for room owners to view, add, and remove editors.
///
/// Writes directly to Firestore via [RoomService] — the caller should refresh
/// room data after the dialog closes.
class ManageEditorsDialog extends StatefulWidget {
  const ManageEditorsDialog({
    required this.room,
    required this.roomService,
    required this.userProfileService,
    super.key,
  });

  final RoomData room;
  final RoomService roomService;
  final UserProfileService userProfileService;

  @override
  State<ManageEditorsDialog> createState() => _ManageEditorsDialogState();
}

class _ManageEditorsDialogState extends State<ManageEditorsDialog> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<UserProfile> _editors = [];
  List<UserProfile> _searchResults = [];
  Set<String> _editorIds = {};
  bool _loading = true;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _editorIds = widget.room.editorIds.toSet();
    _loadEditors();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadEditors() async {
    if (_editorIds.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final profiles = await widget.userProfileService
          .getUserProfiles(_editorIds.toList());
      if (mounted) {
        setState(() {
          _editors = profiles;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load editor profiles: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final results = await widget.userProfileService
            .searchUsers(query.trim());
        if (!mounted) return;
        // Filter out the owner and existing editors.
        final filtered = results
            .where((p) =>
                p.uid != widget.room.ownerId && !_editorIds.contains(p.uid))
            .toList();
        setState(() {
          _searchResults = filtered;
          _searching = false;
        });
      } catch (e) {
        debugPrint('Search failed: $e');
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _addEditor(UserProfile user) async {
    try {
      await widget.roomService.addEditor(widget.room.id, user.uid);
      if (!mounted) return;
      setState(() {
        _editorIds.add(user.uid);
        _editors.add(user);
        _searchResults.removeWhere((p) => p.uid == user.uid);
      });
    } catch (e) {
      debugPrint('Failed to add editor: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add editor.')),
        );
      }
    }
  }

  Future<void> _removeEditor(UserProfile user) async {
    try {
      await widget.roomService.removeEditor(widget.room.id, user.uid);
      if (!mounted) return;
      setState(() {
        _editorIds.remove(user.uid);
        _editors.removeWhere((p) => p.uid == user.uid);
      });
    } catch (e) {
      debugPrint('Failed to remove editor: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to remove editor.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2D2D2D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.people, color: Color(0xFF4FC3F7), size: 24),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Manage Editors',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white54),
                    iconSize: 20,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.room.name,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              // Current editors
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      color: Color(0xFF4FC3F7),
                      strokeWidth: 2,
                    ),
                  ),
                )
              else ...[
                Text(
                  'Editors (${_editors.length})',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                if (_editors.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No editors yet — search below to add people.',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _editors.length,
                      itemBuilder: (context, index) {
                        final editor = _editors[index];
                        return _UserTile(
                          profile: editor,
                          trailing: IconButton(
                            onPressed: () => _removeEditor(editor),
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 18),
                            color: Colors.red.shade300,
                            tooltip: 'Remove editor',
                          ),
                        );
                      },
                    ),
                  ),
              ],
              const Divider(color: Colors.white24, height: 24),
              // Search
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search by name...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search,
                      color: Colors.white38, size: 20),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF4FC3F7),
                            ),
                          ),
                        )
                      : null,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF4FC3F7)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Search results
              if (_searchResults.isNotEmpty)
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final user = _searchResults[index];
                      return _UserTile(
                        profile: user,
                        trailing: IconButton(
                          onPressed: () => _addEditor(user),
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          color: const Color(0xFF4CAF50),
                          tooltip: 'Add as editor',
                        ),
                      );
                    },
                  ),
                )
              else if (_searchController.text.trim().isNotEmpty && !_searching)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No users found.',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact list tile showing a user's avatar and display name.
class _UserTile extends StatelessWidget {
  const _UserTile({required this.profile, this.trailing});

  final UserProfile profile;
  final Widget? trailing;

  String get _initials {
    final name = profile.displayName ?? '';
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF4FC3F7).withValues(alpha: 0.3),
            backgroundImage: profile.profilePictureUrl != null
                ? NetworkImage(profile.profilePictureUrl!)
                : null,
            child: profile.profilePictureUrl == null
                ? Text(
                    _initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              profile.displayName ?? 'Unknown',
              style: const TextStyle(color: Colors.white, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
