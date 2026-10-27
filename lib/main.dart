import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'app/profile.dart';
import 'app/profile_scope.dart';
import 'clips/touches.dart';
import 'ui/palette.dart';
import 'ui/loading_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final profile = await Profile.load();
  runApp(LanternSpiritApp(profile: profile));
}

class LanternSpiritApp extends StatelessWidget {
  const LanternSpiritApp({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    return ProfileScope(
      profile: profile,
      child: MaterialApp(
        title: 'Lantern Spirit',
        debugShowCheckedModeBanner: false,
        // Drag to scroll with every pointer kind, so a mouse or trackpad can
        // fling the list on desktop the way a finger does on a phone.
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: PointerDeviceKind.values.toSet(),
        ),
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Park.bg,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8FD3FF),
            brightness: Brightness.dark,
            surface: Park.sheet,
          ),
        ),
        // Touches drawn over everything, for screen recordings.
        builder: (context, child) => TouchOverlay(child: child!),
        home: const Boot(),
      ),
    );
  }
}
