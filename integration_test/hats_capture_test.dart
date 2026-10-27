// Hats on the soft head: each friend in a hat, pressed on the crown, pulled
// up and sideways, and released, so clipping or a hat floating off shows up.
// Reports PNGs, which test_driver/integration_test.dart writes to
// build/captures/.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/hats_capture_test.dart \
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

  testWidgets('capture hats on the soft head', (tester) async {
    final key = GlobalKey();
    final profile = Profile.memory()..addKey()..addKey()..addKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LanternSpiritApp(profile: profile)));
    ParkScreenState park() => tester.state<ParkScreenState>(find.byType(ParkScreen));
    for (var i = 0; i < 400 && park().character == null; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    for (final (friend, hat) in const [('lumi', 'party_hat'), ('mochi', 'beanie'), ('juju', 'flower_crown'), ('nova', 'cat_ears')]) {
      profile.chooseFriend(friend);
      profile.wear(hat: hat);
      for (var i = 0; i < 600 && (park().swapping || park().character!.friend.id != friend); i++) {
        await settle(tester, const Duration(milliseconds: 30));
      }
      final c = park().character!..wake();
      await settle(tester, const Duration(milliseconds: 1500));
      await capture(tester, key, 'h_${friend}_rest');
      final head = park().camera.worldToScreen(c.headCenter, park().headerSize)!;
      vm.Ray at(Offset o) => park().camera.screenPointToRay(head + o, park().headerSize);
      // Press on the crown.
      final top = c.grab(park().scene, at(const Offset(0, -40)));
      c.drag(at(const Offset(0, -34)));
      await settle(tester, const Duration(milliseconds: 500));
      await capture(tester, key, 'h_${friend}_press${top ? '' : '_miss'}');
      // Pull up and to the side.
      c.drag(at(const Offset(110, -150)));
      await settle(tester, const Duration(milliseconds: 500));
      await capture(tester, key, 'h_${friend}_pull');
      c.releaseGrab();
      await settle(tester, const Duration(milliseconds: 140));
      await capture(tester, key, 'h_${friend}_snap');
      // Grab a cheek and pull sideways.
      c.grab(park().scene, at(const Offset(-40, 6)));
      c.drag(at(const Offset(-170, 20)));
      await settle(tester, const Duration(milliseconds: 500));
      await capture(tester, key, 'h_${friend}_side');
      c.releaseGrab();
      await settle(tester, const Duration(milliseconds: 1500));
    }
    binding.reportData = <String, dynamic>{...captures};
  });
}
