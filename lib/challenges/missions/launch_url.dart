import 'package:abstractions/beliefs.dart';

import '../../app/state/app_state.dart';

class LaunchUrl extends Consideration<AppState> {
  const LaunchUrl({required this.url});

  final String url;

  @override
  Future<void> consider(BeliefSystem<AppState> beliefSystem) async {}

  @override
  toJson() => {
        'name_': 'LaunchUrl',
        'state_': {'url': url}
      };
}
