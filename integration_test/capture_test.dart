// Renders the app in each character state and reports the frames as PNGs,
// which test_driver/integration_test.dart writes to build/captures/.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/capture_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu
//
// No input is synthesized beyond calls on the character itself; this is a
// render check, not a UI test.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lantern_spirit/app/profile.dart';
import 'package:lantern_spirit/lantern/moods.dart';
import 'package:lantern_spirit/lantern/themes.dart';
import 'package:lantern_spirit/main.dart';
import 'package:lantern_spirit/ui/park_screen.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final captures = <String, String>{};

  Future<void> settle(WidgetTester tester, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    await tester.pump();
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    captures['$name.png'] = base64Encode(bytes!.buffer.asUint8List());
  }

  testWidgets('capture character states', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: LanternSpiritApp(profile: Profile.memory())),
    );

    ParkScreenState state() => tester.state<ParkScreenState>(find.byType(ParkScreen));
    for (var i = 0; i < 400 && state().character == null; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    final c = state().character!;
    await settle(tester, const Duration(seconds: 2));
    await capture(tester, key, '0_sleepy');

    c.wake();
    await settle(tester, const Duration(milliseconds: 1500));
    await capture(tester, key, '1_awake');

    c.lookToward(vm.Vector2(-0.9, 0.1));
    await settle(tester, const Duration(milliseconds: 900));
    await capture(tester, key, '2_curious_left');
    c.lookToward(null);
    await settle(tester, const Duration(milliseconds: 700));

    // A poke on the upper-left of the head, as the camera sees it.
    final head = state().camera.worldToScreen(c.headCenter, state().headerSize)!;
    final ray = state().camera.screenPointToRay(head + const Offset(-22, -26), state().headerSize);
    final hit = c.poke(state().scene, ray);
    await settle(tester, const Duration(milliseconds: 90));
    await capture(tester, key, '3_poked_${hit ? 'hit' : 'miss'}');
    await settle(tester, const Duration(milliseconds: 1400));

    // Press and hold near the face, then pull up and to the right.
    vm.Ray at(Offset o) => state().camera.screenPointToRay(head + o, state().headerSize);
    final grabbed = c.grab(state().scene, at(const Offset(-10, -18)));
    c.drag(at(const Offset(-8, -10)));
    await settle(tester, const Duration(milliseconds: 500));
    expect(grabbed, isTrue);
    await capture(tester, key, '3b_pressed');
    c.drag(at(const Offset(120, -110)));
    await settle(tester, const Duration(milliseconds: 500));
    await capture(tester, key, '3c_pulled');
    c.releaseGrab();
    await settle(tester, const Duration(milliseconds: 120));
    await capture(tester, key, '3d_released');
    await settle(tester, const Duration(milliseconds: 1500));

    // The emotion pad, pushed into the grumpy corner and then the content one.
    state().setMoodPad(true);
    state().mood.setValues(-0.9, 0.85);
    await settle(tester, const Duration(milliseconds: 1500));
    await capture(tester, key, '3e_mood_grumpy');
    state().mood.setValues(0.9, -0.9);
    await settle(tester, const Duration(milliseconds: 1500));
    await capture(tester, key, '3f_mood_content');
    state().setMoodPad(false);
    await settle(tester, const Duration(milliseconds: 800));

    c.celebrate();
    await settle(tester, const Duration(milliseconds: 560));
    await capture(tester, key, '4_delighted');
    await settle(tester, const Duration(milliseconds: 1600));

    c.setMood(LanternMood.dizzy);
    await settle(tester, const Duration(milliseconds: 700));
    await capture(tester, key, '5_dizzy');
    await settle(tester, const Duration(milliseconds: 1800));

    c.setTheme(LanternTheme.ember);
    await settle(tester, const Duration(milliseconds: 1500));
    await capture(tester, key, '6_theme_ember');
    c.setTheme(LanternTheme.ghost);
    await settle(tester, const Duration(milliseconds: 1500));
    await capture(tester, key, '7_theme_ghost');
    c.setTheme(LanternTheme.aurora);

    c.explodeTarget = 1;
    await settle(tester, const Duration(milliseconds: 1200));
    await capture(tester, key, '8_exploded');
    c.explodeTarget = 0;

    // Open the show from the Tonight card and catch the dive mid-flight.
    state().openShowForTest();
    await settle(tester, const Duration(milliseconds: 420));
    await capture(tester, key, '10_dive_mid');
    await settle(tester, const Duration(milliseconds: 2600));
    await capture(tester, key, '11_show_open');
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pop();
    await settle(tester, const Duration(milliseconds: 1200));

    state().setPanelOpen(true);
    await settle(tester, const Duration(milliseconds: 800));
    await capture(tester, key, '9_panel');

    binding.reportData = <String, dynamic>{...captures};
  });
}
