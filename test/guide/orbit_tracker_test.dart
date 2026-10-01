import 'package:flutter_test/flutter_test.dart';
import 'package:irent_pulse/guide/orbit.dart';

void main() {
  test('wrapDegrees keeps angles in [-180, 180)', () {
    expect(wrapDegrees(190), -170);
    expect(wrapDegrees(-190), 170);
    expect(wrapDegrees(180), -180);
    expect(wrapDegrees(40), 40);
  });

  test('no fix until the detector agrees with itself', () {
    final t = OrbitTracker();
    t.observe([38, -38, 142, -142], prior: 40);
    t.observe([40, -40, 140, -140], prior: 40);
    expect(t.hasFix, isFalse);
    t.observe([41, -41, 139, -139], prior: 40);
    expect(t.hasFix, isTrue);
    expect(t.azimuth, closeTo(39.7, 0.5));
  });

  test('the prior picks the mirror image nearest the slot being shot', () {
    final t = OrbitTracker();
    for (var i = 0; i < 3; i++) {
      t.observe([35, -35, 145, -145], prior: -40);
    }
    expect(t.azimuth, closeTo(-35, 0.5));
  });

  test('the gyroscope carries the fix', () {
    final t = OrbitTracker();
    t.updateYaw(100);
    for (var i = 0; i < 3; i++) {
      t.observe([40], prior: 40);
    }
    t.updateYaw(70); // turned 30° clockwise: walked towards the nose
    expect(t.azimuth, closeTo(10, 0.01));
    t.updateYaw(130);
    expect(t.azimuth, closeTo(70, 0.01));
  });

  test('agreeing readings pull drift back, a little at a time', () {
    final t = OrbitTracker();
    for (var i = 0; i < 3; i++) {
      t.observe([40], prior: 40);
    }
    t.updateYaw(10); // gyro drifted 10° but the driver has not moved
    expect(t.azimuth, closeTo(50, 0.01));
    for (var i = 0; i < 30; i++) {
      t.observe([40, -40, 140, -140], prior: 40);
    }
    // to within the 2° dead band that keeps detector noise off the outline
    expect(t.azimuth, closeTo(40, 2.1));
  });

  test('a reading that keeps disagreeing re-anchors', () {
    final t = OrbitTracker();
    for (var i = 0; i < 3; i++) {
      t.observe([40], prior: 40);
    }
    for (var i = 0; i < OrbitTracker.dissentToRefix - 1; i++) {
      t.observe([-40], prior: 40);
    }
    expect(t.azimuth, closeTo(40, 0.01));
    t.observe([-40], prior: 40);
    expect(t.azimuth, closeTo(-40, 0.01));
  });
}
