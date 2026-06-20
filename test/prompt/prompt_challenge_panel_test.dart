import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/prompt/cast_result.dart';
import 'package:tech_world/prompt/predefined_prompt_challenges.dart';
import 'package:tech_world/prompt/prompt_challenge_panel.dart';
import 'package:tech_world/prompt/spell_slot_service.dart';

void main() {
  group('PromptChallengePanel cast button', () {
    late SpellSlotService slots;

    setUp(() {
      slots = SpellSlotService(maxSlots: 3);
    });

    // Dispose inside each test body (not tearDown): draining slots starts a
    // regen Timer.periodic, and flutter_test verifies no Timer is pending when
    // the test body completes — which happens *before* tearDown runs.

    Future<void> pumpPanel(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PromptChallengePanel(
              challenge: fizzBuzzIncantation,
              spellSlotService: slots,
              onCast: (prompt) async =>
                  ('a response', const CastResult(feedback: CastFeedback.resonates)),
              onClose: () {},
            ),
          ),
        ),
      );
    }

    /// Finds the "Cast Spell" ElevatedButton and reports whether it's enabled.
    bool castButtonEnabled(WidgetTester tester) {
      final button = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Cast Spell'),
          matching: find.byType(ElevatedButton),
        ),
      );
      return button.onPressed != null;
    }

    testWidgets('is disabled when the prompt is empty', (tester) async {
      await pumpPanel(tester);
      expect(castButtonEnabled(tester), isFalse);
      slots.dispose();
    });

    testWidgets('becomes enabled as soon as the player types a prompt',
        (tester) async {
      // Regression test: previously the button was gated on the prompt text
      // but nothing rebuilt the widget on text change, so it stayed disabled
      // forever — "you can't click submit".
      await pumpPanel(tester);
      expect(castButtonEnabled(tester), isFalse);

      await tester.enterText(find.byType(TextField), 'Make it print FizzBuzz');
      await tester.pump();

      expect(castButtonEnabled(tester), isTrue,
          reason: 'typing a prompt should enable the Cast Spell button');
      slots.dispose();
    });

    testWidgets('is disabled when there are no spell slots, even with text',
        (tester) async {
      slots.consumeSlot(cost: 3); // drain all 3 slots → starts a regen timer
      // try/finally so a failed expectation still cancels the regen timer,
      // otherwise a pending Timer would cascade into a noisier failure that
      // masks the real assertion.
      try {
        await pumpPanel(tester);

        await tester.enterText(find.byType(TextField), 'Some incantation');
        await tester.pump();

        expect(castButtonEnabled(tester), isFalse,
            reason: 'no slots means no cast regardless of prompt text');
      } finally {
        slots.dispose(); // cancels the regen timer started by consumeSlot
      }
    });
  });
}
