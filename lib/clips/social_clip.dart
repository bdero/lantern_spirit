/// The short clips worth recording for social, each one a scripted
/// performance with an on-screen finger, so a recording shows exactly what
/// was touched. Start one from the Clips section of the creative panel.
enum SocialClip {
  fetch('Fetch run', 'Out of the header for the key'),
  taffy('Taffy pull', 'Stretch the head and let it snap'),
  room('Room reveal', 'The header becomes a room'),
  swap('Friend swap', 'All four friends, one after another'),
  moon('Climb to the moon', 'Sky Lift on autopilot'),
  constellation('Constellation', 'Star Catch on autopilot'),
  fireworks('Fireworks dive', 'Into the show from the card'),
  map('Map hop', 'Rides on a 3D park map'),
  shy('Shy', 'Stare too long and it hides its face'),
  sneeze('Sneeze', 'A butterfly, a sneeze, a hat in the air'),
  refresh('Pull to refresh', 'Pulled down after the list'),
  tricks('Tricks', 'Every friend\'s signature trick'),
  booth('Photo booth', 'Strike a pose, take the shot');

  const SocialClip(this.title, this.blurb);
  final String title;
  final String blurb;
}
