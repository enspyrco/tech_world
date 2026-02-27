import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

/// A draggable, resizable floating panel that displays a screen share video.
///
/// Shows a title bar with the sharer's name, maximize/close buttons, and
/// renders the video track using LiveKit's [VideoTrackRenderer]. When no
/// [videoTrack] is provided (e.g. during tests), a placeholder icon is shown.
class ScreenSharePanel extends StatefulWidget {
  const ScreenSharePanel({
    required this.sharerName,
    required this.videoTrack,
    required this.onClose,
    this.initialPosition = Offset.zero,
    super.key,
  });

  /// Display name of the participant sharing their screen.
  final String sharerName;

  /// The screen share video track to render, or null for placeholder.
  final VideoTrack? videoTrack;

  /// Called when the user dismisses this panel locally.
  /// Does NOT stop the remote participant's share.
  final VoidCallback onClose;

  /// Initial position in the parent [Stack].
  final Offset initialPosition;

  @override
  State<ScreenSharePanel> createState() => _ScreenSharePanelState();
}

class _ScreenSharePanelState extends State<ScreenSharePanel> {
  static const _defaultWidth = 640.0;
  static const _defaultHeight = 400.0;
  static const _minWidth = 320.0;
  static const _minHeight = 200.0;
  static const _maxWidth = 1920.0;
  static const _maxHeight = 1080.0;
  static const _titleBarHeight = 36.0;

  late Offset _position;
  Size _size = const Size(_defaultWidth, _defaultHeight);
  bool _maximized = false;

  /// Stored position/size before maximizing, so we can restore.
  Offset? _preMaxPosition;
  Size? _preMaxSize;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
  }

  void _toggleMaximized() {
    setState(() {
      if (_maximized) {
        // Restore previous position and size.
        _position = _preMaxPosition ?? Offset.zero;
        _size = _preMaxSize ?? const Size(_defaultWidth, _defaultHeight);
        _maximized = false;
      } else {
        _preMaxPosition = _position;
        _preMaxSize = _size;
        _maximized = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_maximized) {
      return _buildMaximized();
    }
    return _buildFloating();
  }

  Widget _buildMaximized() {
    return Positioned.fill(
      child: _buildPanelContent(null),
    );
  }

  Widget _buildFloating() {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: SizedBox(
        width: _size.width,
        height: _size.height,
        child: _buildPanelContent(
          _buildResizeHandle(),
        ),
      ),
    );
  }

  Widget _buildPanelContent(Widget? resizeHandle) {
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(8),
      color: const Color(0xFF1E1E1E),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildTitleBar(),
          Expanded(child: _buildBody()),
          if (resizeHandle != null) resizeHandle,
        ],
      ),
    );
  }

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanUpdate: _maximized
          ? null
          : (details) {
              setState(() {
                _position += details.delta;
              });
            },
      child: Container(
        height: _titleBarHeight,
        color: const Color(0xFF2D2D2D),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const Icon(Icons.screen_share, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.sharerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TitleBarButton(
              icon: _maximized ? Icons.close_fullscreen : Icons.open_in_full,
              tooltip: _maximized ? 'Restore' : 'Maximize',
              onPressed: _toggleMaximized,
            ),
            _TitleBarButton(
              icon: Icons.close,
              tooltip: 'Close',
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final track = widget.videoTrack;
    if (track == null) {
      return const Center(
        child: Icon(Icons.screen_share, color: Colors.white24, size: 48),
      );
    }
    return VideoTrackRenderer(
      track,
      fit: VideoViewFit.contain,
    );
  }

  Widget _buildResizeHandle() {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _size = Size(
            (_size.width + details.delta.dx).clamp(_minWidth, _maxWidth),
            (_size.height + details.delta.dy).clamp(_minHeight, _maxHeight),
          );
        });
      },
      child: const Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: EdgeInsets.all(4),
          child: Icon(
            Icons.drag_handle,
            color: Colors.white24,
            size: 16,
          ),
        ),
      ),
    );
  }
}

class _TitleBarButton extends StatelessWidget {
  const _TitleBarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        color: Colors.white70,
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        splashRadius: 14,
      ),
    );
  }
}
