import 'package:flutter/widgets.dart';

import 'profile.dart';

/// Makes the [Profile] available below it and rebuilds dependents when it
/// changes.
class ProfileScope extends InheritedNotifier<Profile> {
  const ProfileScope({super.key, required Profile profile, required super.child}) : super(notifier: profile);

  static Profile of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProfileScope>()!.notifier!;

  /// Reads the profile without subscribing to changes.
  static Profile read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ProfileScope>()!.notifier!;
}
