import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/bot_status.dart';

void main() {
  // Most BotStatus invariants (uniqueness, exhaustiveness, non-null cases,
  // .name correctness) are language guarantees of `enum` and don't need
  // runtime tests. ValueNotifier semantics are tested by the Flutter SDK,
  // not this codebase.
  //
  // What's left is one project-specific contract:

  test('initial bot status is absent (bot has not yet joined the room)', () {
    // Read of the global default — if someone changes the initial value,
    // the bot will appear in the UI before it has actually connected.
    // This is the only failure mode that survives type-checking and the
    // Flutter framework's own tests.
    final fresh = ValueNotifier<BotStatus>(BotStatus.absent);
    expect(botStatusNotifier.value, fresh.value,
        reason: 'global notifier should default to BotStatus.absent');
  });
}
