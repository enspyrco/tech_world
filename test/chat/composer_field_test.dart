import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/chat/composer_field.dart';

void main() {
  Future<({TextEditingController controller, List<int> sends})> pumpComposer(
    WidgetTester tester, {
    bool enabled = true,
  }) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final sends = <int>[];
    addTearDown(() async {
      // Deflate the tree before disposing the focus node — disposing a node
      // still attached to a mounted Focus widget throws.
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      focusNode.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposerField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            hintText: 'Type a message...',
            onSend: () => sends.add(1),
          ),
        ),
      ),
    );
    return (controller: controller, sends: sends);
  }

  testWidgets('grows from one line up to maxLines', (tester) async {
    final c = await pumpComposer(tester);

    final oneLineHeight = tester.getSize(find.byType(TextField)).height;

    c.controller.text = 'line one\nline two\nline three';
    await tester.pump();
    final threeLineHeight = tester.getSize(find.byType(TextField)).height;
    expect(threeLineHeight, greaterThan(oneLineHeight));

    // Beyond maxLines (5) the field stops growing and scrolls internally.
    c.controller.text = List.generate(5, (i) => 'line $i').join('\n');
    await tester.pump();
    final fiveLineHeight = tester.getSize(find.byType(TextField)).height;
    c.controller.text = List.generate(10, (i) => 'line $i').join('\n');
    await tester.pump();
    final tenLineHeight = tester.getSize(find.byType(TextField)).height;
    expect(tenLineHeight, fiveLineHeight);
  });

  testWidgets('hardware Enter sends without inserting a newline',
      (tester) async {
    final c = await pumpComposer(tester);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(c.sends, hasLength(1));
    expect(c.controller.text, isNot(contains('\n')));
  });

  testWidgets('numpad Enter also sends', (tester) async {
    final c = await pumpComposer(tester);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pump();

    expect(c.sends, hasLength(1));
  });

  testWidgets('Shift+Enter is left to the field (newline), not a send',
      (tester) async {
    final c = await pumpComposer(tester);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    // The interceptor must NOT fire; the actual newline insertion is IME
    // behavior the test environment doesn't simulate for hardware keys.
    expect(c.sends, isEmpty);
  });

  testWidgets('IME send action (onSubmitted) sends', (tester) async {
    final c = await pumpComposer(tester);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(c.sends, hasLength(1));
  });

  testWidgets('Enter while disabled does not send', (tester) async {
    final c = await pumpComposer(tester, enabled: false);

    // A disabled TextField can't take focus/text entry; drive the key event
    // at the window level to prove the interceptor also refuses it.
    c.controller.text = 'hello';
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(c.sends, isEmpty);
  });
}
