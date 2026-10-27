import 'dart:async';

/// The app's clock, for waits and timestamps that are not frame driven.
///
/// It runs with real time, until a recording takes over frame production
/// ([driveManually]): from then on it only moves when [advanceTo] is called
/// for each frame, so waits line up exactly with frames however long each
/// frame takes to capture.
abstract final class AppClock {
  static final _watch = Stopwatch()..start();
  static final _epoch = DateTime.now().microsecondsSinceEpoch;
  static bool _manual = false;
  static int _now = 0;
  static final List<_Wait> _waits = [];

  /// Whether a recording drives time (see [driveManually]).
  static bool get manual => _manual;

  /// App time since launch.
  static int get micros => _manual ? _now : _watch.elapsedMicroseconds;
  static double get seconds => micros / 1e6;
  static DateTime get now => DateTime.fromMicrosecondsSinceEpoch(_epoch + micros);

  /// From now on, time only moves through [advanceTo].
  static void driveManually() {
    _now = micros;
    _manual = true;
  }

  /// Moves time to [micros] (never backwards), firing what came due.
  static void advanceTo(int to) {
    if (!_manual || to < _now) return;
    while (_waits.isNotEmpty && _waits.first.at <= to) {
      final w = _waits.removeAt(0);
      _now = w.at;
      w.fire();
    }
    _now = to;
  }

  static _Wait _schedule(Duration d, void Function() f, {Duration? every}) {
    final w = _Wait(_now + d.inMicroseconds, f, every);
    final i = _waits.indexWhere((o) => o.at > w.at);
    _waits.insert(i < 0 ? _waits.length : i, w);
    return w;
  }

  static Future<void> delay(Duration d) {
    if (!_manual) return Future<void>.delayed(d);
    final done = Completer<void>();
    _schedule(d, done.complete);
    return done.future;
  }

  static Future<T> delayed<T>(Duration d, FutureOr<T> Function() f) => delay(d).then((_) => f());

  static Timer timer(Duration d, void Function() f) => _manual ? _schedule(d, f) : Timer(d, f);

  static Timer periodic(Duration d, void Function(Timer) f) {
    if (!_manual) return Timer.periodic(d, f);
    late final _Wait w;
    w = _schedule(d, () => f(w), every: d);
    return w;
  }
}

class _Wait implements Timer {
  _Wait(this.at, this._f, this._every);
  int at;
  final void Function() _f;
  final Duration? _every;
  bool _active = true;
  int _ticks = 0;

  void fire() {
    if (!_active) return;
    _ticks++;
    final every = _every;
    if (every == null) {
      _active = false;
    } else {
      at += every.inMicroseconds;
      final i = AppClock._waits.indexWhere((o) => o.at > at);
      AppClock._waits.insert(i < 0 ? AppClock._waits.length : i, this);
    }
    _f();
  }

  @override
  void cancel() {
    _active = false;
    AppClock._waits.remove(this);
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _ticks;
}
