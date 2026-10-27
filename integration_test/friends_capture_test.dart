// Swaps through every friend in the header and reports PNGs of each one
// awake, celebrating, in a hat, and in another color slot, plus the Friends
// tab. test_driver/integration_test.dart writes them to build/captures/.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/friends_capture_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lantern_spirit/app/profile.dart';
import 'package:lantern_spirit/lantern/friends.dart';
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
    final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    captures['$name.png'] = base64Encode(bytes!.buffer.asUint8List());
  }

  testWidgets('capture friends', (tester) async {
    final key = GlobalKey();
    final profile = Profile.memory();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LanternSpiritApp(profile: profile)));
    ParkScreenState park() => tester.state<ParkScreenState>(find.byType(ParkScreen));
    for (var i = 0; i < 400 && park().character == null; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    park().character!.wake();
    await settle(tester, const Duration(milliseconds: 1200));

    for (final f in Friends.all) {
      profile.chooseFriend(f.id);
      // Catch the swap mid-pop once.
      if (f.id == 'juju') {
        for (var i = 0; i < 400 && park().character!.friend.id != f.id; i++) {
          await settle(tester, const Duration(milliseconds: 16));
        }
        await settle(tester, const Duration(milliseconds: 260));
        await capture(tester, key, 'p_swap_mid');
      }
      for (var i = 0; i < 600 && (park().swapping || park().character!.friend.id != f.id); i++) {
        await settle(tester, const Duration(milliseconds: 30));
      }
      await settle(tester, const Duration(milliseconds: 1200));
      await capture(tester, key, 'p_${f.id}_awake');
      park().character!.celebrate();
      await settle(tester, const Duration(milliseconds: 650));
      await capture(tester, key, 'p_${f.id}_delighted');
      await settle(tester, const Duration(milliseconds: 900));
      profile.wear(hat: 'beanie', scarf: true);
      profile.setLook(theme: 'Ember');
      await settle(tester, const Duration(milliseconds: 1600));
      await capture(tester, key, 'p_${f.id}_ember_hat');
      profile.wear(clearHat: true, scarf: false);
      profile.setLook(theme: 'Aurora');
      await settle(tester, const Duration(milliseconds: 900));
    }

    await tester.tap(find.byTooltip('Friends'));
    await settle(tester, const Duration(milliseconds: 900));
    await capture(tester, key, 'p_friends_tab');

    binding.reportData = <String, dynamic>{...captures};
  });
}
