import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/flame/tech_world_game.dart';

/// Made the TechWorldGame a global for now for simplicity
/// TODO: make TechWorldGame accessible to lower widets with InheritedWidget
final techWorldGame = TechWorldGame(world: TechWorld());
