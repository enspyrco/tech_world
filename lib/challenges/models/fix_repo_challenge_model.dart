import 'package:abstractions/beliefs.dart';
import 'package:ws_game_server_types/ws_game_server_types.dart';

import 'challenge_model.dart';
import 'challenge_task_model.dart';

class FixRepoChallengeModel with ChallengeModel implements CoreBeliefs {
  const FixRepoChallengeModel({required this.repoUrl, required this.tasks});

  final String repoUrl;
  @override
  final List<ChallengeTaskModel> tasks;

  @override
  FixRepoChallengeModel copyWith({
    String? repoUrl,
    List<ChallengeTaskModel>? tasks,
  }) =>
      FixRepoChallengeModel(
          repoUrl: repoUrl ?? this.repoUrl, tasks: tasks ?? this.tasks);

  @override
  JsonMap toJson() => {};

  @override
  String get typeName => 'FixRepoChallengeModel';
}
