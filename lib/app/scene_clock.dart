import 'package:clock/clock.dart';
import 'package:flutter_scene/scene.dart';

import 'clock.dart';

/// A [SceneView] that runs on [AppClock]: its frame steps are app time, and
/// it advances [scene] by the same step [onTick] gets, so a recording that
/// drives its own clock moves the 3D exactly as much as everything else, and
/// draws every frame of it.
SceneView appSceneView(Scene scene, {Camera? camera, required SceneTickCallback onTick}) => SceneView(
      scene,
      camera: camera,
      clock: Clock(() => AppClock.now),
      onTick: (elapsed, dt) {
        // A recording needs every frame drawn: never re-present the last
        // one while the GPU catches up.
        if (AppClock.manual) scene.maxGpuFramesInFlight = 0;
        onTick(elapsed, dt);
        scene.update(dt);
      },
    );
