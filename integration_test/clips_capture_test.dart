// Plays every scripted social clip and reports frames all the way through
// each one, so seams and pops show up in a contact sheet.
// test_driver/integration_test.dart writes them to build/captures/.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/clips_capture_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lantern_spirit/app/profile.dart';
import 'package:lantern_spirit/clips/social_clip.dart';
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
    final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    captures['$name.png'] = base64Encode(bytes!.buffer.asUint8List());
  }

  testWidgets('play every clip', (tester) async {
    final key = GlobalKey();
    final profile = Profile.memory()..addKey()..addKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LanternSpiritApp(profile: profile)));
    ParkScreenState park() => tester.state<ParkScreenState>(find.byType(ParkScreen));
    for (var i = 0; i < 400 && park().character == null; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    await settle(tester, const Duration(milliseconds: 1000));
    const every = {
      SocialClip.moon: 2500,
      SocialClip.constellation: 2500,
    };
    for (final clip in SocialClip.values) {
      var done = false;
      park().playClip(clip).then((_) => done = true);
      var n = 0;
      final interval = every[clip] ?? 420;
      final limit = DateTime.now().add(const Duration(seconds: 120));
      while (!done && DateTime.now().isBefore(limit)) {
        await settle(tester, Duration(milliseconds: interval));
        await capture(tester, key, 'c_${clip.name}_${(n++).toString().padLeft(2, '0')}');
      }
      if (clip == SocialClip.fireworks) {
        for (var i = 0; i < 12; i++) {
          await settle(tester, const Duration(milliseconds: 700));
          await capture(tester, key, 'c_${clip.name}_${(n++).toString().padLeft(2, '0')}');
        }
      }
      debugPrint('CLIP ${clip.name}: $n frames, done $done');
      // Back to the park for the next one.
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      while (nav.canPop()) {
        nav.pop();
        await settle(tester, const Duration(milliseconds: 1300));
      }
      await settle(tester, const Duration(milliseconds: 800));
    }
    binding.reportData = <String, dynamic>{...captures};
  });
}
