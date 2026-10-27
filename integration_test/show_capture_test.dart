// Renders the fireworks show paused at its key beats and reports PNGs, which
// test_driver/integration_test.dart writes to build/captures/.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/show_capture_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lantern_spirit/app/profile.dart';
import 'package:lantern_spirit/app/profile_scope.dart';
import 'package:lantern_spirit/show/show_screen.dart';

const beats = <(String, double)>[
  ('show_a_climb', 4.6),
  ('show_b_first_break', 6.35),
  ('show_c_call', 13.0),
  ('show_d_closeup', 18.2),
  ('show_e_build', 33.0),
  ('show_f_finale', 44.2),
  ('show_g_willows', 49.6),
  ('show_h_afterglow', 56.0),
];

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

  testWidgets('capture show beats', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProfileScope(
          profile: Profile.memory(),
          child: const MaterialApp(debugShowCheckedModeBanner: false, home: ShowScreen(autoExit: false)),
        ),
      ),
    );
    ShowScreenState state() => tester.state<ShowScreenState>(find.byType(ShowScreen));
    for (var i = 0; i < 600 && state().director == null; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    final d = state().director!;
    d.playing = false;
    for (final (name, t) in beats) {
      d.seek(t);
      await settle(tester, const Duration(milliseconds: 700));
      await tester.pump();
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      captures['$name.png'] = base64Encode(bytes!.buffer.asUint8List());
    }
    binding.reportData = <String, dynamic>{...captures};
  });
}
