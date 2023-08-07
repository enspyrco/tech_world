import 'package:types_for_perception/beliefs.dart';

import '../../app/state/app_state.dart';

class LaunchUrl extends AwayMission<AppState> {
  const LaunchUrl({required this.url});

  final String url;

  @override
  Future<void> flightPlan(MissionControl<AppState> missionControl) async {}

  @override
  toJson() => {
        'name_': 'LaunchUrl',
        'state_': {'url': url}
      };
}
