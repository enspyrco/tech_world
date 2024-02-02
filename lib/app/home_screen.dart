import 'package:flutterfire_firebase_auth_for_perception/flutterfire_firebase_auth_for_perception.dart';
import 'package:percepts/percepts.dart';
import 'package:locator_for_perception/locator_for_perception.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../challenges/enums/challenge_enum.dart';
import '../challenges/missions/dismiss_challenge.dart';
import '../challenges/missions/start_challenge.dart';
import '../challenges/models/challenge_model.dart';
import '../challenges/widgets/challenge_stepper.dart';
import '../game/tech_world_game.dart';
import '../utils/extensions/build_context_extensions.dart';
import 'state/app_state.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamOfConsciousness<AppState, ChallengeModel?>(
      infer: (state) => state.challenge,
      builder: (context, challenge) {
        return Scaffold(
          appBar: AppBar(
            actions: [
              if (challenge == null)
                const StartChallengeButton()
              else
                const DismissChallengeButton(),
              const AvatarMenuButton<AppState>(
                options: {MenuOption('Sign Out', SigningOut<AppState>())},
              ),
            ],
          ),
          body: Stack(
            children: [
              GameWidget(game: locate<TechWorldGame>()),
              if (challenge != null) ChallengeStepper(challenge)
            ],
          ),
        );
      },
    );
  }
}

class StartChallengeButton extends StatelessWidget {
  const StartChallengeButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      child: const Text('+'),
      onPressed: () => context.conclude(
        const StartChallenge(challengeType: ChallengeEnum.fixRepo),
      ),
    );
  }
}

class DismissChallengeButton extends StatelessWidget {
  const DismissChallengeButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      child: const Text('X'),
      onPressed: () => context.conclude(const DismissChallenge()),
    );
  }
}
