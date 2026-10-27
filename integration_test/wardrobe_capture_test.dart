// Renders Lumi in each accessory and the wardrobe screen, and reports PNGs
// that test_driver/integration_test.dart writes to build/captures/.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/wardrobe_capture_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lantern_spirit/app/profile.dart';
import 'package:lantern_spirit/lantern/wardrobe.dart';
import 'package:lantern_spirit/main.dart';
import 'package:lantern_spirit/ui/park_screen.dart';
import 'package:lantern_spirit/ui/wardrobe_screen.dart';

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

  testWidgets('capture wardrobe', (tester) async {
    final key = GlobalKey();
    final profile = Profile.memory()
      ..addKey()
      ..addKey()
      ..addKey()
      ..markFireworksWatched();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LanternSpiritApp(profile: profile)));
    ParkScreenState state() => tester.state<ParkScreenState>(find.byType(ParkScreen));
    for (var i = 0; i < 400 && state().character == null; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    state().character!.wake();
    await settle(tester, const Duration(milliseconds: 1200));
    for (final a in Wardrobe.hats) {
      profile.wear(hat: a.id, scarf: a.id == 'beanie');
      await settle(tester, const Duration(milliseconds: 1200));
      await capture(tester, key, 'wear_${a.id}');
    }

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute<void>(builder: (_) => const WardrobeScreen()));
    await settle(tester, const Duration(milliseconds: 2500));
    await capture(tester, key, 'wardrobe_hats');
    profile.setLook(hueShift: 120);
    await settle(tester, const Duration(milliseconds: 1500));
    await capture(tester, key, 'wardrobe_hue');
    binding.reportData = <String, dynamic>{...captures};
  });
}
