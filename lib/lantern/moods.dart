/// The character's states. Each maps to one clip in `assets/lantern.glb`.
enum LanternMood {
  sleepy(clip: 'Sleepy', loops: true, glow: 0.35, face: LanternFace.sleepy, label: 'Sleepy'),
  awake(clip: 'Awake', loops: true, glow: 1.0, face: LanternFace.awake, label: 'Awake'),
  curious(clip: 'Curious', loops: true, glow: 1.05, face: LanternFace.curious, label: 'Curious'),
  poked(clip: 'Poked', loops: false, glow: 1.25, face: LanternFace.poked, label: 'Poked'),
  delighted(clip: 'Delighted', loops: false, glow: 1.55, face: LanternFace.delighted, label: 'Delighted'),
  dizzy(clip: 'Dizzy', loops: true, glow: 0.9, face: LanternFace.dizzy, label: 'Dizzy'),

  /// Sitting at the rail, looking up at the sky.
  watch(clip: 'Watch', loops: true, glow: 1.0, face: LanternFace.wow, label: 'Watch'),

  /// A startle on a bright flash.
  flinch(clip: 'Flinch', loops: false, glow: 1.2, face: LanternFace.surprised, label: 'Flinch'),

  /// A celebration jump with the hands waving overhead.
  cheer(clip: 'Cheer', loops: false, glow: 1.6, face: LanternFace.delighted, label: 'Cheer'),

  /// Content, leaning on the rail.
  lean(clip: 'Lean', loops: true, glow: 0.85, face: LanternFace.content, label: 'Lean'),

  // The four corners of the emotion pad.
  happy(clip: 'Happy', loops: true, glow: 1.45, face: LanternFace.delighted, label: 'Happy'),
  content(clip: 'Content', loops: true, glow: 0.85, face: LanternFace.content, label: 'Content'),
  glum(clip: 'Glum', loops: true, glow: 0.5, face: LanternFace.glum, label: 'Glum'),
  grumpy(clip: 'Grumpy', loops: true, glow: 1.15, face: LanternFace.grumpy, label: 'Grumpy');

  const LanternMood({
    required this.clip,
    required this.loops,
    required this.glow,
    required this.face,
    required this.label,
  });

  /// The clip name in the GLB.
  final String clip;

  /// Loops hold until something changes them; the others play once and
  /// hand back to a resting mood.
  final bool loops;

  /// Glow multiplier while this mood is showing.
  final double glow;

  /// The expression shown on the face cap.
  final LanternFace face;

  final String label;

  /// The states offered as chips in the creative panel.
  static const panelStates = [sleepy, awake, curious, poked, delighted, dizzy];
}

/// Cells of `assets/face_atlas.png`, in atlas order (4 across, 3 down).
enum LanternFace {
  sleepy,
  awake,
  curious,
  poked,
  delighted,
  dizzy,
  blink,
  surprised,
  content,
  glum,
  grumpy,
  wow;

  double get cell => index.toDouble();
}
