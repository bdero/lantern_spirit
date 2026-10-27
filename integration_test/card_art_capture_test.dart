// Renders the stills used on the park's cards: the fireworks finale over the
// lagoon (assets/ui/tonight.jpg) and the park map (assets/ui/park_map.jpg).
// The PNGs land in build/captures/; crop and convert them into assets/ui/.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/card_art_capture_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lantern_spirit/app/profile.dart';
import 'package:lantern_spirit/app/profile_scope.dart';
import 'package:lantern_spirit/map/park_map_screen.dart';
import 'package:lantern_spirit/show/show_screen.dart';

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
    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    captures['$name.png'] = base64Encode(bytes!.buffer.asUint8List());
  }

  Widget framed(GlobalKey key, Size size, Widget child) => ProfileScope(
        profile: Profile.memory(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Center(
            child: RepaintBoundary(key: key, child: SizedBox.fromSize(size: size, child: child)),
          ),
        ),
      );

  testWidgets('capture card art', (tester) async {
    // The finale, framed wide so the bursts, the skyline, and the water all
    // fit the card.
    final showKey = GlobalKey();
    await tester.pumpWidget(framed(showKey, const Size(410, 700), const ShowScreen(autoExit: false)));
    ShowScreenState show() => tester.state<ShowScreenState>(find.byType(ShowScreen));
    for (var i = 0; i < 600 && show().director == null; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    final d = show().director!;
    d.playing = false;
    for (final t in const [43.4, 44.2, 45.0]) {
      d.seek(t);
      await settle(tester, const Duration(milliseconds: 700));
      await capture(tester, showKey, 'card_tonight_${(t * 10).round()}');
    }

    // The map, once the friend is in and the rides are turning.
    await tester.pumpWidget(const SizedBox());
    await settle(tester, const Duration(milliseconds: 300));
    final mapKey = GlobalKey();
    await tester.pumpWidget(framed(mapKey, const Size(400, 280), const ParkMapScreen(chrome: false, holdZoom: 0.45)));
    for (var i = 0; i < 600 && tester.state<ParkMapScreenState>(find.byType(ParkMapScreen)).lumi == null; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    await settle(tester, const Duration(milliseconds: 2500));
    await capture(tester, mapKey, 'card_map');
    await settle(tester, const Duration(milliseconds: 1500));
    await capture(tester, mapKey, 'card_map_b');
    binding.reportData = <String, dynamic>{...captures};
  });
}
