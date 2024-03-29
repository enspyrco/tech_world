import 'package:flutter/material.dart';
import 'package:abstractions/beliefs.dart';

import '../models/challenge_task_model.dart';

class ChallengeStep extends Step {
  ChallengeStep(ChallengeTaskModel task, {Key? key})
      : _task = task,
        super(title: Text(task.title), content: Text(task.description));

  final ChallengeTaskModel _task;

  Cognition? get startMission => _task.startMission;
  Cognition? get endMission => _task.endMission;
}
