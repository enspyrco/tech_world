import 'package:abstractions/beliefs.dart';

class ChallengeTaskModel implements CoreBeliefs {
  const ChallengeTaskModel({
    required this.title,
    required this.description,
    this.complete,
    this.startMission,
    this.endMission,
  });

  final String title;
  final String description;

  /// null = not started, false = in progress, true = complete
  final bool? complete;
  final Cognition? startMission;
  final Cognition? endMission;

  @override
  ChallengeTaskModel copyWith({
    String? title,
    String? description,
    bool? complete,
    Cognition? startMission,
    Cognition? endMission,
  }) =>
      ChallengeTaskModel(
        title: title ?? this.title,
        description: description ?? this.description,
        complete: complete ?? this.complete,
        startMission: startMission ?? startMission,
        endMission: endMission ?? endMission,
      );

  @override
  toJson() => {
        'title': title,
        'description': description,
        'complete': complete,
        // TODO: do better than dynamic invocation - maybe we need another
        // type... DefaultMission? And use Default across the board to mean
        // has copyWith and toJson ?
        'startMission': (startMission as dynamic).toJson(),
        'endMission': (endMission as dynamic).toJson(),
      };
}
