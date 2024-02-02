import 'package:abstractions/beliefs.dart';

import '../../app/app_beliefs.dart';
import '../enums/challenge_enum.dart';
import '../models/challenge_model.dart';
import '../models/fix_repo_challenge_model.dart';

class StartChallenge extends Conclusion<AppBeliefs> {
  const StartChallenge({required this.challengeType});

  final ChallengeEnum challengeType;

  @override
  AppBeliefs conclude(AppBeliefs state) {
    ChallengeModel? challenge;
    if (challengeType == ChallengeEnum.fixRepo) {
      challenge = const FixRepoChallengeModel(
        repoUrl: 'https://github.com/adventures-in/devtools_adventure',
        tasks: [],
      );
    }
    return state.copyWith(challenge: challenge);
  }

  @override
  toJson() => {
        'name_': 'StartChallenge',
        'state_': {'challenge-type': challengeType.toString()}
      };
}
