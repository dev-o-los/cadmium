import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/services/lyric_clock.dart';

const frameMs = 1000.0 / 60.0;

/// Small seeded generator reproducing the test suite
double Function() seeded(int seed) {
  int state = (seed & 0xFFFFFFFF);
  if (state == 0) state = 1;
  return () {
    state = ((state * 1664525 + 1013904223) & 0xFFFFFFFF);
    return state / 4294967296.0;
  };
}

class Playback {
  final double startMs;
  final double rate;
  final double maxDelayMs;
  final bool stamped;
  double report;
  double sampledAt;
  double _nextPollMs = 0.0;
  final List<Map<String, double>> _inFlight = [];
  final double Function() _random;

  Playback({
    this.startMs = 44500.0,
    this.rate = 1.0,
    this.maxDelayMs = 60.0,
    this.stamped = true,
    int seed = 7,
  })  : report = startMs,
        sampledAt = stamped ? 0.0 : double.nan,
        _random = seeded(seed);

  double trueAt(double nowMs) => startMs + nowMs * rate;

  void deliver(double nowMs) {
    while (_nextPollMs <= nowMs) {
      _inFlight.add({
        'arrives': _nextPollMs + _random() * maxDelayMs,
        'reading': trueAt(_nextPollMs).truncateToDouble(),
        'at': _nextPollMs,
      });
      _nextPollMs += 500.0;
    }
    _inFlight.sort((a, b) => a['arrives']!.compareTo(b['arrives']!));
    while (_inFlight.isNotEmpty && _inFlight[0]['arrives']! <= nowMs) {
      final item = _inFlight.removeAt(0);
      report = item['reading']!;
      if (stamped) sampledAt = item['at']!;
    }
  }
}

class RunResult {
  final List<double> frames;
  final List<double> shown;
  final List<double> truth;

  RunResult(this.frames, this.shown, this.truth);
}

RunResult runClock(Playback playback, double seconds, {double maxStallMs = 0.0, int seed = 11}) {
  final random = seeded(seed);
  final clock = LyricClock(playback.startMs);
  final frames = <double>[];
  final shown = <double>[];
  final truth = <double>[];
  double now = 0.0;

  while (now <= seconds * 1000.0) {
    playback.deliver(now);
    frames.add(now);
    shown.add(clock.frame(now, playback.report, playback.sampledAt, 0));
    truth.add(playback.trueAt(now));
    now += frameMs;
    if (maxStallMs > 0 && random() < 0.02) {
      now += random() * maxStallMs;
    }
  }
  return RunResult(frames, shown, truth);
}

void neverBack(RunResult r) {
  for (int i = 1; i < r.shown.length; i++) {
    if (r.shown[i] < r.shown[i - 1]) {
      fail('went back at ${r.frames[i]}: ${r.shown[i]} < ${r.shown[i - 1]}');
    }
  }
}

void main() {
  group('LyricClock ported tests', () {
    for (final seed in [7, 19, 42, 101, 2024]) {
      test('never moves the words back on late readings (seed $seed)', () {
        neverBack(runClock(
          Playback(startMs: 44500, rate: 1.0, maxDelayMs: 800, stamped: true, seed: seed),
          90,
          maxStallMs: 600,
          seed: seed + 4,
        ));
      });
    }

    test('keeps late readings from pulling the words off the song', () {
      final r = runClock(Playback(startMs: 44500, rate: 1.0, maxDelayMs: 800), 60, maxStallMs: 600);
      for (int i = 0; i < r.frames.length; i++) {
        if (r.frames[i] < 2000) continue;
        expect((r.shown[i] - r.truth[i]).abs(), lessThan(40));
      }
    });

    test('never stalls the words', () {
      final r = runClock(Playback(startMs: 44500, rate: 1.0, maxDelayMs: 800), 60);
      const window = 15;
      for (int i = window; i < r.shown.length; i++) {
        final moved = r.shown[i] - r.shown[i - window];
        final elapsed = r.frames[i] - r.frames[i - window];
        expect(moved, greaterThanOrEqualTo(elapsed * 0.5));
      }
    });

    test('never goes back on unstamped readings', () {
      neverBack(runClock(Playback(startMs: 44500, rate: 1.0, maxDelayMs: 800, stamped: false), 60, maxStallMs: 600));
    });

    test('learns a faster playback rate', () {
      final r = runClock(Playback(startMs: 44500, rate: 1.25, maxDelayMs: 300), 30);
      for (int i = 0; i < r.frames.length; i++) {
        if (r.frames[i] < 4000) continue;
        expect((r.shown[i] - r.truth[i]).abs(), lessThan(40));
      }
      neverBack(r);
    });

    test('jumps on an announced seek', () {
      final clock = LyricClock(10000);
      double now = 0;
      double shown = 0;
      while (now <= 3000) {
        final taken = (now / 500.0).floor() * 500.0;
        shown = clock.frame(now, 10000 + taken, taken, 0);
        now += frameMs;
      }
      // Seek to 60s, announced with discontinuity = 1
      final seekAt = now;
      while (now <= seekAt + 1000) {
        final taken = (now / 500.0).floor() * 500.0;
        shown = clock.frame(
          now,
          60000 + math.max(0.0, taken - seekAt),
          math.max(taken, seekAt),
          1,
        );
        now += frameMs;
      }
      expect((shown - (60000 + (now - frameMs - seekAt))).abs(), lessThan(100));
    });
  });
}

