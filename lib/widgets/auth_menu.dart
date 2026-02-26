import 'package:flutter/material.dart';
import 'package:tech_world/auth/auth_service.dart';
import 'package:tech_world/utils/locator.dart';

/// A user avatar with dropdown menu for auth actions (sign out, etc.)
class AuthMenu extends StatelessWidget {
  final String displayName;

  /// Called when the user taps "Change Avatar". If null, the item is hidden.
  final VoidCallback? onChangeAvatar;

  /// Called when the user taps "Edit Profile". If null, the item is hidden.
  final VoidCallback? onEditProfile;

  /// URL for the user's profile picture. When set, shown in the avatar circle.
  final String? profilePictureUrl;

  const AuthMenu({
    super.key,
    required this.displayName,
    this.onChangeAvatar,
    this.onEditProfile,
    this.profilePictureUrl,
  });

  String get _initials {
    if (displayName.isEmpty) return '?';
    final parts = displayName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return displayName[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue,
              backgroundImage: profilePictureUrl != null
                  ? NetworkImage(profilePictureUrl!)
                  : null,
              child: profilePictureUrl != null
                  ? null
                  : Text(
                      _initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_drop_down, color: Colors.white),
          ],
        ),
      ),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            displayName.isEmpty ? 'Guest' : displayName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const PopupMenuDivider(),
        if (onEditProfile != null)
          const PopupMenuItem<String>(
            value: 'edit_profile',
            child: Row(
              children: [
                Icon(Icons.edit, size: 20),
                SizedBox(width: 8),
                Text('Edit Profile'),
              ],
            ),
          ),
        if (onChangeAvatar != null)
          const PopupMenuItem<String>(
            value: 'avatar',
            child: Row(
              children: [
                Icon(Icons.face, size: 20),
                SizedBox(width: 8),
                Text('Change Avatar'),
              ],
            ),
          ),
        const PopupMenuItem<String>(
          value: 'signout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 20),
              SizedBox(width: 8),
              Text('Sign out'),
            ],
          ),
        ),
      ],
      onSelected: (value) async {
        if (value == 'edit_profile') {
          onEditProfile?.call();
        } else if (value == 'avatar') {
          onChangeAvatar?.call();
        } else if (value == 'signout') {
          await locate<AuthService>().signOut();
        }
      },
    );
  }
}
