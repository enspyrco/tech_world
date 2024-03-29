import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/app/app_beliefs.dart';
import 'package:tech_world/networking/missions/set_other_player_ids.dart';

void main() {
  group('SetOtherPlayerIdsReducer', () {
    test('should update otherPlayerIds', () {
      const testIds = {'1', '2'};

      final initialState = AppBeliefs.initial;
      expect(initialState.identity.userAuthState.uid, null);

      const mission = SetOtherPlayerIds(testIds);
      var newState = mission.conclude(initialState);

      expect(newState.game.otherPlayerIds, testIds);
    });
  });
}
