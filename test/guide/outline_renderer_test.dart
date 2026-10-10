import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irent_itrust/guide/car_model.dart';
import 'package:irent_itrust/guide/orbit.dart';
import 'package:irent_itrust/guide/orbit_guide.dart';
import 'package:irent_itrust/guide/outline_renderer.dart';

/// Where to drop the rendered previews, for looking at rather than asserting.
/// `flutter test --dart-define=ORBIT_PREVIEW_DIR=build/orbit_preview`
const String _previewDir = String.fromEnvironment('ORBIT_PREVIEW_DIR');

void main() {
  late CarModel model;
  late OutlineRenderer renderer;
  const viewport = Size(
    346,
    461,
  ); // Pixel 10 Pro at its enlarged display size, 3:4

  setUpAll(() {
    final json = jsonDecode(File(CarModel.asset).readAsStringSync());
    model = CarModel.fromJson(json as Map<String, dynamic>);
    renderer = OutlineRenderer(model);
  });

  OrbitView view(double az, {double distance = 6}) =>
      OrbitView(azimuth: az, distance: distance, viewport: viewport);

  test('the model is the published size', () {
    var minX = double.infinity, maxX = -double.infinity;
    var maxZ = 0.0;
    final v = model.vertices;
    for (var i = 0; i < model.vertexCount; i++) {
      minX = math.min(minX, v[i * 3]);
      maxX = math.max(maxX, v[i * 3]);
      maxZ = math.max(maxZ, v[i * 3 + 2]);
    }
    expect(maxX - minX, closeTo(4.050, 0.01));
    expect(maxZ, closeTo(1.455, 0.01)); // to the tip of the roof fin
    expect(model.length, 4.050);
  });

  test('left and right corners are mirror images', () {
    for (final az in [40.0, 140.0]) {
      final a = renderer.bounds(view(az));
      final b = renderer.bounds(view(-az));
      expect(a.width, closeTo(b.width, 0.5));
      expect(a.height, closeTo(b.height, 0.5));
    }
  });

  test('the box is widest side-on and narrowest end-on', () {
    double aspect(double az) {
      final b = renderer.bounds(view(az));
      return b.width / b.height;
    }

    expect(aspect(90), greaterThan(aspect(40)));
    expect(aspect(40), greaterThan(aspect(0)));
    expect(aspect(-90), greaterThan(aspect(-140)));
    expect(aspect(-140), greaterThan(aspect(180)));
  });

  test('fitDistance fills the requested share of the frame', () {
    final d = renderer.fitDistance(view(40), widthFraction: 0.82);
    final b = renderer.bounds(view(40, distance: d));
    expect(b.width / viewport.width, closeTo(0.82, 0.01));
    // a person can actually stand there
    expect(d, inInclusiveRange(3.5, 9.0));
  });

  test('a corner render has a silhouette and detail lines', () {
    final frame = renderer.render(view(40));
    expect(frame.silhouette.length, greaterThan(200));
    expect(frame.details.length, greaterThan(100));
    expect(frame.fill.length % 6, 0);
  });

  test('the plate end is on the left of the box at 左前 and 右後', () {
    // front plate centre ~ (x = +2.0, y = 0, z = 0.40); rear ~ (-2.0, 0, 0.72)
    Offset project(Offset3 p, double az) {
      final frame = renderer.bounds(view(az));
      final a = az * math.pi / 180;
      // same camera as the renderer
      final eye = [6 * math.cos(a), 6 * math.sin(a), 1.40];
      var f = [-eye[0], -eye[1], 0.62 - eye[2]];
      final fl = math.sqrt(f[0] * f[0] + f[1] * f[1] + f[2] * f[2]);
      f = [f[0] / fl, f[1] / fl, f[2] / fl];
      final rl = math.sqrt(f[1] * f[1] + f[0] * f[0]);
      final r = [f[1] / rl, -f[0] / rl, 0.0];
      final d = [p.x - eye[0], p.y - eye[1], p.z - eye[2]];
      final xc = d[0] * r[0] + d[1] * r[1];
      final zc = d[0] * f[0] + d[1] * f[1] + d[2] * f[2];
      final focal =
          viewport.height / 2 / math.tan(OrbitView.defaultFovY * math.pi / 360);
      final u = viewport.width / 2 + focal * xc / zc;
      return Offset((u - frame.center.dx) / frame.width, 0);
    }

    expect(project(const Offset3(2.0, 0, 0.4), 40).dx, lessThan(-0.08)); // 左前
    expect(
      project(const Offset3(2.0, 0, 0.4), -40).dx,
      greaterThan(0.08),
    ); // 右前
    expect(
      project(const Offset3(-2.0, 0, 0.72), -140).dx,
      lessThan(-0.08),
    ); // 右後
    expect(
      project(const Offset3(-2.0, 0, 0.72), 140).dx,
      greaterThan(0.08),
    ); // 左後
  });

  BoxPoseEstimator estimator() => BoxPoseEstimator(renderer.poseTable(view(0)));

  List<double> read(
    BoxPoseEstimator e,
    double az,
    double distance, {
    double? plateSide,
  }) {
    final b = renderer.bounds(view(az, distance: distance));
    return e.candidates(
      b.width / b.height,
      widthFraction: b.width / viewport.width,
      plateSide: plateSide,
    );
  }

  double nearest(List<double> got, double az) =>
      got.map((c) => wrapDegrees(c - az).abs()).reduce(math.min);

  test('the box reads back the corner, up to the mirror', () {
    final e = estimator();
    for (final az in [40.0, -40.0, 140.0, -140.0, 65.0]) {
      final got = read(e, az, 5.0);
      expect(nearest(got, az), lessThan(3), reason: 'az $az -> $got');
    }
  });

  test('standing further back does not skew the angle', () {
    // The shape alone read 40° at 11 m as 55°: the near end stops looming and
    // the box gets flatter. The width in the frame is what corrects for it.
    final e = estimator();
    for (final d in [3.2, 5.5, 8.0, 11.0, 15.0]) {
      for (final az in [40.0, -140.0]) {
        final got = read(e, az, d);
        expect(nearest(got, az), lessThan(4), reason: 'az $az at $d m -> $got');
      }
    }
  });

  test('a box narrower than any end-on view offers both ends of the car', () {
    // On the phone a box this narrow came back as the tail only, and the
    // tracker re-anchored a driver standing at the nose behind the car.
    final got = estimator().candidates(0.9, widthFraction: 0.5);
    expect(got.any((c) => c.abs() < 10), isTrue, reason: '$got');
    expect(got.any((c) => c.abs() > 170), isTrue, reason: '$got');
  });

  test('the tracker stays at the nose when the box turns ambiguous', () {
    final e = estimator();
    final tracker = OrbitTracker();
    var t = 0.0;
    void feed(double aspect, (double, double) plate) => tracker.observe(
      e.read(aspect, widthFraction: 0.6, plate: plate),
      bearing: 0,
      size: 0.6,
      at: t += 0.2,
      prior: 40,
    );
    for (var i = 0; i < 3; i++) {
      feed(1.29, (-0.25, 0.25));
    }
    expect(tracker.azimuth!.abs(), lessThan(25));
    for (var i = 0; i < 20; i++) {
      feed(1.05, (-0.1, 0.2));
    }
    expect(tracker.azimuth!.abs(), lessThan(25));
  });

  test('the plate picks the corner, front from rear included', () {
    final e = estimator();
    for (final az in [40.0, -40.0, 140.0, -140.0]) {
      final view = OrbitView(azimuth: az, distance: 5, viewport: viewport);
      final b = renderer.bounds(view);
      final front = az.abs() < 90;
      final p = renderer.project(
        view,
        front ? 2.02 : -1.96,
        front ? -0.04 : -0.09,
        front ? 0.44 : 0.715,
      );
      final got = e.read(
        b.width / b.height,
        widthFraction: b.width / viewport.width,
        plate: ((p.dx - b.center.dx) / b.width, (b.bottom - p.dy) / b.height),
      );
      final best = got.reduce((a, c) => c.weight > a.weight ? c : a);
      expect(wrapDegrees(best.azimuth - az).abs(), lessThan(3), reason: '$got');
      for (final c in got) {
        if (c != best) expect(c.weight, lessThan(0.1), reason: '$got');
      }
    }
  });

  test('a box side-on reads vaguer than one at a corner', () {
    final e = estimator();
    double sigmaAt(double az) {
      final b = renderer.bounds(view(az, distance: 5));
      final got = e.read(
        b.width / b.height,
        widthFraction: b.width / viewport.width,
      );
      return got
          .reduce(
            (a, c) =>
                wrapDegrees(c.azimuth - az).abs() <
                    wrapDegrees(a.azimuth - az).abs()
                ? c
                : a,
          )
          .sigma;
    }

    // side-on the box is at its flattest and hardly changes as you move
    expect(sigmaAt(88), greaterThan(sigmaAt(40) * 2));
  });

  test('the plate side keeps only the right pair of corners', () {
    final left = read(estimator(), 40, 5.0, plateSide: -0.3);
    for (final c in left) {
      expect(math.sin(2 * c * math.pi / 180), greaterThan(0));
    }
    expect(left.any((c) => wrapDegrees(c - 40).abs() < 3), isTrue);
    expect(left.any((c) => wrapDegrees(c + 40).abs() < 3), isFalse);
  });

  test('the pose table is cheap enough to build on the UI thread', () {
    final watch = Stopwatch()..start();
    renderer.poseTable(view(0));
    // 180 azimuths × 12 distances over the hull; the old full-mesh version
    // would have been ~6× this. Generous bound for a CI machine.
    expect(watch.elapsedMilliseconds, lessThan(400));
  });

  testWidgets('render previews', (tester) async {
    if (_previewDir.isEmpty) return;
    Directory(_previewDir).createSync(recursive: true);
    for (final az in [40.0, -40.0, -140.0, 140.0, 90.0, 0.0]) {
      final d = renderer.fitDistance(view(az));
      final frame = renderer.render(view(az, distance: d));
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Offset.zero & viewport,
        Paint()..color = const Color(0xFF26323F),
      );
      OutlinePainter(frame: frame, color: Colors.white).paint(canvas, viewport);
      final image = await tester.runAsync(
        () => recorder.endRecording().toImage(
          viewport.width.toInt(),
          viewport.height.toInt(),
        ),
      );
      final bytes = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.png),
      );
      File('$_previewDir/az_${az.round()}.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    }
  });
}

class Offset3 {
  const Offset3(this.x, this.y, this.z);
  final double x, y, z;
}
