import 'package:flutter/material.dart';
import 'package:tech_world/avatar/avatar.dart';
import 'package:tech_world/avatar/predefined_avatars.dart';

/// Full-screen character selection UI.
///
/// Displays all [predefinedAvatars] in a grid. The player taps an avatar to
/// select it, then taps "Confirm" to commit the choice.
class AvatarSelectionScreen extends StatefulWidget {
  const AvatarSelectionScreen({
    required this.onAvatarSelected,
    this.initialAvatar,
    super.key,
  });

  /// Called when the player confirms their avatar choice.
  final ValueChanged<Avatar> onAvatarSelected;

  /// Pre-selects a previously saved avatar. Falls back to [defaultAvatar].
  final Avatar? initialAvatar;

  @override
  State<AvatarSelectionScreen> createState() => _AvatarSelectionScreenState();
}

class _AvatarSelectionScreenState extends State<AvatarSelectionScreen> {
  late Avatar _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialAvatar ?? defaultAvatar;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Choose Your Character',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 32),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: predefinedAvatars
                      .map((avatar) => _AvatarCard(
                            avatar: avatar,
                            isSelected: avatar == _selected,
                            onTap: () => setState(() => _selected = avatar),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: 200,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => widget.onAvatarSelected(_selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97757),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single avatar card in the selection grid.
class _AvatarCard extends StatelessWidget {
  const _AvatarCard({
    required this.avatar,
    required this.isSelected,
    required this.onTap,
  });

  final Avatar avatar;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: const Color(0xFFD97757), width: 2)
              : Border.all(color: Colors.transparent, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sprite preview — show the first frame (down-facing) of the sheet
            SizedBox(
              width: 64,
              height: 128,
              child: Image.asset(
                'assets/images/${avatar.spriteAsset}',
                fit: BoxFit.none,
                alignment: Alignment.topLeft,
                // Crop to show only the first 64x128 (scaled 2x from 32x64)
                width: 64,
                height: 128,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.person,
                  color: Colors.white38,
                  size: 48,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              avatar.displayName,
              style: TextStyle(
                color: isSelected ? const Color(0xFFD97757) : Colors.white70,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
