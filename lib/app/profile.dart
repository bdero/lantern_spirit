import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The guest's progress and choices: rewards earned around the app and what
/// Lumi is wearing. Saved on every change.
class Profile extends ChangeNotifier {
  Profile._(this._prefs);

  static Future<Profile> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      // Storage can be unavailable (tests, a sandbox); run in memory then.
      debugPrint('Profile storage unavailable, keeping progress in memory: $e');
    }
    return Profile._(prefs).._read();
  }

  /// An in-memory profile, for render checks, previews, and recordings.
  factory Profile.memory() => Profile._(null);

  final SharedPreferences? _prefs;

  int _keys = 2;
  int _stars = 0;
  int _bestCatch = 0;
  int _bestLift = 0;
  bool _watchedFireworks = false;
  String? _hat;
  bool _scarf = false;
  String _theme = 'Aurora';
  String _friend = 'lumi';
  double _hueShift = 0;
  double _glow = 1;

  int get keys => _keys;
  int get stars => _stars;
  int get bestCatch => _bestCatch;
  int get bestLift => _bestLift;
  bool get watchedFireworks => _watchedFireworks;

  /// The accessory on the head socket, or null.
  String? get hat => _hat;

  /// Whether the scarf is on the neck socket.
  bool get scarf => _scarf;
  String get theme => _theme;

  /// Which friend lives in the app (see lib/lantern/friends.dart).
  String get friend => _friend;
  double get hueShift => _hueShift;
  double get glow => _glow;

  void _read() {
    final p = _prefs;
    if (p == null) return;
    _keys = p.getInt('lantern.rewards.keys') ?? _keys;
    _stars = p.getInt('lantern.rewards.stars') ?? _stars;
    _bestCatch = p.getInt('lantern.rewards.bestCatch') ?? _bestCatch;
    _bestLift = p.getInt('lantern.rewards.bestLift') ?? _bestLift;
    _watchedFireworks = p.getBool('lantern.rewards.fireworks') ?? _watchedFireworks;
    _hat = p.getString('lantern.wardrobe.hat');
    _scarf = p.getBool('lantern.wardrobe.scarf') ?? _scarf;
    _theme = p.getString('lantern.wardrobe.theme') ?? _theme;
    _friend = p.getString('lantern.friend') ?? _friend;
    _hueShift = p.getDouble('lantern.wardrobe.hue') ?? _hueShift;
    _glow = p.getDouble('lantern.wardrobe.glow') ?? _glow;
  }

  void _save() {
    final p = _prefs;
    if (p != null) {
      p.setInt('lantern.rewards.keys', _keys);
      p.setInt('lantern.rewards.stars', _stars);
      p.setInt('lantern.rewards.bestCatch', _bestCatch);
      p.setInt('lantern.rewards.bestLift', _bestLift);
      p.setBool('lantern.rewards.fireworks', _watchedFireworks);
      if (_hat == null) {
        p.remove('lantern.wardrobe.hat');
      } else {
        p.setString('lantern.wardrobe.hat', _hat!);
      }
      p.setBool('lantern.wardrobe.scarf', _scarf);
      p.setString('lantern.wardrobe.theme', _theme);
      p.setString('lantern.friend', _friend);
      p.setDouble('lantern.wardrobe.hue', _hueShift);
      p.setDouble('lantern.wardrobe.glow', _glow);
    }
    notifyListeners();
  }

  void addKey() {
    _keys += 1;
    _save();
  }

  void addStars(int n) {
    _stars += n;
    _save();
  }

  void recordCatch(int score) {
    if (score > _bestCatch) _bestCatch = score;
    _save();
  }

  void recordLift(int meters) {
    if (meters > _bestLift) _bestLift = meters;
    _save();
  }

  void markFireworksWatched() {
    _watchedFireworks = true;
    _save();
  }

  void wear({String? hat, bool clearHat = false, bool? scarf}) {
    if (clearHat) {
      _hat = null;
    } else if (hat != null) {
      _hat = hat;
    }
    if (scarf != null) _scarf = scarf;
    _save();
  }

  void setLook({String? theme, double? hueShift, double? glow}) {
    if (theme != null) _theme = theme;
    if (hueShift != null) _hueShift = hueShift;
    if (glow != null) _glow = glow;
    _save();
  }

  void chooseFriend(String id) {
    if (id == _friend) return;
    _friend = id;
    _save();
  }

  /// Resets progress (from the creative panel), keeping the look.
  void resetProgress() {
    _keys = 2;
    _stars = 0;
    _bestCatch = 0;
    _bestLift = 0;
    _watchedFireworks = false;
    _save();
  }
}
