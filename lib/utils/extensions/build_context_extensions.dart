import 'package:locator_for_perception/locator_for_perception.dart';
import 'package:flutter/widgets.dart';
import 'package:abstractions/beliefs.dart';

import '../../app/app_beliefs.dart';

// Currently uses the locator meaning there is no need to use an extension
// on BuildContext, however doing so makes it a lot easier if we decide to
// change later (which is quite possible as using the locator seems to have some
// problems, eg. breaks hot reload)

extension BuildContextExtension on BuildContext {
  void conclude(Conclusion<AppBeliefs> conclusion) {
    return locate<BeliefSystem<AppBeliefs>>().conclude(conclusion);
  }

  Future<void> consider(Consideration<AppBeliefs> consideration) {
    return locate<BeliefSystem<AppBeliefs>>().consider(consideration);
  }
}
