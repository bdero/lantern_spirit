import 'package:flutter/material.dart';

import 'package:vector_math/vector_math.dart' as vm;

import '../app/sfx.dart';
import '../clips/social_clip.dart';
import '../lantern/character.dart';
import '../lantern/moods.dart';
import '../lantern/themes.dart';

/// A drawer over the bottom of the screen that shows what drives the
/// character and lets a creative team play with it: jump to any state with
/// the real crossfade, watch the clip weights blend, and tune the timing,
/// glow, and deformer live.
class CreativePanel extends StatelessWidget {
  const CreativePanel({
    super.key,
    required this.open,
    required this.character,
    required this.frameTick,
    required this.onClose,
    required this.moodPadOn,
    required this.onMoodPad,
    required this.mood,
    required this.lookingAt,
    required this.onClip,
    required this.showTouches,
    required this.onShowTouches,
    required this.day,
    required this.onDay,
    required this.moments,
  });

  /// The time of day (index into auto, morning, day, evening, night).
  final Enum day;
  final void Function(dynamic) onDay;

  /// Little moments to trigger by hand: tricks, surprises, reactions.
  final Map<String, VoidCallback> moments;

  /// Plays one of the scripted clips for recording.
  final void Function(SocialClip clip) onClip;
  final bool showTouches;
  final ValueChanged<bool> onShowTouches;

  final bool moodPadOn;
  final ValueChanged<bool> onMoodPad;

  /// The emotion pad point (x mood, y energy, each -1..1), edited in place.
  final vm.Vector2 mood;

  /// What Lumi is paying attention to.
  final String Function() lookingAt;

  final bool open;
  final LanternCharacter? character;
  final ValueNotifier<int> frameTick;
  final VoidCallback onClose;

  static const _bg = Color(0xF00C122C);
  static const _line = Color(0xFF2A3566);
  static const _text = Color(0xFFE9EEFC);
  static const _muted = Color(0xFF95A2C8);
  static const _accent = Color(0xFF8FD3FF);
  static const _violet = Color(0xFF9D84FF);

  @override
  Widget build(BuildContext context) {
    final c = character;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      bottom: open ? 0 : -560,
      height: 520,
      child: Material(
        color: _bg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          side: BorderSide(color: _line),
        ),
        clipBehavior: Clip.antiAlias,
        child: c == null
            ? const SizedBox.shrink()
            : ValueListenableBuilder<int>(
                valueListenable: frameTick,
                builder: (context, _, _) => ListView(
                  padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + bottomInset),
                  children: [
                    Row(
                      children: [
                        const Text('Creative panel', style: TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: onClose,
                          icon: const Icon(Icons.close_rounded, color: _muted),
                        ),
                      ],
                    ),
                    _label('CLIPS TO RECORD'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final clip in SocialClip.values)
                          Tooltip(message: clip.blurb, child: _chip(clip.title, false, () => onClip(clip))),
                      ],
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: showTouches,
                      onChanged: onShowTouches,
                      activeTrackColor: _accent,
                      title: const Text('Show touches', style: TextStyle(color: _text, fontSize: 15)),
                      subtitle: const Text('Draw your own touches too, for screen recordings', style: TextStyle(color: _muted, fontSize: 12.5)),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: Sfx.mute,
                      builder: (context, muted, _) => SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: !muted,
                        onChanged: (on) {
                          Sfx.mute.value = !on;
                          Sfx.sound('toggle');
                        },
                        activeTrackColor: _accent,
                        title: const Text('Sound', style: TextStyle(color: _text, fontSize: 15)),
                        subtitle: const Text('Every little interaction has its own sound', style: TextStyle(color: _muted, fontSize: 12.5)),
                      ),
                    ),
                    _label('MOMENTS'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [for (final m in moments.entries) _chip(m.key, false, m.value)],
                    ),
                    _label('TIME OF DAY'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final d in _days)
                          _chip(d.$2, d.$1 == day.index, () => onDay(d.$1)),
                      ],
                    ),
                    _label('STATE'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in LanternMood.panelStates)
                          _chip(m.label, m == c.mood, () {
                            if (m == LanternMood.delighted) {
                              c.celebrate();
                            } else {
                              c.wake();
                              c.setMood(m);
                            }
                          }),
                      ],
                    ),
                    _label('CLIP WEIGHTS'),
                    for (final m in LanternMood.values)
                      if (c.weights[m]! > 0.004 || m == c.mood) _weight(m.clip, c.weights[m]!),
                    _label('EMOTION'),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: moodPadOn,
                      onChanged: onMoodPad,
                      activeTrackColor: _accent,
                      title: const Text('Mood blend', style: TextStyle(color: _text, fontSize: 15)),
                      subtitle: const Text(
                        'Rest as a blend of four moods; rewards and pokes move it',
                        style: TextStyle(color: _muted, fontSize: 12.5),
                      ),
                    ),
                    if (moodPadOn) _MoodPad(mood: mood, character: c),
                    const SizedBox(height: 6),
                    Text('Looking at: ${lookingAt()}', style: const TextStyle(color: _muted, fontSize: 13)),
                    _label('TUNING'),
                    _slider('Fade', c.fadeSeconds, 0.05, 1.0, '${c.fadeSeconds.toStringAsFixed(2)} s', (v) => c.fadeSeconds = v),
                    _slider('Glow', c.glowScale, 0.2, 1.8, c.glowScale.toStringAsFixed(2), (v) => c.glowScale = v),
                    _slider('Softness', c.softness, 0.4, 2.0, c.softness.toStringAsFixed(2), (v) => c.softness = v),
                    _slider('Squash', c.squash, 0.75, 1.0, c.squash.toStringAsFixed(2), (v) => c.squash = v),
                    _label('THEME'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final t in LanternTheme.all) _chip(t.name, c.theme == t, () => c.setTheme(t)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: c.explodeTarget > 0.5,
                      onChanged: (v) => c.explodeTarget = v ? 1 : 0,
                      activeTrackColor: _accent,
                      title: const Text('Explode parts', style: TextStyle(color: _text, fontSize: 15)),
                      subtitle: const Text(
                        'Five spheres and a face shell',
                        style: TextStyle(color: _muted, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  static const _days = [(0, 'Auto'), (1, 'Morning'), (2, 'Day'), (3, 'Evening'), (4, 'Night')];

  Widget _label(String s) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(s, style: const TextStyle(color: _violet, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.3)),
  );

  Widget _chip(String label, bool on, VoidCallback onTap) {
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: on ? _accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? _accent : _line),
          ),
          child: Text(
            label,
            style: TextStyle(color: on ? const Color(0xFF0A1024) : _muted, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _weight(String name, double w) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 84, child: Text(name, style: const TextStyle(color: _muted, fontSize: 13))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: w.clamp(0, 1),
                minHeight: 7,
                backgroundColor: const Color(0xFF1A2450),
                valueColor: const AlwaysStoppedAnimation(_accent),
              ),
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              w.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(color: _text, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(String name, double value, double min, double max, String readout, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 84, child: Text(name, style: const TextStyle(color: _muted, fontSize: 13))),
        Expanded(
          child: SliderTheme(
            data: const SliderThemeData(
              activeTrackColor: _accent,
              inactiveTrackColor: Color(0xFF1A2450),
              thumbColor: _accent,
              trackHeight: 3,
            ),
            child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            readout,
            textAlign: TextAlign.right,
            style: const TextStyle(color: _text, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
      ],
    );
  }
}


/// A square pad: drag the point to set Lumi's mood and energy.
class _MoodPad extends StatelessWidget {
  const _MoodPad({required this.mood, required this.character});

  final vm.Vector2 mood;
  final LanternCharacter character;

  @override
  Widget build(BuildContext context) {
    final w = character.moodWeights;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth.clamp(0.0, 260.0);
        void set(Offset p) {
          mood.setValues((p.dx / side * 2 - 1).clamp(-1.0, 1.0), (1 - p.dy / side * 2).clamp(-1.0, 1.0));
        }

        Widget corner(String label, double weight, Alignment a) => Align(
          alignment: a,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '$label ${weight.toStringAsFixed(2)}',
              style: const TextStyle(color: CreativePanel._muted, fontSize: 11, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        );

        return Center(
          child: GestureDetector(
            onPanDown: (d) => set(d.localPosition),
            onPanUpdate: (d) => set(d.localPosition),
            child: Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                color: const Color(0xFF111A3D),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: CreativePanel._line),
              ),
              child: Stack(
                children: [
                  Positioned(left: side / 2, top: 0, bottom: 0, child: Container(width: 1, color: CreativePanel._line)),
                  Positioned(top: side / 2, left: 0, right: 0, child: Container(height: 1, color: CreativePanel._line)),
                  corner('Grumpy', w[0], Alignment.topLeft),
                  corner('Happy', w[1], Alignment.topRight),
                  corner('Glum', w[2], Alignment.bottomLeft),
                  corner('Content', w[3], Alignment.bottomRight),
                  Positioned(
                    left: (mood.x + 1) / 2 * side - 11,
                    top: (1 - mood.y) / 2 * side - 11,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFFB35C),
                        boxShadow: [BoxShadow(color: Color(0x99FFB35C), blurRadius: 14)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
