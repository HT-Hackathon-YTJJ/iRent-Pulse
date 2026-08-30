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

    AimEvaluator evaluator({Rect? guide}) =>
        AimEvaluator(guideRect: guide)..restart();

    AimVerdict run(
      AimEvaluator e, {
      FrameStats stats = goodStats,
      Detection? detection,
      bool requireGuide = true,
      int frames = 1,
    }) {
      late AimVerdict verdict;
      for (var i = 0; i < frames; i++) {
        verdict = e.evaluate(
          stats: stats,
          car: detection,
          detectorAvailable: true,
          requireGuide: requireGuide,
        );
      }
      return verdict;
    }

    test('an empty frame is 未對準 and points at the outline', () {
      final verdict = run(evaluator(), detection: null);
      expect(verdict.state, AimState.off);
      expect(verdict.hint, '對齊灰色輪廓線');
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
        detection: car(const Rect.fromLTRB(0.03, 0.03, 0.97, 0.97)),
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

    test('one bad frame resets the streak', () {
      final e = evaluator();
      run(e, detection: car(wellFramed), frames: e.holdFrames - 1);
      final dropped = run(e, detection: null);
      expect(dropped.streak, 0);
      final next = run(e, detection: car(wellFramed));
      expect(next.streak, 1);
      expect(next.isAcceptable, isFalse);
    });

    test('a car that misses the guide outline is held at 接近', () {
      final e = evaluator(guide: const Rect.fromLTRB(0.07, 0.3, 1.0, 0.61));
      // Big enough and clear of every edge, but sitting below the outline —
      // so only the IoU check can reject it.
      final verdict = run(
        e,
        detection: car(const Rect.fromLTRB(0.05, 0.55, 0.95, 0.975)),
      );
      expect(verdict.coverage, greaterThan(const AimThresholds().minCoverage));
      expect(verdict.iou, lessThan(const AimThresholds().minIou));
      expect(verdict.hint, '對齊灰色輪廓線');
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
    });

    test('never relaxes past the point where anything at all would pass', () {
      const base = AimThresholds();
      final relaxed = base.relaxedBy(0.9);
      expect(relaxed.maxCoverage, lessThanOrEqualTo(0.98));
      expect(relaxed.maxOverExposed, lessThanOrEqualTo(0.5));
      expect(relaxed.maxUnderExposed, lessThanOrEqualTo(0.5));
    });
  });
}
