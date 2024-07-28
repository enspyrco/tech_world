import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/livekit/pages/room.dart';
import 'package:tech_world/utils/locator.dart';

class FinalPage extends StatelessWidget {
  const FinalPage({required this.room, required this.listener, super.key});

  final Room room;
  final EventsListener<RoomEvent> listener;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 120, child: RoomPage(room, listener)),
        Expanded(
            child: GameWidget(game: TechWorldGame(world: locate<TechWorld>()))),
      ],
    );
  }
}
