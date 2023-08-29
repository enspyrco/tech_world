import 'package:locator_for_perception/locator_for_perception.dart';
import 'package:flutter/widgets.dart';
import 'package:abstractions/beliefs.dart';

import '../../app/state/app_state.dart';

// Currently uses the locator meaning there is no need to use an extension
// on BuildContext, however doing so makes it a lot easier if we decide to
// change later (which is quite possible as using the locator seems to have some
// problems, eg. breaks hot reload)

extension BuildContextExtension on BuildContext {
  void land(Conclusion<AppState> mission) {
    return locate<BeliefSystem<AppState>>().conclude(mission);
  }

  Future<void> launch(Consideration<AppState> mission) {
    return locate<BeliefSystem<AppState>>().consider(mission);
  }
}
