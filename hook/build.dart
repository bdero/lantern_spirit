import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) {
  build(args, (input, output) async {
    // The character, authored as a GLB with one named clip per state.
    buildScenes(
      buildInput: input,
      buildOutput: output,
      inputFilePaths: const [
        'assets/lantern.glb',
        // The wardrobe, one GLB per accessory.
        'assets/accessories/star_sprout.glb',
        'assets/accessories/beanie.glb',
        'assets/accessories/flower_crown.glb',
        'assets/accessories/headphones.glb',
        'assets/accessories/cat_ears.glb',
        'assets/accessories/party_hat.glb',
        'assets/accessories/scarf.glb',
      ],
    );
    // Skin, face, and ember materials (assets/**/*.fmat).
    await buildMaterials(buildInput: input, buildOutput: output);
  });
}
