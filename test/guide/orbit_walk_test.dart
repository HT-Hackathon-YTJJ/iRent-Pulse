import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:irent_pulse/guide/car_model.dart';
import 'package:irent_pulse/guide/orbit_guide.dart';
import 'package:irent_pulse/guide/outline_renderer.dart';

import 'walk_sim.dart';

/// The guide as the viewfinder drives it: heading from the gyroscope, raw
/// detector boxes with the time their frame arrived, and the plate's place
/// in the box when the reader found one.
class GuideAdapter implements SimTracker {
  GuideAdapter(CarModel model, WalkSimulator sim, double target)
    : guide = OrbitGuide(startSensors: false) {
    guide.attach(model);
    guide.configure(viewport: sim.viewport, target: target);
  }

  final OrbitGuide guide;
  final DateTime _base = DateTime.now();

  DateTime _at(double t) =>
      _base.add(Duration(microseconds: (t * 1e6).round()));

  @override
  void gyro(double t, double yaw, {required bool walking}) =>
      guide.heading.feed(_at(t), yaw, walking: walking);

  @override
  void detection(double t, SimDetection d) {
    final box = d.box;
    ({double across, double up})? plate;
    final px = d.plateX, py = d.plateY;
    if (px != null && py != null && px >= box.left && px <= box.right) {
      plate = (
        across: (px - box.center.dx) / box.width,
        up: (box.bottom - py) / box.height,
      );
    }
    guide.observeBox(box, at: _at(d.frameAt), plate: plate);
  }

  @override
  double? get azimuth => guide.azimuth;
}

void main() {
  late CarModel model;
  late WalkSimulator sim;

  setUpAll(() {
    final json = jsonDecode(File(CarModel.asset).readAsStringSync());
    model = CarModel.fromJson(json as Map<String, dynamic>);
    sim = WalkSimulator(OutlineRenderer(model));
  });

  Map<String, List<SimResult>> runAll() => {
    for (final s in scenarios)
      s.name: [
        for (final seed in [1, 2, 3, 4, 5])
          sim.run(s, GuideAdapter(model, sim, s.prior), seed: seed, ease: 0.14),
      ],
  };

  late final results = runAll();

  List<SimResult> of(String name) => results[name]!;

  test('panning to frame the car does not turn the outline', () {
    // The heading alone turned the outline with every pan: 10° rms, 20° at
    // worst, standing still.
    for (final r in of('pan at 左前')) {
      expect(r.rms, lessThan(4), reason: '$r');
      expect(r.max, lessThan(9), reason: '$r');
      expect(r.jumps, 0, reason: '$r');
    }
  });

  test('walking round with the phone up follows the walk', () {
    for (final r in of('walk phone up')) {
      expect(r.rms, lessThan(5), reason: '$r');
      expect(r.jumps, 0, reason: '$r');
    }
  });

  test('walking with the phone down picks the car up again', () {
    for (final r in of('walk phone down')) {
      expect(r.p95, lessThan(10), reason: '$r');
      expect(r.falseGreen, 0, reason: '$r');
    }
  });

  test('the car in the next bay does not drag the outline', () {
    for (final r in of('neighbour car 右後')) {
      expect(r.rms, lessThan(6), reason: '$r');
      expect(r.jumps, 0, reason: '$r');
    }
  });

  test('the mirror corner does not go green', () {
    // 右前 while the slot asks for 左前: the old tracker took the prior's
    // mirror image and showed the wrong side of the car, green, every run.
    for (final name in ['wrong side 右前', 'opposite 右後']) {
      final greens = of(name).map((r) => r.falseGreen).reduce((a, b) => a + b);
      final scored = of(name).map((r) => r.scored).reduce((a, b) => a + b);
      expect(greens / scored, lessThan(0.05), reason: '${of(name)}');
    }
  });

  test('stepping in and out does not skew the angle', () {
    // Stepping in cuts the box off at the frame's edge, and for those few
    // seconds nothing reads the angle; the outline holds where it was.
    for (final r in of('step in/out 左後')) {
      expect(r.p95, lessThan(6), reason: '$r');
      expect(r.jumps, 0, reason: '$r');
    }
  });

  test('print the table', () {
    for (final rs in results.values) {
      for (final r in rs) {
        // ignore: avoid_print
        print(r);
      }
    }
  });
}
