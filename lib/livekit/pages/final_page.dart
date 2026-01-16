import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/livekit/widgets/controls.dart';
import 'package:tech_world/utils/locator.dart';

class FinalPage extends StatefulWidget {
  const FinalPage({required this.room, required this.listener, super.key});

  final Room room;
  final EventsListener<RoomEvent> listener;

  @override
  State<FinalPage> createState() => _FinalPageState();
}

class _FinalPageState extends State<FinalPage> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GameWidget(game: locate<TechWorldGame>()),
        ),
        if (widget.room.localParticipant != null)
          SafeArea(
            top: false,
            child: ControlsWidget(widget.room, widget.room.localParticipant!),
          ),
      ],
    );
  }
}
