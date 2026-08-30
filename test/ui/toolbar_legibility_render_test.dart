import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/main.dart' show toolbarButtonStyle, toolbarIconColor;

/// Renders the toolbar buttons over the backgrounds they actually sit on and
/// writes a PNG for a human to look at.
///
/// Legibility is a claim about what an eye can distinguish, so nothing asserted
/// here can settle it — the IMAGE is the deliverable, not the green tick. What
/// the harness buys is control: the live map may never happen to put a button
/// over its worst-case ground, while these swatches ARE the extremes (near
/// black floor, pale brick) plus the mid-tones between. Survive all six and you
/// survive the map.
///
/// Out: $TOOLBAR_RENDER_OUT, else the system temp dir. Path is printed.
void main() {
  const backgrounds = <String, Color>{
    'void black': Color(0xFF000000),
    'dark floor': Color(0xFF14121A),
    'mid stone': Color(0xFF6B6357),
    'pale brick': Color(0xFFC9BCA4),
    'bright sand': Color(0xFFE8DCC0),
    'pure white': Color(0xFFFFFFFF),
  };

  Widget btn(IconData icon, Color? accent) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: IconButton(
          onPressed: () {},
          icon: Icon(icon, color: toolbarIconColor(accent: accent), size: 20),
          style: toolbarButtonStyle(accent: accent),
        ),
      );

  testWidgets('toolbar buttons over every background they can land on',
      (tester) async {
    tester.view.physicalSize = const Size(900, 760);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    late int pngBytes;
    final out = Platform.environment['TOOLBAR_RENDER_OUT'] ??
        '${Directory.systemTemp.path}/toolbar_legibility.png';

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Material(
          child: RepaintBoundary(
            key: const Key('sheet'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in backgrounds.entries)
                  Container(
                    width: 420,
                    height: 56,
                    color: e.value,
                    alignment: Alignment.center,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      btn(Icons.arrow_back, null),
                      btn(Icons.mic_off, Colors.red.shade300),
                      btn(Icons.volume_off, Colors.amber.shade300),
                      btn(Icons.menu_book, const Color(0xFFB388FF)),
                      btn(Icons.videocam, null),
                    ]),
                  ),
              ],
            ),
          ),
        ),
      ));
      // NOT pumpAndSettle: inside runAsync it waits on a real clock the test
      // binding never advances, and hangs. Two explicit pumps are enough for a
      // static sheet with no in-flight animation.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));

      final boundary = tester
          .renderObject<RenderRepaintBoundary>(find.byKey(const Key('sheet')));
      final image = await boundary.toImage(pixelRatio: 2.0);
      // Encode AND write inside runAsync. toByteData is a real engine
      // round-trip; awaiting it outside leaves the test "did not complete"
      // AFTER the PNG has already landed on disk — a hang that looks exactly
      // like success if you only check for the file.
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      pngBytes = png!.lengthInBytes;
      File(out).writeAsBytesSync(png.buffer.asUint8List());
      // ignore: avoid_print
      print('TOOLBAR_RENDER_WRITTEN: $out');
    });

    // The one mechanical check worth making: something was actually drawn. A
    // blank sheet would otherwise be indistinguishable from a pass.
    expect(pngBytes, greaterThan(2000));
  });
}
