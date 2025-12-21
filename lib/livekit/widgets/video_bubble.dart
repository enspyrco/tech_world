import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

/// A circular video bubble that displays a participant's video feed.
/// Shows the participant's initial if no video is available.
class VideoBubble extends StatefulWidget {
  const VideoBubble({
    required this.participant,
    this.size = 80,
    super.key,
  });

  final Participant participant;
  final double size;

  @override
  State<VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<VideoBubble> {
  @override
  void initState() {
    super.initState();
    widget.participant.addListener(_onParticipantChanged);
  }

  @override
  void dispose() {
    widget.participant.removeListener(_onParticipantChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VideoBubble oldWidget) {
    oldWidget.participant.removeListener(_onParticipantChanged);
    widget.participant.addListener(_onParticipantChanged);
    super.didUpdateWidget(oldWidget);
  }

  void _onParticipantChanged() => setState(() {});

  VideoTrack? get _videoTrack {
    if (widget.participant is LocalParticipant) {
      final pub = (widget.participant as LocalParticipant)
          .videoTrackPublications
          .where((t) => t.source == TrackSource.camera)
          .firstOrNull;
      return pub?.track;
    } else if (widget.participant is RemoteParticipant) {
      final pub = (widget.participant as RemoteParticipant)
          .videoTrackPublications
          .where((t) => t.source == TrackSource.camera)
          .firstOrNull;
      return pub?.track;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final videoTrack = _videoTrack;
    final hasVideo = videoTrack != null && !videoTrack.muted;

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.participant.isSpeaking ? Colors.green : Colors.white,
          width: widget.participant.isSpeaking ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: hasVideo
            ? VideoTrackRenderer(videoTrack, fit: VideoViewFit.cover)
            : Container(
                color: Colors.grey[800],
                child: Center(
                  child: Text(
                    _getInitial(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.size * 0.4,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  String _getInitial() {
    final name = widget.participant.name;
    if (name.isNotEmpty) {
      return name[0].toUpperCase();
    }
    final identity = widget.participant.identity;
    if (identity.isNotEmpty) {
      return identity[0].toUpperCase();
    }
    return '?';
  }
}
