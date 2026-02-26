import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tech_world/auth/profile_picture_service.dart';
import 'package:tech_world/auth/user_profile_service.dart';

/// Result returned from [EditProfileDialog] when the user saves.
class EditProfileResult {
  const EditProfileResult({
    required this.displayName,
    this.profilePictureUrl,
  });

  final String displayName;
  final String? profilePictureUrl;
}

/// Dialog for editing the user's display name and profile picture.
///
/// Returns an [EditProfileResult] on save, or `null` on cancel.
class EditProfileDialog extends StatefulWidget {
  const EditProfileDialog({
    super.key,
    required this.currentDisplayName,
    this.currentProfilePictureUrl,
  });

  final String currentDisplayName;
  final String? currentProfilePictureUrl;

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  late final TextEditingController _nameController;
  bool _saving = false;
  bool _uploadingPhoto = false;
  String? _error;

  /// The new photo bytes picked by the user, or null if unchanged.
  Uint8List? _pendingPhotoBytes;
  String? _pendingPhotoMime;

  /// The current profile picture URL (may be updated after upload).
  String? _currentPhotoUrl;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentDisplayName);
    _currentPhotoUrl = widget.currentProfilePictureUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String get _initials {
    final name = _nameController.text.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Future<void> _pickPhoto() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image == null) return;

      final bytes = await image.readAsBytes();
      setState(() {
        _pendingPhotoBytes = bytes;
        _pendingPhotoMime = image.mimeType ?? 'image/jpeg';
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not open photo library.');
      }
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Update display name.
      await user.updateDisplayName(name);
      await user.reload();

      final profileService = UserProfileService();
      await profileService.saveUserProfile(uid: user.uid, displayName: name);

      // Upload profile picture if a new one was picked.
      String? newPhotoUrl = _currentPhotoUrl;
      if (_pendingPhotoBytes != null) {
        setState(() => _uploadingPhoto = true);
        final pictureService = ProfilePictureService();
        newPhotoUrl = await pictureService.uploadProfilePicture(
          uid: user.uid,
          imageBytes: _pendingPhotoBytes!,
          mimeType: _pendingPhotoMime ?? 'image/jpeg',
        );
        await profileService.saveProfilePictureUrl(user.uid, newPhotoUrl);
        await user.updatePhotoURL(newPhotoUrl);
        await user.reload();
      }

      if (mounted) {
        Navigator.of(context).pop(EditProfileResult(
          displayName: name,
          profilePictureUrl: newPhotoUrl,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to save profile. Please try again.');
      }
    } finally {
      if (mounted) setState(() { _saving = false; _uploadingPhoto = false; });
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
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Edit Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Profile picture
              GestureDetector(
                onTap: _saving ? null : _pickPhoto,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: Colors.blue,
                      backgroundImage: _pendingPhotoBytes != null
                          ? MemoryImage(_pendingPhotoBytes!)
                          : (_currentPhotoUrl != null
                              ? NetworkImage(_currentPhotoUrl!)
                              : null),
                      child: (_pendingPhotoBytes == null &&
                              _currentPhotoUrl == null)
                          ? Text(
                              _initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _saving ? null : _pickPhoto,
                child: const Text('Change Photo'),
              ),
              const SizedBox(height: 16),
              // Display name
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Display Name',
                  labelStyle: const TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.blue),
                  ),
                ),
                onSubmitted: (_) => _save(),
                onChanged: (_) => setState(() {}), // Update initials preview
              ),
              const SizedBox(height: 24),
              // Status indicator
              if (_uploadingPhoto)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Uploading photo...',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Colors.red.shade300,
                      fontSize: 13,
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
