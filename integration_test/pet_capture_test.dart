// Petting: strokes across the crown, hearts, the purr, and the slide into a
// sleepy trance, then waking from it. Also checks the friend faces where it
// walks on the park map (prints the worst angle between facing and travel),
// the snap back after a hard stretch, and Juju's split trick frame by frame.
// Reports PNGs, which test_driver/integration_test.dart writes to
// build/captures/.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/pet_capture_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:math' as math;
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

  testWidgets('capture petting', (tester) async {
    addTearDown(() => binding.reportData = <String, dynamic>{...captures});
    final key = GlobalKey();
    final profile = Profile.memory();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LanternSpiritApp(profile: profile)));
    ParkScreenState park() => tester.state<ParkScreenState>(find.byType(ParkScreen));
    for (var i = 0; i < 400 && park().character == null; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    park().autoSurprises = false;
    park().character!.wake();
    await settle(tester, const Duration(milliseconds: 1500));

    // Slow strokes back and forth across the crown, capturing as it melts.
    final crown = park().crownForTest()!;
    final hand = await tester.startGesture(crown + const Offset(-30, 6));
    var shot = 0;
    for (var stroke = 0; stroke < 26; stroke++) {
      final dir = stroke.isEven ? 1.0 : -1.0;
      for (var k = 0; k < 10; k++) {
        await hand.moveBy(Offset(6 * dir, math.sin(k / 9 * math.pi) * -1.5));
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (stroke % 5 == 2) await capture(tester, key, 'q_pet_${(shot++).toString().padLeft(2, '0')}');
    }
    await hand.up();
    for (var i = 0; i < 4; i++) {
      await settle(tester, const Duration(milliseconds: 1500));
      await capture(tester, key, 'q_after_${i.toString().padLeft(2, '0')}');
    }
    await settle(tester, const Duration(milliseconds: 6000));
    await capture(tester, key, 'q_awake');

    // A hard stretch and let go: the snap whips the friend round, dizzy.
    final head = park().headCenterOnScreen()!;
    final pull = await tester.startGesture(head + const Offset(30, 10));
    for (var k = 0; k < 20; k++) {
      await pull.moveBy(const Offset(9, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    await capture(tester, key, 'q_stretch');
    await pull.up();
    for (var i = 0; i < 14; i++) {
      await settle(tester, const Duration(milliseconds: 70));
      await capture(tester, key, 'q_snap_${i.toString().padLeft(2, '0')}');
    }
    await settle(tester, const Duration(milliseconds: 2500));

    // Juju's split, frame by frame.
    profile.chooseFriend('juju');
    await settle(tester, const Duration(milliseconds: 3000));
    park().character!.wake();
    park().trick();
    await settle(tester, const Duration(milliseconds: 600));
    for (var i = 0; i < 28; i++) {
      await settle(tester, const Duration(milliseconds: 90));
      await capture(tester, key, 'q_split_${i.toString().padLeft(2, '0')}');
    }
    await settle(tester, const Duration(milliseconds: 2000));
    profile.chooseFriend('lumi');
    await settle(tester, const Duration(milliseconds: 3000));

    // The map: facing where it walks.
    park().openMapForTest();
    for (var i = 0; i < 400 && (find.byType(ParkMapScreen).evaluate().isEmpty || tester.state<ParkMapScreenState>(find.byType(ParkMapScreen)).lumi == null); i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    await settle(tester, const Duration(milliseconds: 1500));
    final map = tester.state<ParkMapScreenState>(find.byType(ParkMapScreen));
    var worst = 0.0;
    var total = 0.0;
    var count = 0;
    for (final name in const ['Tidal Twist', 'Star Swing', 'River Run', 'Sky Coaster']) {
      map.goTo(map.rides.firstWhere((r) => r.name == name));
      var last = map.positionForTest.clone();
      for (var i = 0; i < 600 && map.travelling; i++) {
        await settle(tester, const Duration(milliseconds: 30));
        final p = map.positionForTest;
        final step = p - last;
        last = p.clone();
        if (step.length < 0.01) continue;
        final yaw = map.yawForTest;
        final face = math.atan2(-math.sin(yaw), -math.cos(yaw));
        var off = (face - math.atan2(step.x, step.z)).abs() % (math.pi * 2);
        if (off > math.pi) off = math.pi * 2 - off;
        worst = math.max(worst, off);
        total += off;
        count++;
      }
      if (name == 'Star Swing') await capture(tester, key, 'q_map_walk');
    }
    debugPrint('PET map facing worst angle ${(worst * 180 / math.pi).toStringAsFixed(0)} deg, average ${(total / math.max(count, 1) * 180 / math.pi).toStringAsFixed(1)} deg');
  });
}
