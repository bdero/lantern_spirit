// Lumi breaking out of the header: the fetch errand into the list, the room
// the header grows into, and the park map. Reports PNGs, which
// test_driver/integration_test.dart writes to build/captures/.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/header_capture_test.dart \
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

  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    await tester.pump();
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    captures['$name.png'] = base64Encode(bytes!.buffer.asUint8List());
  }

  testWidgets('capture breaking the header', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LanternSpiritApp(profile: Profile.memory())));
    ParkScreenState park() => tester.state<ParkScreenState>(find.byType(ParkScreen));
    await until(tester, () => park().character != null);
    park().character!.wake();
    await settle(tester, const Duration(milliseconds: 1500));

    // The fetch errand.
    park().sendLumiForTest();
    for (final (at, name) in const [
      (0.3, 'e0_windup'),
      (0.9, 'e1_dive'),
      (1.7, 'e2_hidden'),
      (2.6, 'e3_peek'),
      (3.2, 'e4_look'),
      (3.95, 'e5_hop'),
      (4.8, 'e6_reach'),
      (5.1, 'e7_press'),
      (5.8, 'e8_key'),
      (6.4, 'e9_home'),
    ]) {
      await until(tester, () => park().errandTime >= at);
      await capture(tester, key, name);
    }
    await until(tester, () => !park().errandActive);
    await settle(tester, const Duration(milliseconds: 700));
    await capture(tester, key, 'e10_back');

    // The room: the header grows into it, then a hat from the shelf, a party.
    await park().openRoomForTest();
    for (final (ms, name) in const [(250, 'r0_opening'), (500, 'r1_opening'), (900, 'r2_open')]) {
      await settle(tester, Duration(milliseconds: ms == 250 ? 250 : (ms == 500 ? 250 : 400)));
      await capture(tester, key, name);
    }
    park().partyForTest();
    await settle(tester, const Duration(milliseconds: 600));
    await capture(tester, key, 'r3_party');
    await settle(tester, const Duration(milliseconds: 1500));
    park().closeRoomForTest();
    await settle(tester, const Duration(milliseconds: 500));
    await capture(tester, key, 'r4_closing');
    await settle(tester, const Duration(milliseconds: 900));
    await capture(tester, key, 'r5_closed');

    // The park map: open it, then send the friend to the shortest wait.
    // Opening scrolls the list to the map card first; keep frames coming.
    park().openMapForTest();
    await settle(tester, const Duration(milliseconds: 500));
    for (var i = 0; i < 400 && (find.byType(ParkMapScreen).evaluate().isEmpty || tester.state<ParkMapScreenState>(find.byType(ParkMapScreen)).lumi == null); i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    await settle(tester, const Duration(milliseconds: 1600));
    await capture(tester, key, 'm0_map');
    final map = tester.state<ParkMapScreenState>(find.byType(ParkMapScreen));
    map.goTo(map.pick);
    await settle(tester, const Duration(milliseconds: 900));
    await capture(tester, key, 'm1_hopping');
    await settle(tester, const Duration(milliseconds: 3500));
    await capture(tester, key, 'm2_arrived');
    map.goTo(map.rides.firstWhere((r) => r.name == 'Moon Drop'));
    await settle(tester, const Duration(milliseconds: 5000));
    await capture(tester, key, 'm3_moon_drop');

    binding.reportData = <String, dynamic>{...captures};
  });
}
