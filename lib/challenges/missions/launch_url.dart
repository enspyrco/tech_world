import 'package:abstractions/beliefs.dart';

import '../../app/app_beliefs.dart';

class LaunchUrl extends Consideration<AppBeliefs> {
  const LaunchUrl({required this.url});

  final String url;

  @override
  Future<void> consider(BeliefSystem<AppBeliefs> beliefSystem) async {}

  @override
  toJson() => {
        'name_': 'LaunchUrl',
        'state_': {'url': url}
      };
}
