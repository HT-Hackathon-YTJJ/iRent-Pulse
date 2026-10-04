import 'dart:math' as math;
import 'dart:ui';

import 'package:irent_pulse/guide/orbit.dart';
import 'package:irent_pulse/guide/outline_renderer.dart';

/// A driver walking round the car with the phone, and what the phone's
/// sensors make of it — for measuring the orbit tracker end to end rather
/// than one reading at a time.
///
/// The truth is a script: where the driver stands ([az], [distance]), where
/// the phone points relative to the car ([pan], positive is anticlockwise,
/// i.e. the car slides right in the frame), whether the car is in the frame
/// at all and whether they are walking. From that the simulator produces what
/// the app actually gets: a gyroscope heading that drifts, and a detector box
/// five times a second that is late, noisy, sometimes missing, sometimes cut
/// short by a shadow, and sometimes round the car parked next door.
class Scenario {
  const Scenario({
    required this.name,
    required this.duration,
    required this.prior,
    required this.az,
    required this.pan,
    this.distanceScale = _one,
    this.inView = _always,
    this.walking = _never,
    this.neighbourRate = 0,
    this.plateRate = 0.35,
  });

  final String name;
  final double duration;

  /// The corner the slot asks for.
  final double prior;
  final double Function(double t) az;
  final double Function(double t) pan;

  /// Multiplies the distance that frames the car at [prior].
  final double Function(double t) distanceScale;
  final bool Function(double t) inView;
  final bool Function(double t) walking;

  /// Share of detections that box the neighbouring car instead.
  final double neighbourRate;

  /// Share of frames, with a plate facing the camera, that the reader reads.
  final double plateRate;

  static double _one(double t) => 1;
  static bool _always(double t) => true;
  static bool _never(double t) => false;
}

/// What one detector run hands the app.
class SimDetection {
  SimDetection({
    required this.frameAt,
    required this.box,
    this.plateX,
    this.plateY,
  });

  /// Seconds; when the frame reached Dart. The exposure was earlier.
  final double frameAt;

  /// Upright, normalised.
  final Rect box;

  /// Where the plate was read, normalised, if it was.
  final double? plateX;
  final double? plateY;
}

/// The thing under test.
abstract class SimTracker {
  void gyro(double t, double yaw, {required bool walking});
  void detection(double t, SimDetection d);

  /// The azimuth the outline is asked to show, or null with no fix.
  double? get azimuth;
}

class SimResult {
  SimResult(this.name);
  final String name;
  final List<double> errors = [];
  int jumps = 0;
  double? fixAt;
  int falseGreen = 0;
  int scored = 0;

  double get rms => errors.isEmpty
      ? double.nan
      : math.sqrt(
          errors.map((e) => e * e).reduce((a, b) => a + b) / errors.length,
        );

  double get p95 {
    if (errors.isEmpty) return double.nan;
    final s = [...errors]..sort();
    return s[(s.length * 0.95).floor().clamp(0, s.length - 1)];
  }

  double get max => errors.isEmpty ? double.nan : errors.reduce(math.max);

  @override
  String toString() =>
      '${name.padRight(22)} rms ${rms.toStringAsFixed(1).padLeft(5)}°  '
      'p95 ${p95.toStringAsFixed(1).padLeft(5)}°  '
      'max ${max.toStringAsFixed(1).padLeft(5)}°  '
      'jumps $jumps  falseGreen $falseGreen/$scored  '
      'fix ${fixAt?.toStringAsFixed(1) ?? "-"}s';
}

class WalkSimulator {
  WalkSimulator(this.renderer, {this.viewport = const Size(346, 461)});

  final OutlineRenderer renderer;
  final Size viewport;

  static const double fovY = OrbitView.defaultFovY;

  /// Gyro frame = car frame turned by this: bearing = azimuth − offset.
  static const double gyroOffset = 61;

  /// Exposure to Dart, and Dart to the box being handed over.
  static const double frameLatency = 0.07;
  static const double inference = 0.04;

  double get focal => viewport.height / 2 / math.tan(fovY * math.pi / 360);

  double baseDistance(double azimuth) => renderer.fitDistance(
    OrbitView(azimuth: azimuth, distance: 5, viewport: viewport),
  );

  SimResult run(
    Scenario s,
    SimTracker tracker, {
    int seed = 1,
    double ease = 0.07,
    double tolerance = 10,
    void Function(double t, double truth, double? want, double shown)? trace,
  }) {
    final rnd = math.Random(seed);
    double gauss() {
      final u = math.max(1e-9, rnd.nextDouble()), v = rnd.nextDouble();
      return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
    }

    final d0 = baseDistance(s.prior);
    final result = SimResult(s.name);
    const dt = 0.01;
    var nextFrame = 0.1 + rnd.nextDouble() * 0.05;
    final pending = <(double, SimDetection)>[];
    double? shown;
    final history = <(double, double, double)>[]; // t, shown, truth (unwrapped)
    var shownUnwrapped = 0.0, truthUnwrapped = 0.0;
    double? lastShown, lastTruth;
    var lastJumpAt = -10.0;
    var inViewSince = 0.0;
    var wasInView = false;

    for (var t = 0.0; t <= s.duration; t += dt) {
      final az = s.az(t);
      final bearing = az - gyroOffset;
      final yaw = bearing + s.pan(t) + 0.015 * t + gauss() * 0.04;
      tracker.gyro(t, yaw, walking: s.walking(t));

      if (t >= nextFrame) {
        nextFrame += 0.2 + (rnd.nextDouble() - 0.5) * 0.04;
        final exposed = t - frameLatency;
        final d = _detect(s, exposed, d0, rnd, gauss);
        if (d != null) {
          pending.add((
            t + inference,
            SimDetection(frameAt: t, box: d.$1, plateX: d.$2, plateY: d.$3),
          ));
        }
      }
      while (pending.isNotEmpty && pending.first.$1 <= t) {
        tracker.detection(t, pending.removeAt(0).$2);
      }

      final want = tracker.azimuth;
      if (want != null && result.fixAt == null) result.fixAt = t;
      final settled = result.fixAt != null && t - result.fixAt! > 1.2;
      final target = want ?? s.prior;
      shown = shown == null
          ? target
          : wrapDegrees(
              shown + wrapDegrees(target - shown) * (1 - math.exp(-dt / ease)),
            );

      // unwrap both so a 0.5 s window can be compared across ±180
      if (lastShown != null) {
        shownUnwrapped += wrapDegrees(shown - lastShown);
        truthUnwrapped += wrapDegrees(az - lastTruth!);
      }
      lastShown = shown;
      lastTruth = az;
      history.add((t, shownUnwrapped, truthUnwrapped));
      while (history.first.$1 < t - 0.5) {
        history.removeAt(0);
      }
      final first = history.first;
      final excess = ((shownUnwrapped - first.$2) - (truthUnwrapped - first.$3))
          .abs();
      final inView = s.inView(t);
      if (settled && inView && excess > 15 && t - lastJumpAt > 0.5) {
        result.jumps++;
        lastJumpAt = t;
      }

      if (inView && !wasInView) inViewSince = t;
      wasInView = inView;
      if (trace != null && (t * 100).round() % 20 == 0) {
        trace(t, az, want, shown);
      }
      if (want != null &&
          settled &&
          inView &&
          t >= 2 &&
          t - inViewSince >= 1.5) {
        final err = wrapDegrees(shown - az).abs();
        result.errors.add(err);
        result.scored++;
        final saysThere = wrapDegrees(want - s.prior).abs() <= tolerance;
        final isThere = wrapDegrees(az - s.prior).abs() <= tolerance + 8;
        if (saysThere && !isThere) result.falseGreen++;
      }
    }
    return result;
  }

  /// One detector run on the frame exposed at [t]: the box, and the plate
  /// if it was read.
  (Rect, double?, double?)? _detect(
    Scenario s,
    double t,
    double d0,
    math.Random rnd,
    double Function() gauss,
  ) {
    if (!s.inView(t)) return null;
    if (rnd.nextDouble() < 0.12) return null; // missed
    var az = s.az(t);
    var distance = d0 * s.distanceScale(t);
    var shift = math.tan(s.pan(t) * math.pi / 180) * focal / viewport.width;
    final neighbour = rnd.nextDouble() < s.neighbourRate;
    if (neighbour) {
      // the car in the next bay: further back, side-on, off to the right
      az = wrapDegrees(az + 65);
      distance *= 1.8;
      shift += 0.30;
    }
    final view = OrbitView(azimuth: az, distance: distance, viewport: viewport);
    final b = renderer.bounds(view);
    var l = b.left / viewport.width + shift;
    var r = b.right / viewport.width + shift;
    var top = b.top / viewport.height;
    var bottom = b.bottom / viewport.height;
    // COCO SSD stops short of the roof and the tyres: ~4.4% flatter
    final h = bottom - top, cy = (top + bottom) / 2;
    top = cy - h / 2 / 1.044;
    bottom = cy + h / 2 / 1.044;
    final w = r - l, hh = bottom - top;
    l += gauss() * 0.012 * w;
    r += gauss() * 0.012 * w;
    top += gauss() * 0.015 * hh;
    bottom += gauss() * 0.015 * hh;
    if (rnd.nextDouble() < 0.08) {
      // shadow under the sills, a pillar across the roof
      top += (rnd.nextDouble() - 0.4) * 0.25 * hh;
    }
    final box = Rect.fromLTRB(
      l.clamp(0.0, 1.0),
      top.clamp(0.0, 1.0),
      r.clamp(0.0, 1.0),
      bottom.clamp(0.0, 1.0),
    );

    double? plateX, plateY;
    final facing = math.cos(az * math.pi / 180);
    if (!neighbour && facing.abs() > 0.45 && rnd.nextDouble() < s.plateRate) {
      final front = facing > 0;
      final p = renderer.project(
        view,
        front ? 2.02 : -1.96,
        front ? -0.04 : -0.09,
        front ? 0.44 : 0.715,
      );
      plateX = p.dx / viewport.width + shift;
      plateY = p.dy / viewport.height;
    }
    return (box, plateX, plateY);
  }
}

// ---------------------------------------------------------------------------

double _sway(double t, double amp, double hz, [double phase = 0]) =>
    amp * math.sin(2 * math.pi * hz * t + phase);

double _ramp(double t, double t0, double t1, double a, double b) {
  if (t <= t0) return a;
  if (t >= t1) return b;
  final u = (t - t0) / (t1 - t0);
  return a + (b - a) * (0.5 - 0.5 * math.cos(math.pi * u));
}

/// The scripts. Every one starts with the driver already holding the phone
/// up at the car, since that is when the viewfinder opens.
final List<Scenario> scenarios = [
  // Standing at the corner, panning to centre the car in the outline. The
  // driver is not moving round the car at all.
  Scenario(
    name: 'pan at 左前',
    duration: 12,
    prior: 40,
    az: (t) => 40 + _sway(t, 1, 0.1),
    pan: (t) => _sway(t, 11, 0.21) + _sway(t, 5, 0.57, 1),
  ),
  // Walking from 左前 to 右前 with the car in frame the whole way.
  Scenario(
    name: 'walk phone up',
    duration: 18,
    prior: 40,
    az: (t) => _ramp(t, 4, 12, 40, -40),
    pan: (t) => _sway(t, 4, 0.3),
    walking: (t) => t > 4 && t < 12,
  ),
  // Lowering the phone, walking round the nose facing where they are going,
  // and raising it again at 右前.
  Scenario(
    name: 'walk phone down',
    duration: 18,
    prior: -40,
    az: (t) => _ramp(t, 5, 11, 40, -40),
    pan: (t) =>
        _ramp(t, 4, 5.5, 0, -90) + _ramp(t, 10, 11.5, 0, 90) + _sway(t, 3, 0.4),
    inView: (t) => t < 4.2 || t > 11.5,
    walking: (t) => t > 5 && t < 11,
  ),
  // At 右後 in a car park: the detector boxes the car next door a fifth of
  // the time.
  Scenario(
    name: 'neighbour car 右後',
    duration: 14,
    prior: -140,
    az: (t) => -140 + _sway(t, 1, 0.1),
    pan: (t) => _sway(t, 7, 0.25),
    neighbourRate: 0.22,
  ),
  // Standing at 右前 while the slot asks for 左前: must not go green.
  Scenario(
    name: 'wrong side 右前',
    duration: 10,
    prior: 40,
    az: (t) => -40 + _sway(t, 1, 0.1),
    pan: (t) => _sway(t, 6, 0.25),
  ),
  // Standing at 右後 — diagonally opposite — while the slot asks for 左前.
  Scenario(
    name: 'opposite 右後',
    duration: 10,
    prior: 40,
    az: (t) => -140 + _sway(t, 1, 0.1),
    pan: (t) => _sway(t, 6, 0.25),
    plateRate: 0.5,
  ),
  // Walking in and out: the box grows and shrinks.
  Scenario(
    name: 'step in/out 左後',
    duration: 12,
    prior: 140,
    az: (t) => 140 + _sway(t, 2, 0.08),
    pan: (t) => _sway(t, 5, 0.3),
    distanceScale: (t) => 1 + _sway(t, 0.35, 0.12),
    walking: (t) => (t % 8) > 2 && (t % 8) < 4,
  ),
];
