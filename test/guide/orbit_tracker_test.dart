import 'package:flutter_test/flutter_test.dart';
import 'package:irent_pulse/guide/orbit.dart';

/// Every mirror image of [az], the way a box with no plate reads.
List<OrbitCandidate> mirrors(double az) => [
  for (final a in [az, -az, 180 - az, az - 180])
    OrbitCandidate(wrapDegrees(a), sigma: 3),
];

/// [az] picked out by the plate, its mirror images all but ruled out.
List<OrbitCandidate> plated(double az) => [
  for (final a in [az, -az, 180 - az, az - 180])
    OrbitCandidate(wrapDegrees(a), sigma: 3, weight: a == az ? 1 : 0.02),
];

/// Feeds a tracker readings at 5 Hz on its own clock.
class Feed {
  Feed(this.tracker);
  final OrbitTracker tracker;
  double t = 0;
  double yaw = 0;

  void heading(double value, {bool walking = false}) {
    yaw = value;
    tracker.updateYaw(value, walking: walking, at: t);
  }

  /// One box: [candidates], with the car's middle at [bearing] in the gyro
  /// frame, [size] of the frame wide.
  void box(
    List<OrbitCandidate> candidates, {
    double bearing = 0,
    double size = 0.8,
    double prior = 40,
  }) {
    t += 0.2;
    tracker.updateYaw(yaw, at: t);
    tracker.observe(
      candidates,
      bearing: bearing,
      size: size,
      at: t,
      prior: prior,
    );
  }
}

void main() {
  test('wrapDegrees keeps angles in [-180, 180)', () {
    expect(wrapDegrees(190), -170);
    expect(wrapDegrees(-190), 170);
    expect(wrapDegrees(180), -180);
    expect(wrapDegrees(40), 40);
  });

  test('no fix until a few readings agree', () {
    final f = Feed(OrbitTracker());
    f.box(plated(38));
    f.box(plated(40));
    expect(f.tracker.hasFix, isFalse);
    f.box(plated(41));
    expect(f.tracker.hasFix, isTrue);
    expect(f.tracker.azimuth, closeTo(39.7, 1));
  });

  test('with nothing to tell the mirror images apart, the slot decides', () {
    final f = Feed(OrbitTracker());
    for (var i = 0; i < OrbitTracker.patience - 1; i++) {
      f.box(mirrors(35), prior: -40);
      expect(f.tracker.hasFix, isFalse, reason: 'waits for a plate');
    }
    f.box(mirrors(35), prior: -40);
    expect(f.tracker.azimuth, closeTo(-35, 0.5));
  });

  test('one plate reading outweighs the slot', () {
    // Standing at 右前 while the slot asks for 左前: the old tracker took the
    // slot's mirror image and showed the wrong side of the car.
    final f = Feed(OrbitTracker());
    f.box(mirrors(-40), prior: 40);
    f.box(plated(-40), prior: 40);
    f.box(mirrors(-40), prior: 40);
    expect(f.tracker.azimuth, closeTo(-40, 1));
  });

  test('panning the phone does not turn the outline', () {
    final f = Feed(OrbitTracker());
    for (var i = 0; i < 3; i++) {
      f.box(plated(40));
    }
    // Turned 15° left: the car slid right in the frame, so the box's
    // bearing — heading plus where it is in the frame — has not moved.
    f.heading(15);
    expect(f.tracker.azimuth, closeTo(40, 0.5));
    f.box(plated(40));
    expect(f.tracker.azimuth, closeTo(40, 0.5));
  });

  test('walking, the heading carries the outline round', () {
    final f = Feed(OrbitTracker());
    for (var i = 0; i < 3; i++) {
      f.box(plated(40));
    }
    // walked clockwise round the nose with the phone down
    f.t += 1;
    f.heading(-30, walking: true);
    expect(f.tracker.azimuth, closeTo(10, 0.5));
    f.heading(-80, walking: true);
    expect(f.tracker.azimuth, closeTo(-40, 0.5));
    // and the car, seen again from there, agrees
    f.heading(-80);
    f.box(plated(-40), bearing: -80);
    expect(f.tracker.azimuth, closeTo(-40, 1));
  });

  test('an arm swinging the phone about is not a walk round the car', () {
    // The footstep detector also fires on the phone being waved about. With
    // the car in view the box says where it is, and the heading stays out.
    final f = Feed(OrbitTracker());
    for (var i = 0; i < 3; i++) {
      f.box(plated(40));
    }
    f.t += 0.1;
    f.heading(20, walking: true);
    expect(f.tracker.azimuth, closeTo(40, 0.5));
  });

  test('the car in the next bay is not followed', () {
    final f = Feed(OrbitTracker());
    for (var i = 0; i < 4; i++) {
      f.box(plated(-140));
    }
    // smaller, off to one side, side-on
    for (var i = 0; i < OrbitTracker.rebaseStill - 1; i++) {
      f.box(mirrors(-100), bearing: -14, size: 0.45, prior: -140);
      expect(f.tracker.azimuth, closeTo(-140, 0.5));
    }
    f.box(plated(-140), prior: -140);
    expect(f.tracker.azimuth, closeTo(-140, 1));
  });

  test('plate readings move a fix off the wrong mirror image', () {
    final f = Feed(OrbitTracker());
    for (var i = 0; i < OrbitTracker.patience; i++) {
      f.box(mirrors(-40), prior: 40);
    }
    expect(f.tracker.azimuth, closeTo(40, 1), reason: 'took the slot');
    var n = 0;
    while (f.tracker.azimuth!.abs() > 45 || f.tracker.azimuth! > 0) {
      f.box(plated(-40), prior: 40);
      expect(++n, lessThan(12));
    }
    expect(f.tracker.azimuth, closeTo(-40, 1));
  });

  test('the box readings pull the gyroscope drift back', () {
    final f = Feed(OrbitTracker());
    for (var i = 0; i < 3; i++) {
      f.box(plated(40));
    }
    // The heading drifts 6° over two minutes while the driver stands still
    // — a poor gyroscope — and the car's bearing, read through it, drifts
    // the same way.
    for (var i = 1; i <= 600; i++) {
      f.heading(i * 0.01);
      f.box(plated(40), bearing: i * 0.01);
    }
    expect(f.tracker.azimuth, closeTo(40, 1));
  });
}
