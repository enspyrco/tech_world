import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/livekit/pages/room.dart';
import 'package:tech_world/livekit/widgets/proximity_video_overlay.dart';
import 'package:tech_world/proximity/proximity_service.dart';
import 'package:tech_world/utils/locator.dart';

class FinalPage extends StatefulWidget {
  const FinalPage({required this.room, required this.listener, super.key});

  final Room room;
  final EventsListener<RoomEvent> listener;

  @override
  State<FinalPage> createState() => _FinalPageState();
}

class _FinalPageState extends State<FinalPage> {
  late final TechWorld _techWorld;
  late final TechWorldGame _game;
  late final ProximityService _proximityService;

  @override
  void initState() {
    super.initState();
    _techWorld = locate<TechWorld>();
    _game = TechWorldGame(world: _techWorld);
    _proximityService = ProximityService(proximityThreshold: 3);
  }

  @override
  void dispose() {
    _proximityService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 120, child: RoomPage(widget.room, widget.listener)),
        Expanded(
          child: Stack(
            children: [
              GameWidget(game: _game),
              ProximityVideoOverlay(
                room: widget.room,
                techWorld: _techWorld,
                proximityService: _proximityService,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
