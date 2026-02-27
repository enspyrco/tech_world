import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/livekit/widgets/screen_share_panel.dart';

/// Entry tracking a single screen share panel.
class _ScreenShareEntry {
  _ScreenShareEntry({
    required this.identity,
    required this.name,
    required this.track,
    required this.initialPosition,
  });

  final String identity;
  final String name;
  final VideoTrack track;
  final Offset initialPosition;
}

/// Manages floating [ScreenSharePanel]s for all active screen shares in the
/// LiveKit room.
///
/// Subscribes to [LiveKitService.trackSubscribed] and
/// [LiveKitService.trackUnsubscribed], filtered by
/// [TrackSource.screenShareVideo], and creates/removes panels accordingly.
class ScreenShareOverlay extends StatefulWidget {
  const ScreenShareOverlay({
    required this.liveKitService,
    super.key,
  });

  final LiveKitService liveKitService;

  @override
  State<ScreenShareOverlay> createState() => _ScreenShareOverlayState();
}

class _ScreenShareOverlayState extends State<ScreenShareOverlay> {
  /// Active screen share panels, keyed by `'${identity}_${track.sid}'`.
  final Map<String, _ScreenShareEntry> _entries = {};

  StreamSubscription<(Participant, VideoTrack)>? _subscribedSub;
  StreamSubscription<(Participant, VideoTrack)>? _unsubscribedSub;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(ScreenShareOverlay old) {
    super.didUpdateWidget(old);
    if (old.liveKitService != widget.liveKitService) {
      _unsubscribe();
      _entries.clear();
      _subscribe();
    }
  }

  void _subscribe() {
    _subscribedSub =
        widget.liveKitService.trackSubscribed.listen(_onTrackSubscribed);
    _unsubscribedSub =
        widget.liveKitService.trackUnsubscribed.listen(_onTrackUnsubscribed);
  }

  void _unsubscribe() {
    _subscribedSub?.cancel();
    _unsubscribedSub?.cancel();
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  void _onTrackSubscribed((Participant, VideoTrack) event) {
    final (participant, track) = event;

    // Only handle screen share tracks.
    final publication = participant.getTrackPublicationBySource(
      TrackSource.screenShareVideo,
    );
    if (publication == null || publication.track?.sid != track.sid) return;

    final key = '${participant.identity}_${track.sid}';
    if (_entries.containsKey(key)) return;

    // Stagger panels by 40px each to avoid stacking on top of each other.
    final index = _entries.length;
    final offset = Offset(40.0 * index + 40, 40.0 * index + 40);

    setState(() {
      _entries[key] = _ScreenShareEntry(
        identity: participant.identity,
        name: participant.name.isNotEmpty
            ? participant.name
            : participant.identity,
        track: track,
        initialPosition: offset,
      );
    });
  }

  void _onTrackUnsubscribed((Participant, VideoTrack) event) {
    final (participant, track) = event;
    final key = '${participant.identity}_${track.sid}';
    if (_entries.containsKey(key)) {
      setState(() {
        _entries.remove(key);
      });
    }
  }

  void _dismissPanel(String key) {
    setState(() {
      _entries.remove(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) return const SizedBox.shrink();

    return Stack(
      children: _entries.entries.map((entry) {
        final data = entry.value;
        return ScreenSharePanel(
          key: ValueKey(entry.key),
          sharerName: data.name,
          videoTrack: data.track,
          initialPosition: data.initialPosition,
          onClose: () => _dismissPanel(entry.key),
        );
      }).toList(),
    );
  }
}
