// The full-screen moments, frame by frame: the lantern pulse, the sneeze
// ripple, the pratfall, lights out, card Jenga, and the peel into 3D.
// Reports PNGs, which test_driver/integration_test.dart writes to
// build/captures/.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/spectacle_capture_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lantern_spirit/app/profile.dart';
import 'package:lantern_spirit/main.dart';
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

  Future<void> frames(WidgetTester tester, GlobalKey key, String name, int count, int everyMs) async {
    for (var i = 0; i < count; i++) {
      await settle(tester, Duration(milliseconds: everyMs));
      await capture(tester, key, '${name}_${i.toString().padLeft(2, '0')}');
    }
  }

  testWidgets('capture spectacle', (tester) async {
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

    park().lanternPulse();
    await frames(tester, key, 'x_pulse', 8, 60);
    await settle(tester, const Duration(milliseconds: 1500));

    park().character!.sneeze();
    await settle(tester, const Duration(milliseconds: 700));
    await frames(tester, key, 'x_ripple', 8, 60);
    await settle(tester, const Duration(milliseconds: 2000));

    park().pratfall();
    await frames(tester, key, 'x_fall', 24, 150);
    await settle(tester, const Duration(milliseconds: 1500));

    park().lightsOut();
    await frames(tester, key, 'x_lights', 3, 700);
    park().lightsOn();
    await settle(tester, const Duration(milliseconds: 1800));

    park().cardJenga();
    await frames(tester, key, 'x_jenga', 30, 220);
    await settle(tester, const Duration(milliseconds: 1500));

    park().peelInto3D();
    await frames(tester, key, 'x_peel', 30, 280);
    await settle(tester, const Duration(milliseconds: 2000));
    await capture(tester, key, 'x_after');
  });
}
