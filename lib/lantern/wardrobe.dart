import '../app/profile.dart';

/// Where an accessory attaches on the rig.
enum Socket { head, neck }

/// One piece of Lumi's wardrobe.
class Accessory {
  const Accessory({
    required this.id,
    required this.name,
    required this.blurb,
    this.socket = Socket.head,
    this.unlockText,
    this.unlocked = _always,
  });

  /// Matches `assets/accessories/<id>.glb`.
  final String id;
  final String name;
  final String blurb;
  final Socket socket;

  /// How to earn it, shown while it is locked.
  final String? unlockText;
  final bool Function(Profile) unlocked;

  String get asset => 'assets/accessories/$id.glb';

  static bool _always(Profile _) => true;
}

/// Everything Lumi can wear. Hats go on the head socket; the scarf on the
/// neck socket and can be worn with any hat.
abstract final class Wardrobe {
  static const hats = [
    Accessory(id: 'star_sprout', name: 'Star sprout', blurb: 'A starter piece. The star glows with Lumi.'),
    Accessory(id: 'beanie', name: 'Beanie', blurb: 'Knit, with a pom-pom that bobs.'),
    Accessory(id: 'flower_crown', name: 'Flower crown', blurb: 'The petals sway as Lumi moves.'),
    Accessory(
      id: 'headphones',
      name: 'Headphones',
      blurb: 'Pearl finish, glowing rings.',
      unlockText: 'Find 3 keys',
      unlocked: _threeKeys,
    ),
    Accessory(
      id: 'cat_ears',
      name: 'Cat ears',
      blurb: 'For the curious.',
      unlockText: 'Find 5 keys',
      unlocked: _fiveKeys,
    ),
    Accessory(
      id: 'party_hat',
      name: 'Party hat',
      blurb: 'The fireworks souvenir.',
      unlockText: 'Watch the fireworks',
      unlocked: _watched,
    ),
  ];

  static const scarf = Accessory(
    id: 'scarf',
    name: 'Scarf',
    blurb: 'Knit, with a tail that trails behind.',
    socket: Socket.neck,
  );

  static Accessory? byId(String? id) {
    if (id == null) return null;
    for (final a in [...hats, scarf]) {
      if (a.id == id) return a;
    }
    return null;
  }

  static bool _threeKeys(Profile p) => p.keys >= 3;
  static bool _fiveKeys(Profile p) => p.keys >= 5;
  static bool _watched(Profile p) => p.watchedFireworks;
}
