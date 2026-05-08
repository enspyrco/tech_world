import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/bot_status.dart';

void main() {
  test('BotStatus enum has three values', () {
    expect(BotStatus.values.length, 3);
    expect(BotStatus.values, containsAll([
      BotStatus.absent,
      BotStatus.idle,
      BotStatus.thinking,
    ]));
  });
}
