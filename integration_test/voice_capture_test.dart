// Talking to the friend: questions typed in (the built-in matcher answers,
// no network), each answered in a speech bubble and shown on screen: a row
// lit up, a card pointed out, the map walked. Reports PNGs, which
// test_driver/integration_test.dart writes to build/captures/.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/voice_capture_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lantern_spirit/app/profile.dart';
import 'package:lantern_spirit/main.dart';
import 'package:lantern_spirit/map/park_map_screen.dart';
import 'package:lantern_spirit/ui/park_screen.dart';

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
    final ui.Image image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    captures['$name.png'] = base64Encode(bytes!.buffer.asUint8List());
  }

  testWidgets('capture voice', (tester) async {
    addTearDown(() => binding.reportData = <String, dynamic>{...captures});
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LanternSpiritApp(profile: Profile.memory())));
    ParkScreenState park() => tester.state<ParkScreenState>(find.byType(ParkScreen));
    for (var i = 0; i < 400 && park().character == null; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    park().autoSurprises = false;
    park().character!.wake();
    await settle(tester, const Duration(milliseconds: 1500));
    final list = find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first;

    var n = 0;
    for (final q in const ['What has the shortest line?', 'When are the fireworks?', 'Where can I eat?']) {
      park().askLumi(q);
      await settle(tester, const Duration(milliseconds: 300));
      await capture(tester, key, 'v_${n}_a_thinking');
      await settle(tester, const Duration(milliseconds: 900));
      await capture(tester, key, 'v_${n}_b_talking');
      await settle(tester, const Duration(milliseconds: 1800));
      await capture(tester, key, 'v_${n}_c_shown');
      for (var i = 0; i < 200 && park().voiceBusy; i++) {
        await settle(tester, const Duration(milliseconds: 50));
      }
      tester.state<ScrollableState>(list).position.jumpTo(0);
      await settle(tester, const Duration(milliseconds: 600));
      n++;
    }

    // Walked there on the map.
    park().askLumi('Take me to Moon Drop');
    await settle(tester, const Duration(milliseconds: 1200));
    await capture(tester, key, 'v_3_b_talking');
    for (var i = 0; i < 200 && find.byType(ParkMapScreen).evaluate().isEmpty; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    await settle(tester, const Duration(milliseconds: 4500));
    await capture(tester, key, 'v_3_c_walking');
  });
}
