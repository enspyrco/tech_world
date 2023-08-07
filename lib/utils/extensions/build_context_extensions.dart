import 'package:locator_for_perception/locator_for_perception.dart';
import 'package:flutter/widgets.dart';
import 'package:types_for_perception/beliefs.dart';

import '../../app/state/app_state.dart';

// Currently uses the locator meaning there is no need to use an extension
// on BuildContext, however doing so makes it a lot easier if we decide to
// change later (which is quite possible as using the locator seems to have some
// problems, eg. breaks hot reload)

extension BuildContextExtension on BuildContext {
  void land(LandingMission<AppState> mission) {
    return locate<MissionControl<AppState>>().land(mission);
  }

  Future<void> launch(AwayMission<AppState> mission) {
    return locate<MissionControl<AppState>>().launch(mission);
  }
}
