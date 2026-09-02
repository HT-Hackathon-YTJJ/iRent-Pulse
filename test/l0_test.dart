import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:irent_pulse/data/return_inspection.dart';
import 'package:irent_pulse/l0/aim.dart';
import 'package:irent_pulse/l0/car_detector.dart';
import 'package:irent_pulse/l0/frame_analysis.dart';

/// A frame built from a function, so each test states exactly what the sensor
/// is handing over.
class _FakeFrame implements FramePixels {
  _FakeFrame(this.width, this.height, this._value);

  @override
  final int width;
  @override
  final int height;

  final int Function(int x, int y) _value;

  @override
  int luma(int x, int y) => _value(x, y);

  @override
  int rgb(int x, int y) {
    final v = _value(x, y);
    return (v << 16) | (v << 8) | v;
  }
}

void main() {
  group('FrameStats', () {
    test('a flat wall has no edges, so it reads as blurred', () {
      final stats = FrameStats.measure(_FakeFrame(640, 480, (_, _) => 128));
      expect(stats.blurScore, closeTo(0, 0.001));
      expect(stats.meanLuma, closeTo(128, 0.001));
      expect(stats.overExposed, 0);
      expect(stats.underExposed, 0);
    });

    test('a sharp checkerboard scores far above the blur floor', () {
      final stats = FrameStats.measure(
        _FakeFrame(640, 480, (x, y) => ((x ~/ 4) + (y ~/ 4)).isEven ? 20 : 235),
      );
      expect(stats.blurScore, greaterThan(const AimThresholds().blurFloor));
    });

    test('an unlit car park reads as under-exposed — this is what lights the torch', () {
      final stats = FrameStats.measure(_FakeFrame(640, 480, (_, _) => 12));
      expect(stats.underExposed, closeTo(1, 0.001));
      expect(stats.meanLuma, lessThan(55));
    });

    test('a blown-out frame reads as over-exposed', () {
      final stats = FrameStats.measure(_FakeFrame(640, 480, (_, _) => 252));
      expect(stats.overExposed, closeTo(1, 0.001));
    });

    test('only the centre 80% is measured, so a bright edge does not skew it', () {
      // Pure white down the left 5% of the frame; everything else mid-grey.
      final stats = FrameStats.measure(
        _FakeFrame(640, 480, (x, _) => x < 32 ? 255 : 128),
      );
      expect(stats.overExposed, 0);
    });
  });

  group('sampleRotatedRgb', () {
    // A frame whose top-left quadrant is bright and everything else dark, so a
    // rotation is visible in a single sample.
    _FakeFrame marked() =>
        _FakeFrame(40, 20, (x, y) => (x < 20 && y < 10) ? 255 : 0);

    int brightnessAt(List<int> rgb, int size, int x, int y) =>
        rgb[(y * size + x) * 3];

    test('0° leaves the mark in the top-left', () {
      final out = sampleRotatedRgb(marked(), 0, 8);
      expect(brightnessAt(out, 8, 1, 1), 255);
      expect(brightnessAt(out, 8, 6, 6), 0);
    });

    test('90° clockwise moves the top-left mark to the top-right', () {
      final out = sampleRotatedRgb(marked(), 90, 8);
      expect(brightnessAt(out, 8, 6, 1), 255);
      expect(brightnessAt(out, 8, 1, 1), 0);
    });

    test('270° moves it to the bottom-left', () {
      final out = sampleRotatedRgb(marked(), 270, 8);
      expect(brightnessAt(out, 8, 1, 6), 255);
      expect(brightnessAt(out, 8, 6, 1), 0);
    });

    test('180° moves it to the bottom-right', () {
      final out = sampleRotatedRgb(marked(), 180, 8);
      expect(brightnessAt(out, 8, 6, 6), 255);
      expect(brightnessAt(out, 8, 1, 1), 0);
    });

    test('every sample lands inside the source, whatever the rotation', () {
      for (final rotation in [0, 90, 180, 270]) {
        expect(
          () => sampleRotatedRgb(_FakeFrame(41, 19, (_, _) => 7), rotation, 13),
          returnsNormally,
          reason: 'rotation $rotation',
        );
      }
    });
  });

  group('AimEvaluator', () {
    // A frame that passes every arithmetic check, so each test only has to
    // vary the one thing it is about.
    const goodStats = FrameStats(
      blurScore: 400,
      overExposed: 0.01,
      underExposed: 0.02,
      meanLuma: 130,
    );

    Detection car(Rect box, {double score = 0.9}) =>
        Detection(box: box, score: score, label: 'car');

    // Fills 54% of the frame, well clear of every edge.
    final wellFramed = Rect.fromLTRB(0.12, 0.22, 0.88, 0.94);

    AimEvaluator evaluator({Rect? guide, bool allowsEdge = false}) =>
        AimEvaluator(guideRect: guide, guideAllowsEdge: allowsEdge)..restart();

    /// The evaluator ages its detections, so every test drives its own clock
    /// rather than letting the wall clock decide whether a box is still fresh.
    final epoch = DateTime(2026, 1, 1);

    AimVerdict run(
      AimEvaluator e, {
      FrameStats stats = goodStats,
      Detection? detection,
      bool requireGuide = true,
      int frames = 1,
      DateTime? at,
    }) {
      late AimVerdict verdict;
      for (var i = 0; i < frames; i++) {
        verdict = e.evaluate(
          stats: stats,
          car: detection,
          detectorAvailable: true,
          requireGuide: requireGuide,
          now: at ?? epoch,
        );
      }
      return verdict;
    }

    test('an empty frame is 未對準 and points at the outline', () {
      final verdict = run(evaluator(), detection: null);
      expect(verdict.state, AimState.off);
      expect(verdict.hint, '對齊輪廓線');
    });

    test('a soft frame is called out before anything about framing', () {
      // Blur is true of the whole frame; no amount of repositioning fixes it,
      // so telling the driver to step closer first would be a wasted trip.
      final verdict = run(
        evaluator(),
        stats: const FrameStats(
          blurScore: 5,
          overExposed: 0,
          underExposed: 0,
          meanLuma: 130,
        ),
        detection: car(wellFramed),
      );
      expect(verdict.state, AimState.near);
      expect(verdict.hint, contains('模糊'));
    });

    test('a dark frame explains that the torch is coming on', () {
      final verdict = run(
        evaluator(),
        stats: const FrameStats(
          blurScore: 400,
          overExposed: 0,
          underExposed: 0.9,
          meanLuma: 20,
        ),
        detection: car(wellFramed),
      );
      expect(verdict.hint, contains('閃光燈'));
    });

    test('a distant car is asked to come closer', () {
      final verdict = run(
        evaluator(),
        detection: car(const Rect.fromLTRB(0.4, 0.4, 0.6, 0.6)),
      );
      expect(verdict.state, AimState.near);
      expect(verdict.hint, '再靠近一點');
    });

    test('a car filling the frame is asked to step back', () {
      final verdict = run(
        evaluator(),
        detection: car(const Rect.fromLTRB(0.01, 0.01, 0.99, 0.99)),
      );
      expect(verdict.hint, '請再退後一步');
    });

    test('a car touching the edge is reported as cropped, not as too big', () {
      // 完整性: the box is only 40% of the frame but runs off the left edge.
      final verdict = run(
        evaluator(),
        detection: car(const Rect.fromLTRB(0.0, 0.25, 0.62, 0.95)),
      );
      expect(verdict.hint, contains('切到'));
    });

    test('the shutter arms only after the confirmation streak', () {
      final e = evaluator();
      for (var i = 1; i < e.holdFrames; i++) {
        final partial = run(e, detection: car(wellFramed));
        expect(partial.isAcceptable, isFalse, reason: 'frame $i');
        expect(partial.streak, i);
      }
      final armed = run(e, detection: car(wellFramed));
      expect(armed.state, AimState.locked);
      expect(armed.isAcceptable, isTrue);
      expect(armed.hint, isNull);
    });

    test('a frame the detector skipped does not reset the streak', () {
      // Inference runs at 5Hz over a 30Hz stream, so most frames arrive with
      // no detection at all. Treating those as "no car" is what used to make
      // the badge strobe between 未對準 and 已對準 on a phone held still.
      final e = evaluator();
      final built = run(e, detection: car(wellFramed), frames: e.holdFrames - 1);
      expect(built.streak, e.holdFrames - 1);

      final skipped = run(e, detection: null);
      expect(skipped.streak, e.holdFrames);
      expect(skipped.isAcceptable, isTrue);
    });

    test('a detection that has gone stale does reset it', () {
      // The other half of the same rule: the last box cannot stand in for ever,
      // or a viewfinder swung away from the car keeps reporting 已對準 from a
      // frame that is long gone.
      final e = evaluator();
      run(e, detection: car(wellFramed), frames: e.holdFrames);

      final later = epoch.add(AimEvaluator.staleAfter * 2);
      final dropped = run(e, detection: null, at: later);
      expect(dropped.streak, 0);
      expect(dropped.state, AimState.off);
      expect(dropped.hint, '對齊輪廓線');
    });

    test('one genuinely bad frame resets the streak', () {
      final e = evaluator();
      run(e, detection: car(wellFramed), frames: e.holdFrames - 1);
      final dropped = run(
        e,
        stats: const FrameStats(
          blurScore: 2,
          overExposed: 0,
          underExposed: 0,
          meanLuma: 130,
        ),
        detection: car(wellFramed),
      );
      expect(dropped.streak, 0);
    });

    // The guide the four body slots are scored against, in the same upright
    // normalised space the detector reports boxes in.
    const guide = Rect.fromLTRB(0.06, 0.34, 0.94, 0.80);

    test('a car the right size but off the outline is 未對準, not 接近', () {
      // This is the case a single IoU could not tell apart from a centred car
      // that was simply too small — and telling the driver to walk forward
      // when the problem is that they are aimed at the wrong part of the car
      // sends them the wrong way.
      final e = evaluator(guide: guide);
      final verdict = run(
        e,
        detection: car(const Rect.fromLTRB(0.06, 0.06, 0.94, 0.52)),
      );
      expect(verdict.fill, closeTo(1, 0.05), reason: '大小其實是對的');
      expect(verdict.drift, greaterThan(const AimThresholds().maxDrift));
      expect(verdict.state, AimState.off);
      expect(verdict.hint, '對齊輪廓線');
    });

    test('a car centred on the outline but too small is 接近 with a direction', () {
      final e = evaluator(guide: guide);
      final verdict = run(
        e,
        detection: car(const Rect.fromLTRB(0.36, 0.47, 0.64, 0.67)),
      );
      expect(verdict.drift, lessThan(const AimThresholds().maxDrift));
      expect(verdict.fill, lessThan(const AimThresholds().minFill));
      expect(verdict.state, AimState.near);
      expect(verdict.hint, '再靠近一點');
    });

    test('a car overflowing the outline is asked to step back', () {
      final e = evaluator(guide: guide, allowsEdge: true);
      final verdict = run(
        e,
        detection: car(const Rect.fromLTRB(0.0, 0.05, 1.0, 1.0)),
      );
      expect(verdict.fill, greaterThan(const AimThresholds().maxFill));
      expect(verdict.hint, '請再退後一步');
    });

    test('a car filling the outline locks after the streak', () {
      final e = evaluator(guide: guide);
      final verdict = run(e, detection: car(guide), frames: e.holdFrames);
      expect(verdict.fill, closeTo(1, 0.02));
      expect(verdict.drift, closeTo(0, 0.02));
      expect(verdict.state, AimState.locked);
    });

    test('a bleeding guide does not report the car as cropped', () {
      // 右前 and 左前 run the silhouette off one edge on purpose, so the car
      // touching that edge is the instruction being followed, not a failure.
      final e = evaluator(
        guide: const Rect.fromLTRB(0.0, 0.34, 0.94, 0.80),
        allowsEdge: true,
      );
      final verdict = run(
        e,
        detection: car(const Rect.fromLTRB(0.0, 0.34, 0.94, 0.80)),
        frames: e.holdFrames,
      );
      expect(verdict.state, AimState.locked);
    });

    test('the same frame without the bleed is reported as cropped', () {
      final e = evaluator(guide: const Rect.fromLTRB(0.0, 0.34, 0.94, 0.80));
      final verdict = run(
        e,
        detection: car(const Rect.fromLTRB(0.0, 0.34, 0.94, 0.80)),
      );
      expect(verdict.hint, contains('切到'));
    });

    test('the reported box eases towards a new detection instead of snapping', () {
      final e = evaluator(guide: guide);
      run(e, detection: car(guide));
      final moved = run(
        e,
        detection: car(const Rect.fromLTRB(0.26, 0.34, 0.94, 0.80)),
        at: epoch.add(const Duration(milliseconds: 200)),
      );

      final box = moved.carBox!;
      expect(box.left, greaterThan(guide.left));
      expect(box.left, lessThan(0.26));
    });

    test('one jittery inference cannot knock a settled frame out of 已對準', () {
      // A single-shot SSD moves its box by a few percent between frames even on
      // a phone lying on a table, and at 5Hz that was landing either side of
      // the threshold and strobing the badge. Smoothing plus the hysteresis on
      // an already-locked frame is what stops it.
      final e = evaluator(guide: guide);
      run(e, detection: car(guide), frames: e.holdFrames);

      final jitter = run(
        e,
        // Shifted a fifth of a frame down — far enough that this box on its
        // own would score past even the relaxed drift limit.
        detection: car(const Rect.fromLTRB(0.06, 0.53, 0.94, 0.99)),
        at: epoch.add(const Duration(milliseconds: 200)),
      );
      expect(jitter.state, AimState.locked);
    });

    test('the cabin shot has no outline to miss', () {
      // requireGuide is off for 車內, so the same frame passes.
      final e = evaluator(guide: const Rect.fromLTRB(0.07, 0.3, 1.0, 0.61));
      final verdict = run(
        e,
        detection: car(wellFramed),
        requireGuide: false,
        frames: 5,
      );
      expect(verdict.isAcceptable, isTrue);
    });

    test('with no model loaded, the arithmetic checks still gate the shutter', () {
      // 沒跑 tool/fetch_l0_model.sh 時：少了車體偵測，但糊掉／過暗仍擋得住。
      final e = evaluator();
      final sharp = e.evaluate(
        stats: goodStats,
        car: null,
        detectorAvailable: false,
        requireGuide: true,
      );
      expect(sharp.state, AimState.near); // streak of 1, not yet armed
      final soft = e.evaluate(
        stats: const FrameStats(
          blurScore: 1,
          overExposed: 0,
          underExposed: 0,
          meanLuma: 130,
        ),
        car: null,
        detectorAvailable: false,
        requireGuide: true,
      );
      expect(soft.hint, contains('模糊'));
    });
  });

  group('AimVerdict.report', () {
    test('an overridden shutter is marked as bypassed for L1', () {
      const verdict = AimVerdict(state: AimState.near, coverage: 0.2);
      final report = verdict.report(manual: true);
      expect(report['capture_mode'], 'manual');
      expect(report['bypassed'], isTrue);
      expect(report['passed'], isFalse);
    });

    test('an automatic shutter on a good frame is not bypassed', () {
      const verdict = AimVerdict(state: AimState.locked, streak: 5);
      final report = verdict.report(manual: false);
      expect(report['capture_mode'], 'auto');
      expect(report['bypassed'], isFalse);
      expect(report['passed'], isTrue);
      expect(report['frames_confirmed'], 5);
    });
  });

  group('AimThresholds.relaxedBy', () {
    test('widens the window on both sides rather than only lowering the floor', () {
      const base = AimThresholds();
      final relaxed = base.relaxedBy(0.2);
      expect(relaxed.minCoverage, lessThan(base.minCoverage));
      expect(relaxed.maxCoverage, greaterThan(base.maxCoverage));
      expect(relaxed.blurFloor, lessThan(base.blurFloor));
      expect(relaxed.maxUnderExposed, greaterThan(base.maxUnderExposed));
      // The alignment window widens from both ends too, or a driver who cannot
      // get green would still be stuck after the timer relaxed everything else.
      expect(relaxed.minFill, lessThan(base.minFill));
      expect(relaxed.maxFill, greaterThan(base.maxFill));
      expect(relaxed.maxDrift, greaterThan(base.maxDrift));
    });

    test('never relaxes past the point where anything at all would pass', () {
      const base = AimThresholds();
      final relaxed = base.relaxedBy(0.9);
      expect(relaxed.maxCoverage, lessThanOrEqualTo(0.99));
      expect(relaxed.maxOverExposed, lessThanOrEqualTo(0.5));
      expect(relaxed.maxUnderExposed, lessThanOrEqualTo(0.5));
    });
  });
}
