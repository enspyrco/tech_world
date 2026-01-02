import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../exts.dart';

class ControlsWidget extends StatefulWidget {
  //
  final Room room;
  final LocalParticipant participant;

  const ControlsWidget(
    this.room,
    this.participant, {
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _ControlsWidgetState();
}

class _ControlsWidgetState extends State<ControlsWidget> {
  //
  CameraPosition position = CameraPosition.front;

  List<MediaDevice>? _audioInputs;
  List<MediaDevice>? _audioOutputs;
  List<MediaDevice>? _videoInputs;

  StreamSubscription? _subscription;

  bool _speakerphoneOn = Hardware.instance.preferSpeakerOutput;

  @override
  void initState() {
    super.initState();
    participant.addListener(_onChange);
    _subscription = Hardware.instance.onDeviceChange.stream
        .listen((List<MediaDevice> devices) {
      _loadDevices(devices);
    });
    Hardware.instance.enumerateDevices().then(_loadDevices);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    participant.removeListener(_onChange);
    super.dispose();
  }

  LocalParticipant get participant => widget.participant;

  void _loadDevices(List<MediaDevice> devices) async {
    _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
    _audioOutputs = devices.where((d) => d.kind == 'audiooutput').toList();
    _videoInputs = devices.where((d) => d.kind == 'videoinput').toList();
    setState(() {});
  }

  void _onChange() {
    // trigger refresh
    setState(() {});
  }

  void _disableAudio() async {
    await participant.setMicrophoneEnabled(false);
  }

  Future<void> _enableAudio() async {
    await participant.setMicrophoneEnabled(true);
  }

  void _disableVideo() async {
    await participant.setCameraEnabled(false);
  }

  void _enableVideo() async {
    await participant.setCameraEnabled(true);
  }

  void _selectAudioOutput(MediaDevice device) async {
    await widget.room.setAudioOutputDevice(device);
    setState(() {});
  }

  void _selectAudioInput(MediaDevice device) async {
    await widget.room.setAudioInputDevice(device);
    setState(() {});
  }

  void _selectVideoInput(MediaDevice device) async {
    await widget.room.setVideoInputDevice(device);
    setState(() {});
  }

  void _setSpeakerphoneOn() {
    _speakerphoneOn = !_speakerphoneOn;
    Hardware.instance.setSpeakerphoneOn(_speakerphoneOn);
    setState(() {});
  }

  void _toggleCamera() async {
    //
    final track = participant.videoTrackPublications.firstOrNull?.track;
    if (track == null) return;

    try {
      final newPosition = position.switched();
      await track.setCameraPosition(newPosition);
      setState(() {
        position = newPosition;
      });
    } catch (error) {
      debugPrint('could not restart track: $error');
      return;
    }
  }

  void _enableScreenShare() async {
    if (lkPlatformIsDesktop()) {
      try {
        final source = await showDialog<DesktopCapturerSource>(
          context: context,
          builder: (context) => ScreenSelectDialog(),
        );
        if (source == null) {
          debugPrint('cancelled screenshare');
          return;
        }
        debugPrint('DesktopCapturerSource: ${source.id}');
        var track = await LocalVideoTrack.createScreenShareTrack(
          ScreenShareCaptureOptions(
            sourceId: source.id,
            maxFrameRate: 15.0,
          ),
        );
        await participant.publishVideoTrack(track);
      } catch (e) {
        debugPrint('could not publish video: $e');
      }
      return;
    }

    await participant.setScreenShareEnabled(true, captureScreenAudio: true);
  }

  void _disableScreenShare() async {
    await participant.setScreenShareEnabled(false);
    if (lkPlatformIs(PlatformType.android)) {
      // Android specific
      try {
        //   await FlutterBackground.disableBackgroundExecution();
      } catch (error) {
        debugPrint('error disabling screen share: $error');
      }
    }
  }

  void _onTapDisconnect() async {
    final result = await context.showDisconnectDialog();
    if (result == true) await widget.room.disconnect();
  }

  void _onTapInvite() async {
    final roomName = widget.room.name ?? 'Unknown';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite to Room'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share this room name with others:'),
            const SizedBox(height: 10),
            SelectableText(
              roomName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: roomName));
              Navigator.of(context).pop(true);
            },
            child: const Text('Copy Room Name'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Room name copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 48,
      child: Row(
        children: [
          // Left side: Menu button
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu, size: 20),
            tooltip: 'Menu',
            padding: EdgeInsets.zero,
            onSelected: _handleMenuSelection,
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'invite',
                child: ListTile(
                  leading: Icon(Icons.person_add),
                  title: Text('Invite'),
                  dense: true,
                ),
              ),
              if (participant.isScreenShareEnabled())
                const PopupMenuItem<String>(
                  value: 'screen_share_off',
                  child: ListTile(
                    leading: Icon(Icons.stop_screen_share),
                    title: Text('Stop Screen Share'),
                    dense: true,
                  ),
                )
              else
                const PopupMenuItem<String>(
                  value: 'screen_share',
                  child: ListTile(
                    leading: Icon(Icons.screen_share),
                    title: Text('Share Screen'),
                    dense: true,
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'configure',
                child: ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Configure'),
                  dense: true,
                  trailing: Icon(
                    Icons.arrow_right,
                    color: Colors.grey[400],
                  ),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'leave',
                child: ListTile(
                  leading: Icon(Icons.exit_to_app, color: Colors.red),
                  title: Text('Leave', style: TextStyle(color: Colors.red)),
                  dense: true,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Center: Essential controls (mic, camera)
          _buildMicButton(),
          const SizedBox(width: 8),
          _buildCameraButton(),
          const Spacer(),
          // Right side: placeholder for balance
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildMicButton() {
    final isEnabled = participant.isMicrophoneEnabled();
    return IconButton(
      onPressed: isEnabled ? _disableAudio : _enableAudio,
      icon: Icon(
        isEnabled ? Icons.mic : Icons.mic_off,
        size: 20,
        color: isEnabled ? null : Colors.red,
      ),
      tooltip: isEnabled ? 'Mute' : 'Unmute',
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: isEnabled ? null : Colors.red.withValues(alpha: 0.1),
      ),
    );
  }

  Widget _buildCameraButton() {
    final isEnabled = participant.isCameraEnabled();
    return IconButton(
      onPressed: isEnabled ? _disableVideo : _enableVideo,
      icon: Icon(
        isEnabled ? Icons.videocam : Icons.videocam_off,
        size: 20,
        color: isEnabled ? null : Colors.red,
      ),
      tooltip: isEnabled ? 'Turn off camera' : 'Turn on camera',
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: isEnabled ? null : Colors.red.withValues(alpha: 0.1),
      ),
    );
  }

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'invite':
        _onTapInvite();
        break;
      case 'screen_share':
        _enableScreenShare();
        break;
      case 'screen_share_off':
        _disableScreenShare();
        break;
      case 'configure':
        _showConfigureDialog();
        break;
      case 'leave':
        _onTapDisconnect();
        break;
    }
  }

  void _showConfigureDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configure'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Audio Input
              if (_audioInputs != null && _audioInputs!.isNotEmpty) ...[
                const Text('Microphone',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...(_audioInputs!.map((device) => ListTile(
                      leading: Icon(
                        device.deviceId ==
                                widget.room.selectedAudioInputDeviceId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      title: Text(device.label),
                      onTap: () {
                        _selectAudioInput(device);
                        Navigator.pop(context);
                        _showConfigureDialog();
                      },
                      dense: true,
                    ))),
                const Divider(),
              ],
              // Audio Output
              if (_audioOutputs != null &&
                  _audioOutputs!.isNotEmpty &&
                  !lkPlatformIs(PlatformType.iOS)) ...[
                const Text('Speaker',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...(_audioOutputs!.map((device) => ListTile(
                      leading: Icon(
                        device.deviceId ==
                                widget.room.selectedAudioOutputDeviceId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      title: Text(device.label),
                      onTap: () {
                        _selectAudioOutput(device);
                        Navigator.pop(context);
                        _showConfigureDialog();
                      },
                      dense: true,
                    ))),
                const Divider(),
              ],
              // Video Input
              if (_videoInputs != null && _videoInputs!.isNotEmpty) ...[
                const Text('Camera',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...(_videoInputs!.map((device) => ListTile(
                      leading: Icon(
                        device.deviceId ==
                                widget.room.selectedVideoInputDeviceId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      title: Text(device.label),
                      onTap: () {
                        _selectVideoInput(device);
                        Navigator.pop(context);
                        _showConfigureDialog();
                      },
                      dense: true,
                    ))),
                const Divider(),
              ],
              // Flip Camera
              ListTile(
                leading: Icon(position == CameraPosition.back
                    ? Icons.video_camera_back
                    : Icons.video_camera_front),
                title: const Text('Flip Camera'),
                onTap: () {
                  Navigator.pop(context);
                  _toggleCamera();
                },
                dense: true,
              ),
              // iOS Speakerphone
              if (!kIsWeb && lkPlatformIs(PlatformType.iOS))
                ListTile(
                  leading: Icon(_speakerphoneOn
                      ? Icons.speaker_phone
                      : Icons.phone_android),
                  title: Text(_speakerphoneOn
                      ? 'Switch to Phone Speaker'
                      : 'Switch to Speakerphone'),
                  onTap: Hardware.instance.canSwitchSpeakerphone
                      ? () {
                          Navigator.pop(context);
                          _setSpeakerphoneOn();
                        }
                      : null,
                  dense: true,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
