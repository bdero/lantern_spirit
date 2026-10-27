// Every new moment: dark mode, shyness under a lingering mouse, the sneeze
// that sends the hat flying, the butterfly, the spark chase, the snowman,
// each friend's trick, pull-to-refresh, the scrollbar ride, the peek, a
// notification, search, weather, time of day, the tumble, and the photo
// booth. Reports PNGs, which test_driver/integration_test.dart writes to
// build/captures/.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/life_capture_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lantern_spirit/app/profile.dart';
import 'package:lantern_spirit/booth/photo_booth_screen.dart';
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

  testWidgets('capture life', (tester) async {
    final key = GlobalKey();
    final profile = Profile.memory()..addKey()..addKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LanternSpiritApp(profile: profile)));
    ParkScreenState park() => tester.state<ParkScreenState>(find.byType(ParkScreen));
    for (var i = 0; i < 400 && park().character == null; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    park().autoSurprises = false;
    final c = park().character!..wake();
    await settle(tester, const Duration(milliseconds: 1200));
    await capture(tester, key, 'l00_dark');

    // Shy: a mouse resting on the head.
    final head = park().headCenterOnScreen()!;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: head + const Offset(0, -6));
    await mouse.moveTo(head);
    await settle(tester, const Duration(milliseconds: 2400));
    await capture(tester, key, 'l01_shy');
    await mouse.moveTo(const Offset(20, 700));
    await mouse.removePointer();
    await settle(tester, const Duration(milliseconds: 800));

    // The sneeze, with a hat on.
    profile.wear(hat: 'beanie');
    await settle(tester, const Duration(milliseconds: 900));
    c.sneeze();
    for (final (ms, n) in const [(500, 'l02_inhale'), (330, 'l03_achoo'), (350, 'l04_hat_up'), (900, 'l05_hat_land'), (1500, 'l06_hat_crooked')]) {
      await settle(tester, Duration(milliseconds: ms));
      await capture(tester, key, n);
    }
    await settle(tester, const Duration(milliseconds: 2500));

    // The butterfly lands, and gets sneezed away.
    park().startButterfly();
    await settle(tester, const Duration(milliseconds: 2900));
    await capture(tester, key, 'l07_butterfly');
    await settle(tester, const Duration(milliseconds: 1500));
    await capture(tester, key, 'l08_butterfly_sneeze');
    await settle(tester, const Duration(milliseconds: 3000));

    // Chasing a spark, and a glow snowman.
    park().startChase();
    await settle(tester, const Duration(milliseconds: 1500));
    await capture(tester, key, 'l09_chase');
    await settle(tester, const Duration(milliseconds: 2400));
    park().buildSnowman();
    await settle(tester, const Duration(milliseconds: 2800));
    await capture(tester, key, 'l10_snowman');

    // Each friend's trick.
    for (final (id, at, n) in const [('lumi', 2200, 'l11_trick_lumi'), ('juju', 1900, 'l12_trick_juju'), ('mochi', 1700, 'l13_trick_mochi'), ('nova', 1200, 'l14_trick_nova')]) {
      profile.chooseFriend(id);
      for (var i = 0; i < 600 && (park().swapping || park().character!.friend.id != id); i++) {
        await settle(tester, const Duration(milliseconds: 30));
      }
      await settle(tester, const Duration(milliseconds: 1500));
      await park().trick();
      await settle(tester, Duration(milliseconds: at));
      await capture(tester, key, n);
      await settle(tester, const Duration(milliseconds: 5000));
    }
    profile.chooseFriend('lumi');
    for (var i = 0; i < 600 && (park().swapping || park().character!.friend.id != 'lumi'); i++) {
      await settle(tester, const Duration(milliseconds: 30));
    }
    await settle(tester, const Duration(milliseconds: 1200));

    // Pull-to-refresh: drag the list down past its top and hold.
    final list = find.byType(ListView).first;
    final from = tester.getTopLeft(list) + const Offset(180, 40);
    final pull = await tester.startGesture(from);
    for (var i = 0; i < 20; i++) {
      await pull.moveBy(const Offset(0, 12));
      await settle(tester, const Duration(milliseconds: 30));
    }
    await settle(tester, const Duration(milliseconds: 300));
    await capture(tester, key, 'l15_pull');
    await pull.up();
    await settle(tester, const Duration(milliseconds: 500));
    await capture(tester, key, 'l16_refreshed');
    await settle(tester, const Duration(milliseconds: 1500));

    // A long drag: the friend hops onto the scrollbar for a ride.
    final drag = await tester.startGesture(tester.getCenter(list));
    for (var i = 0; i < 30; i++) {
      await drag.moveBy(const Offset(0, -14));
      await settle(tester, const Duration(milliseconds: 40));
    }
    await settle(tester, const Duration(milliseconds: 700));
    await capture(tester, key, 'l17_ride');
    for (var i = 0; i < 20; i++) {
      await drag.moveBy(const Offset(0, -30));
      await settle(tester, const Duration(milliseconds: 40));
    }
    await drag.up();
    await settle(tester, const Duration(milliseconds: 600));
    await capture(tester, key, 'l18_ride_bottom');
    await settle(tester, const Duration(milliseconds: 3500));
    await tester.drag(list, const Offset(0, 2000));
    await settle(tester, const Duration(milliseconds: 1500));

    // A peek from behind a card.
    park().peekForTest();
    await settle(tester, const Duration(milliseconds: 2500));
    await capture(tester, key, 'l19_peek');
    await settle(tester, const Duration(milliseconds: 3200));

    // A notification caught and read.
    park().notify();
    await settle(tester, const Duration(milliseconds: 1500));
    await capture(tester, key, 'l20_toast');
    await settle(tester, const Duration(milliseconds: 1800));
    await capture(tester, key, 'l21_toast_toss');
    await settle(tester, const Duration(milliseconds: 1200));

    // Search: type, and the friend throws a sparkle at the match.
    await tester.enterText(find.byType(TextField), 'moon');
    await settle(tester, const Duration(milliseconds: 1250));
    await capture(tester, key, 'l22_search_sparkle');
    await settle(tester, const Duration(milliseconds: 700));
    await capture(tester, key, 'l23_search_found');
    await tester.drag(list, const Offset(0, 2000));
    await settle(tester, const Duration(milliseconds: 1500));
    await tester.enterText(find.byType(TextField), '');
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester, const Duration(milliseconds: 500));

    // Weather, and the time of day.
    park().setWeather(WeatherKind.rain);
    await settle(tester, const Duration(milliseconds: 1500));
    await capture(tester, key, 'l24_rain');
    park().setWeather(WeatherKind.heat);
    await settle(tester, const Duration(milliseconds: 1800));
    await capture(tester, key, 'l25_heat');
    park().setWeather(WeatherKind.clear);
    park().setDayPart(DayPart.morning);
    await settle(tester, const Duration(milliseconds: 2200));
    await capture(tester, key, 'l26_morning');
    park().setDayPart(DayPart.night);
    await settle(tester, const Duration(milliseconds: 1200));
    await capture(tester, key, 'l27_night');
    park().setDayPart(DayPart.auto);

    // The tumble.
    park().character!.tumble();
    await settle(tester, const Duration(milliseconds: 380));
    await capture(tester, key, 'l28_tumble');
    await settle(tester, const Duration(milliseconds: 1500));

    // The room, after the concept.
    await park().openRoomForTest();
    await settle(tester, const Duration(milliseconds: 2000));
    await capture(tester, key, 'l29_room');
    park().closeRoomForTest();
    await settle(tester, const Duration(milliseconds: 1500));

    // The photo booth.
    park().openBoothForTest();
    await settle(tester, const Duration(milliseconds: 600));
    PhotoBoothScreenState booth() => tester.state<PhotoBoothScreenState>(find.byType(PhotoBoothScreen));
    for (var i = 0; i < 400 && booth().lumi == null; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    await settle(tester, const Duration(milliseconds: 2500));
    await capture(tester, key, 'l30_booth_fireworks');
    for (final (b, n) in [(Backdrop.moon, 'l31_booth_moon'), (Backdrop.aurora, 'l32_booth_aurora'), (Backdrop.room, 'l33_booth_room')]) {
      await tester.tap(find.text(b.label));
      await settle(tester, const Duration(milliseconds: 1800));
      await capture(tester, key, n);
    }
    await tester.tap(find.text('Cheer'));
    await tester.tap(find.text('Fireworks'));
    await settle(tester, const Duration(milliseconds: 1500));
    await booth().shoot();
    await settle(tester, const Duration(milliseconds: 1200));
    await capture(tester, key, 'l34_polaroid');
    await booth().save();
    await settle(tester, const Duration(milliseconds: 300));
    await capture(tester, key, 'l35_saved');

    binding.reportData = <String, dynamic>{...captures};
  });
}
