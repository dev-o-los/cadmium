import 'dart:math' as math;

/// The lyric playhead: a clock that runs on its own frames and is *steered* by
/// the player's readings rather than set by them.
///
/// Ported from Benjamin's am-lyrics / native LyricClock.kt:
/// 1. A reading is dated by when it was taken, not when it was seen.
/// 2. Nothing but an announced jump moves the words backwards.
/// 3. Readings steer, they don't set: the words close the gap to the newest
///    reading carried forward at the learned rate, at most 25% faster or 50% slower.
///
/// All times are milliseconds.
class LyricClock {
  /// Where the lyrics are drawn, in song milliseconds.
  double displayedMs;

  double _lastNowMs = double.nan;
  double _lastReportMs = -9007199254740991.0;
  double _lastSampledAtMs = double.nan;

  /// When playback was last seen stopped; a reading taken before then was taken standing still.
  double _heldAtMs = double.negativeInfinity;
  int? _lastDiscontinuity;
  bool _jumpPending = false;
  double _anchorAtMs = double.nan;
  double _anchorMs = 0.0;

  /// The playback rate, learned from how far the song moves between readings.
  double _rate = 1.0;
  final List<double> _historyAt = [];
  final List<double> _historyMs = [];
  bool _rateSettled = false;
  double _suspectAtMs = double.nan;
  double _suspectMs = 0.0;
  int _rejections = 0;
  double _glideStartMs = double.nan;
  double _glideOffsetMs = 0.0;

  static const double outlierMs = 250.0;
  static const double rateSlack = 0.2;
  static const double unsettledRateSlack = 0.75;
  static const int maxRejections = 2;
  static const double minRateSpanMs = 900.0;
  static const double rateWindowMs = 4000.0;
  static const int historySize = 16;
  static const double minPairSpanMs = 300.0;
  static const double pairLearning = 0.5;
  static const double minRate = 0.25;
  static const double maxRate = 4.0;
  static const double correctionMs = 120.0;
  static const double maxSlew = 0.80;
  static const double maxSlow = 0.5;
  static const double glideFromMs = 180.0;
  static const double glideMs = 150.0;
  static const double glideMaxMs = 1500.0;
  static const double lostMs = 2000.0;

  LyricClock(double startMs) : displayedMs = startMs;

  /// Forget the run so far: frames stopped arriving, and the next frame starts a new one.
  void restart() {
    _lastNowMs = double.nan;
    _jumpPending = false;
    _glideStartMs = double.nan;
    _clearSuspect();
  }

  /// Playback is not moving: settle on [positionMs] outright, as of [nowMs].
  void hold(double positionMs, double nowMs) {
    restart();
    displayedMs = positionMs;
    _heldAtMs = nowMs;
  }

  /// Advance to the frame at [nowMs] and return where the lyrics should be drawn.
  /// [sampledAtMs] is when [reportedMs] was taken (NaN when unknown);
  /// [discontinuity] changes whenever the playhead jumps on purpose.
  double frame(double nowMs, double reportedMs, double sampledAtMs, int discontinuity) {
    final firstOfRun = _lastNowMs.isNaN;
    if (discontinuity != _lastDiscontinuity) {
      if (_lastDiscontinuity != null && !firstOfRun) _jumpPending = true;
      _lastDiscontinuity = discontinuity;
    }
    final isNew = reportedMs != _lastReportMs ||
        (!sampledAtMs.isNaN && sampledAtMs != _lastSampledAtMs);
    _lastReportMs = reportedMs;
    _lastSampledAtMs = sampledAtMs;

    if (firstOfRun) {
      _lastNowMs = nowMs;
      final takenAt = (sampledAtMs.isNaN || sampledAtMs <= _heldAtMs)
          ? nowMs
          : math.min(sampledAtMs, nowMs);
      _anchor(takenAt, reportedMs);
      displayedMs = _targetAt(nowMs);
      return displayedMs.truncateToDouble();
    }

    final dt = math.max(0.0, nowMs - _lastNowMs);
    _lastNowMs = nowMs;
    _advance(nowMs, dt);

    if (isNew) {
      final takenAt = sampledAtMs.isNaN ? nowMs : math.min(sampledAtMs, nowMs);
      if (takenAt >= _anchorAtMs || _jumpPending) {
        _take(nowMs, takenAt, reportedMs);
      }
    }
    return displayedMs.truncateToDouble();
  }

  void _take(double nowMs, double takenAt, double reportedMs) {
    if (_jumpPending) {
      _jumpPending = false;
      _clearSuspect();
      _anchor(takenAt, reportedMs);
      _jumpTo(nowMs);
      return;
    }
    final elapsed = takenAt - _anchorAtMs;
    if ((reportedMs - (_anchorMs + elapsed * _rate)).abs() <= _tolerance(elapsed)) {
      _clearSuspect();
      _anchor(takenAt, reportedMs, continues: true);
      return;
    }
    final sinceSuspect = takenAt - _suspectAtMs;
    final agrees = !_suspectAtMs.isNaN &&
        sinceSuspect >= 0 &&
        (reportedMs - (_suspectMs + sinceSuspect * _rate)).abs() <= _tolerance(sinceSuspect);
    _rejections++;
    if (agrees) {
      final firstAt = _suspectAtMs;
      final first = _suspectMs;
      _clearSuspect();
      _anchor(firstAt, first);
      _anchor(takenAt, reportedMs, continues: true);
    } else if (_rejections > maxRejections) {
      _clearSuspect();
      _anchor(takenAt, reportedMs);
    } else {
      _suspectAtMs = takenAt;
      _suspectMs = reportedMs;
    }
  }

  double _tolerance(double elapsedMs) {
    return outlierMs + elapsedMs.abs() * (_rateSettled ? rateSlack : unsettledRateSlack);
  }

  void _anchor(double atMs, double positionMs, {bool continues = false}) {
    _anchorAtMs = atMs;
    _anchorMs = positionMs;
    if (!continues) {
      _historyAt.clear();
      _historyMs.clear();
    }
    if (_historyAt.length == historySize) {
      _historyAt.removeAt(0);
      _historyMs.removeAt(0);
    }
    _historyAt.add(atMs);
    _historyMs.add(_anchorMs);
    _learnRate();
  }

  void _learnRate() {
    final newest = _historyAt.length - 1;
    if (newest < 1) return;
    int oldest = 0;
    while (oldest < newest && _historyAt[newest] - _historyAt[oldest] > rateWindowMs) {
      oldest++;
    }
    final span = _historyAt[newest] - _historyAt[oldest];
    if (span >= minRateSpanMs) {
      _rate = ((_historyMs[newest] - _historyMs[oldest]) / span).clamp(minRate, maxRate);
      _rateSettled = true;
      return;
    }
    final pairSpan = _historyAt[newest] - _historyAt[newest - 1];
    if (!_rateSettled && pairSpan >= minPairSpanMs) {
      final measured = ((_historyMs[newest] - _historyMs[newest - 1]) / pairSpan).clamp(minRate, maxRate);
      _rate += (measured - _rate) * pairLearning;
    }
  }

  void _clearSuspect() {
    _suspectAtMs = double.nan;
    _rejections = 0;
  }

  void _advance(double nowMs, double dt) {
    final target = _targetAt(nowMs);
    final step = dt * _rate;
    final error = target - (displayedMs + step);
    if (!_glideStartMs.isNaN) {
      final progress = (nowMs - _glideStartMs) / glideMs;
      if (progress >= 1.0) {
        displayedMs = target;
        _glideStartMs = double.nan;
      } else {
        displayedMs = target + _glideOffsetMs * (1.0 - _smoothstep(progress));
      }
    } else if (error <= -lostMs || error >= lostMs) {
      displayedMs = target;
    } else if (error >= glideFromMs) {
      _startGlide(nowMs - dt, displayedMs - (target - step));
      displayedMs = target + _glideOffsetMs * (1.0 - _smoothstep(dt / glideMs));
    } else {
      final closing = error * (dt / (dt + correctionMs));
      displayedMs += step + closing.clamp(-maxSlow * step, maxSlew * step);
    }
  }

  void _jumpTo(double nowMs) {
    final offset = displayedMs - _targetAt(nowMs);
    if (offset.abs() > glideMaxMs) {
      displayedMs = _targetAt(nowMs);
      _glideStartMs = double.nan;
    } else {
      _startGlide(nowMs, offset);
    }
  }

  void _startGlide(double startMs, double offsetMs) {
    _glideStartMs = startMs;
    _glideOffsetMs = offsetMs;
  }

  double _targetAt(double atMs) {
    return _anchorMs + (atMs - _anchorAtMs) * _rate;
  }

  static double _smoothstep(double fraction) {
    final t = fraction.clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }
}

