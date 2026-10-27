part of 'park_screen.dart';

enum _VoicePhase { idle, listening, thinking, speaking }

/// Talking to the friend: it listens (an ear cupped, glowing with your
/// voice), thinks, and answers in its own chirpy voice while the words type
/// out in a speech bubble, then shows you: it points out a card, lights up a
/// row, walks you there on the map, or opens what you asked for.
class _Voice {
  _VoicePhase phase = _VoicePhase.idle;
  final stt = SpeechToText();
  bool? sttReady;
  String heard = '';
  String reply = '';
  double typed = 0;
  double t = 0;
  double level = 0;
  LumiAnswer? answer;
  bool acted = false;
  double since = 0;

  /// The bubble's fade, 0 to 1, and what it last showed (kept while it
  /// fades out).
  double shown = 0;

  /// Typing instead of talking (no microphone or speech recognition).
  bool typing = false;
  final field = TextEditingController();
  final focus = FocusNode();
  late final LumiBrain brain = LumiBrain.create();
}

extension ParkVoice on ParkScreenState {
  /// The mic button: start listening, or stop and ask what was heard.
  Future<void> toggleVoice() async {
    final c = character;
    if (c == null) return;
    if (voice.phase == _VoicePhase.listening) {
      await voice.stt.stop();
      if (voice.heard.trim().isNotEmpty) {
        askLumi(voice.heard);
      } else {
        _voiceIdle();
      }
      return;
    }
    if (voice.typing) {
      voice.typing = false;
      _refresh();
      return;
    }
    c.wake();
    voice
      ..phase = _VoicePhase.listening
      ..t = 0
      ..heard = ''
      ..reply = ''
      ..level = 0;
    Sfx.sound('toggle');
    _refresh();
    try {
      voice.sttReady ??= await voice.stt.initialize(
        onError: (_) => _voiceIdle(),
        onStatus: (status) {
          // Ended without a final result: ask with what was heard so far.
          if ((status == 'done' || status == 'notListening') && voice.phase == _VoicePhase.listening) {
            if (voice.heard.trim().isNotEmpty) {
              askLumi(voice.heard);
            }
          }
        },
      );
    } catch (_) {
      voice.sttReady = false;
    }
    if (!mounted) return;
    if (voice.sttReady != true) {
      // No speech recognition here: type instead.
      voice
        ..phase = _VoicePhase.idle
        ..typing = true;
      voice.field.clear();
      _refresh();
      voice.focus.requestFocus();
      return;
    }
    await voice.stt.listen(
      onResult: (r) {
        voice.heard = r.recognizedWords;
        _refresh();
        if (r.finalResult && voice.phase == _VoicePhase.listening) {
          if (voice.heard.trim().isEmpty) {
            _voiceIdle();
          } else {
            askLumi(voice.heard);
          }
        }
      },
      onSoundLevelChange: (l) => voice.level = ((l + 2) / 12).clamp(0.0, 1.0),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 2),
        contextualPhrases: [for (final w in _waits) w.$1, for (final d in ParkScreenState._dining) d.$1, for (final s in ParkScreenState._shows) s.$1, 'fireworks', 'Lagoon Key'],
      ),
    );
  }

  void _voiceIdle() {
    voice
      ..phase = _VoicePhase.idle
      ..level = 0;
    character?.reachTarget = null;
    _refresh();
  }

  ParkFacts _facts() => ParkFacts(
        friend: character?.friend.name ?? 'Lumi',
        waits: List.of(_waits),
        dining: ParkScreenState._dining,
        shows: ParkScreenState._shows,
        weather: switch (life.weather) {
          WeatherKind.rain => 'rain is rolling in, 15 degrees',
          WeatherKind.heat => 'a hot one, 31 degrees and sunny',
          WeatherKind.clear => 'clear skies, 18 degrees',
        },
        keys: ProfileScope.read(context).keys,
        dayPart: dayPart.name,
      );

  /// Asks the friend [question] (spoken or typed): it thinks, answers, and
  /// shows you.
  Future<void> askLumi(String question) async {
    final c = character;
    if (c == null || question.trim().isEmpty) return;
    if (voice.phase == _VoicePhase.listening) voice.stt.stop();
    voice
      ..typing = false
      ..heard = question.trim()
      ..phase = _VoicePhase.thinking
      ..t = 0;
    c
      ..wake()
      ..reachTarget = null
      ..react(LanternFace.curious, 0.8);
    Sfx.sound('chirp_curious', volume: 0.8);
    _refresh();
    // A beat of thinking even when the answer is instant, so it reads.
    final results = await Future.wait<Object?>([voice.brain.answer(question, _facts()), AppClock.delay(const Duration(milliseconds: 550))]);
    final answer = results.first! as LumiAnswer;
    if (!mounted) return;
    voice
      ..answer = answer
      ..reply = answer.say
      ..typed = 0
      ..acted = false
      ..since = 0
      ..phase = _VoicePhase.speaking
      ..t = 0;
    _refresh();
  }

  void tickVoice(LanternCharacter c, double dt) {
    final v = voice;
    v.t += dt;
    final target = v.phase != _VoicePhase.idle || v.typing ? 1.0 : 0.0;
    v.shown += (target - v.shown) * math.min(1.0, dt * 9);
    if (v.phase == _VoicePhase.idle && !v.typing) {
      if (v.shown > 0.005) _refresh();
      return;
    }
    switch (v.phase) {
      case _VoicePhase.listening:
        // An ear cupped toward you, glowing with your voice.
        final s = c.root.globalTransform.getMaxScaleOnAxis() / c.friend.scale;
        final r = c.headRadius * s;
        c
          ..reachTarget = c.headCenter + vm.Vector3(r * 1.05, -r * 0.05 + math.sin(v.t * 3) * 0.02, 0.25 * kFaceZ)
          ..glowScale = 1 + 0.6 * v.level
          ..react(LanternFace.curious, 0.2);
        v.level *= math.exp(-dt * 4);
      case _VoicePhase.thinking:
        c
          ..reachTarget = null
          ..lookToward(vm.Vector2(-0.35 + 0.1 * math.sin(v.t * 2), 0.55), curious: false);
        if ((v.t * 3).floor() != ((v.t - dt) * 3).floor()) c.jolt(0.08);
      case _VoicePhase.speaking:
        _tickSpeech(c, dt);
      case _VoicePhase.idle:
        break;
    }
    _refresh();
  }

  void _tickSpeech(LanternCharacter c, double dt) {
    final v = voice;
    final before = v.typed;
    v.typed = math.min(v.reply.length.toDouble(), v.typed + dt * 34);
    // A chirp every few letters, the mouth opening and closing with it.
    if ((before / 3.2).floor() != (v.typed / 3.2).floor() && v.typed < v.reply.length) {
      const pitches = [1.0, 1.122, 1.26, 1.335, 1.498];
      final rng = life.rng;
      final asking = v.reply.trimRight().endsWith('?');
      Sfx.sound(asking || rng.nextDouble() < 0.25 ? 'chirp_curious' : 'chirp_happy', pitch: pitches[rng.nextInt(pitches.length)], gap: const Duration(milliseconds: 70));
      c
        ..react(rng.nextBool() ? LanternFace.delighted : LanternFace.content, 0.11)
        ..jolt(0.07);
    }
    final done = v.typed >= v.reply.length;
    if (done) v.since += dt;
    final answer = v.answer;
    // What happens on screen: in-place actions while it talks, anything
    // that opens a new screen once it has finished speaking.
    if (answer != null && !v.acted) {
      final opens = answer.action == LumiAction.open || answer.action == LumiAction.walkTo;
      if ((!opens && v.typed > v.reply.length * 0.55) || (opens && v.since > 0.7)) {
        v.acted = true;
        _act(answer);
      }
    }
    if (done) {
      c.lookToward(null);
      if (v.since > 2.6 + v.reply.length / 60) _voiceIdle();
    }
  }

  GlobalKey? _cardFor(String? target) => switch (target?.toLowerCase()) {
        'tonight' || 'fireworks' => sp.cardKeys[1],
        'reward' || 'key' => sp.cardKeys[2],
        'weather' => sp.cardKeys[3],
        'booth' || 'photo' => sp.cardKeys[4],
        'games' || 'game' => sp.cardKeys[5],
        'map' => sp.cardKeys[6],
        'waits' || 'wait times' || 'rides' => sp.cardKeys[7],
        'dining' || 'food' => sp.cardKeys[8],
        'shows' => sp.cardKeys[9],
        _ => null,
      };

  Future<void> _act(LumiAnswer a) async {
    final c = character;
    if (c == null) return;
    switch (a.action) {
      case LumiAction.none:
        c.react(LanternFace.delighted, 0.6);
      case LumiAction.showCard:
        final key = _cardFor(a.target);
        if (key != null) await _pointAt(key);
      case LumiAction.highlight:
        if (a.target != null) await _findMatch(a.target!);
      case LumiAction.walkTo:
        final ride = a.target;
        await _openMap();
        // Once the map is up, the friend sets off.
        for (var i = 0; i < 120; i++) {
          await AppClock.delay(const Duration(milliseconds: 50));
          final map = _mapScreenKey.currentState;
          if (map != null && map.lumi != null) {
            await AppClock.delay(const Duration(milliseconds: 900));
            final r = map.rides.where((r) => r.name.toLowerCase() == ride?.toLowerCase()).firstOrNull;
            if (r != null) map.goTo(r);
            break;
          }
        }
      case LumiAction.open:
        switch (a.target?.toLowerCase()) {
          case 'show' || 'fireworks':
            _openShow();
          case 'catch' || 'star catch':
            _openGame(_catchKey, StarCatch.new);
          case 'lift' || 'sky lift':
            _openGame(_liftKey, SkyLift.new);
          case 'booth' || 'photo booth':
            _openBooth();
          case 'wardrobe':
            _openWardrobe();
          case 'room':
            _openRoom();
        }
      case LumiAction.weather:
        setWeather(switch (a.target?.toLowerCase()) {
          'rain' => WeatherKind.rain,
          'heat' || 'hot' || 'sun' => WeatherKind.heat,
          _ => WeatherKind.clear,
        });
      case LumiAction.moment:
        switch (a.target?.toLowerCase()) {
          case 'trick':
            trick();
          case 'sneeze':
            c.sneeze();
          case 'pulse':
            lanternPulse();
          case 'pratfall':
            pratfall();
          case 'lights_out':
            lightsOut();
          case 'jenga':
            cardJenga();
          case 'peel':
            peelInto3D();
          case 'eat':
            eatNotification();
        }
    }
  }

  /// Scrolls a card into view, throws a sparkle from the friend's hand to
  /// it, and makes it glow.
  Future<void> _pointAt(GlobalKey key) async {
    if (key.currentContext == null) await _reveal(key);
    final ctx = key.currentContext;
    if (ctx == null || !mounted) return;
    await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 420), curve: Curves.easeInOutCubic, alignment: 0.25);
    if (!mounted) return;
    final rect = globalRectOf(key);
    final c = character;
    if (rect == null || c == null) return;
    final from = _headerGlobal(camera.worldToScreen(c.handWorld, _headerSize) ?? Offset.zero);
    c.react(LanternFace.delighted, 0.6);
    final start = AppClock.now;
    while (mounted) {
      final t = AppClock.now.difference(start).inMilliseconds / 550;
      if (t >= 1) break;
      life.sparkle.value = (from, rect.topCenter + const Offset(0, 14), t);
      await AppClock.delay(const Duration(milliseconds: 16));
    }
    life.sparkle.value = null;
    final now = globalRectOf(key);
    if (now != null) life.ping.value = (now, 0.0);
    Sfx.sound('search_found');
  }

  /// The speech bubble beside the friend: what it hears, its thinking dots,
  /// or its answer typing out, or a field to type into.
  Widget _voiceOverlay() {
    final v = voice;
    if (v.shown <= 0.005 && !v.typing) return const SizedBox.shrink();
    final c = character;
    final head = _headGlobal();
    if (c == null || head == null) return const SizedBox.shrink();
    final w = _screenSize.width;
    // Where the greeting sits, below the friend, clear of the buttons; the
    // greeting steps aside while it talks. The tail points up at it.
    const left = 16.0;
    final width = math.min(320.0, w - left - 160);
    final tail = (head.dx - left).clamp(28.0, width - 22);

    Widget body;
    if (v.typing) {
      body = TextField(
        controller: v.field,
        focusNode: v.focus,
        autofocus: true,
        style: const TextStyle(color: Park.ink, fontSize: 14),
        cursorColor: Park.gold,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: 'Ask me anything',
          hintStyle: TextStyle(color: Park.inkMuted, fontSize: 14),
        ),
        onSubmitted: askLumi,
      );
    } else {
      body = switch (v.phase) {
        _VoicePhase.listening => Row(
            children: [
              Transform.scale(
                scale: 1 + 0.35 * v.level,
                child: const Icon(Icons.mic_rounded, color: Park.gold, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  v.heard.isEmpty ? 'Listening' : v.heard,
                  style: const TextStyle(color: Park.inkMuted, fontSize: 14, fontStyle: FontStyle.italic, height: 1.25),
                ),
              ),
            ],
          ),
        _VoicePhase.thinking => SizedBox(
            height: 20,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Transform.translate(
                      offset: Offset(0, -4 * math.max(0.0, math.sin(v.t * 7 - i * 0.7))),
                      child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Park.ink, shape: BoxShape.circle)),
                    ),
                  ),
              ],
            ),
          ),
        _ => Text(
            v.reply.substring(0, v.typed.floor().clamp(0, v.reply.length)),
            style: const TextStyle(color: Park.ink, fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.3),
          ),
      };
    }
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: width, minWidth: 64),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
      decoration: BoxDecoration(
        color: const Color(0xF2182041),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: v.phase == _VoicePhase.listening ? Park.gold.withValues(alpha: 0.4 + 0.5 * v.level) : const Color(0x553A4A80)),
        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: body,
    );
    final scale = 0.85 + 0.15 * Curves.easeOutBack.transform(v.shown.clamp(0.0, 1.0));
    return Positioned(
      left: left,
      bottom: _screenSize.height - _headerHeight + 12,
      width: width,
      child: IgnorePointer(
        ignoring: !v.typing,
        child: Opacity(
          opacity: v.typing ? 1 : v.shown.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment(tail / width * 2 - 1, -1),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: CustomPaint(
                painter: _TailPainter(tail),
                child: bubble,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @visibleForTesting
  bool get voiceBusy => voice.phase != _VoicePhase.idle;
}

/// The little tail on top of the speech bubble, pointing up at the friend.
class _TailPainter extends CustomPainter {
  _TailPainter(this.x);
  final double x;

  @override
  void paint(Canvas canvas, Size size) {
    final at = math.min(x, size.width - 22);
    final path = Path()
      ..moveTo(at - 8, 1)
      ..quadraticBezierTo(at - 1, -4, at + 4, -12)
      ..quadraticBezierTo(at + 4, -3, at + 9, 1)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xF2182041));
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.x != x;
}
