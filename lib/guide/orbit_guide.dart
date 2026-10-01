import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'car_model.dart';
import 'heading.dart';
import 'orbit.dart';
import 'outline_renderer.dart';

/// Everything the viewfinder needs to draw a car outline that turns as the
/// driver walks round the car.
///
/// Owns the model and its renderer, the gyroscope, and the [OrbitTracker]
/// that fuses the gyroscope with what the detector sees. The screen tells it
/// the size of the preview and which corner it is shooting; it answers with
/// an outline, the box L0 should score against, and how far off the angle is.
class OrbitGuide extends ChangeNotifier {
  OrbitGuide({this.useGyroscope = true});

  final bool useGyroscope;

  final OrbitTracker tracker = OrbitTracker();
  final HeadingTracker heading = HeadingTracker();

  CarModel? _model;
  OutlineRenderer? _renderer;
  Object? loadError;

  bool get ready => _renderer != null;
  CarModel? get model => _model;

  Size _viewport = Size.zero;
  double _target = 40;
  double _zoom = 1;
  double _distance = 5;
  double _shiftX = 0;
  BoxPoseEstimator? _pose;
  String _configKey = '';

  /// Angle, in degrees either side of the target, that counts as "there".
  static const double tolerance = 10;

  /// Detector box aspect ÷ model box aspect, measured. See [observeBox].
  static const double detectorAspectBias = 1.044;

  Future<void> load() async {
    try {
      final model = await CarModel.load();
      _model = model;
      _renderer = OutlineRenderer(model);
      _configKey = '';
      if (useGyroscope) {
        heading.addListener(_onHeading);
        heading.start();
      }
      notifyListeners();
    } catch (error) {
      loadError = error;
      debugPrint('Orbit: 輪廓模型載入失敗 — $error');
    }
  }

  void _onHeading() => tracker.updateYaw(heading.yaw);

  /// The preview the outline is drawn into, the corner being shot, and the
  /// lens zoom (which narrows the field of view).
  void configure({
    required Size viewport,
    required double target,
    double zoom = 1,
  }) {
    final renderer = _renderer;
    if (renderer == null || viewport.isEmpty) return;
    final key =
        '${viewport.width.round()}x${viewport.height.round()}|$target|${zoom.toStringAsFixed(2)}';
    if (key == _configKey) return;
    _configKey = key;
    _viewport = viewport;
    _target = target;
    _zoom = zoom;
    _shiftX = 0;
    _distance = renderer.fitDistance(_view(target, 5));
    final atTarget = renderer.bounds(_view(target, _distance));
    _shiftX = viewport.width / 2 - atTarget.center.dx;
    _pose = BoxPoseEstimator(renderer.poseTable(_view(0, _distance)));
    _frameKey = null;
  }

  double get target => _target;

  /// The azimuth the outline was last drawn at. It trails [azimuth] by a few
  /// frames while it eases, and the L0 box should match what is on screen.
  double? shownAzimuth;

  OrbitView _view(double azimuth, double distance) => OrbitView(
    azimuth: azimuth,
    distance: distance,
    viewport: _viewport,
    shiftX: _shiftX,
    fovY:
        2 *
        math.atan(math.tan(OrbitView.defaultFovY * math.pi / 360) / _zoom) *
        180 /
        math.pi,
  );

  /// The azimuth the driver is at, or null until something has placed them.
  double? get azimuth => tracker.azimuth;

  /// Signed degrees from the driver to the target: positive means walk to
  /// your right (anticlockwise round the car).
  double? get angleError {
    final az = azimuth;
    return az == null ? null : wrapDegrees(_target - az);
  }

  bool get atTarget {
    final e = angleError;
    return e != null && e.abs() <= tolerance;
  }

  OutlineFrame? _frame;
  String? _frameKey;

  static const bool _log = bool.fromEnvironment('ORBIT_LOG');
  int _renders = 0;
  int _renderMicros = 0;

  /// The outline seen from [azimuth], cached to a tenth of a degree.
  OutlineFrame? frameAt(double azimuth) {
    final renderer = _renderer;
    if (renderer == null || _viewport.isEmpty) return null;
    final key = '$_configKey|${(azimuth * 10).round()}';
    if (key == _frameKey && _frame != null) return _frame;
    _frameKey = key;
    final watch = _log ? (Stopwatch()..start()) : null;
    _frame = renderer.render(_view(azimuth, _distance));
    if (watch != null) {
      _renderMicros += watch.elapsedMicroseconds;
      if (++_renders == 60) {
        debugPrint(
          'Orbit 輪廓: ${(_renderMicros / _renders / 1000).toStringAsFixed(1)} ms/張 '
          'az=${azimuth.toStringAsFixed(1)} fixed=${tracker.hasFix}',
        );
        _renders = 0;
        _renderMicros = 0;
      }
    }
    return _frame;
  }

  /// Where the car should be, in the preview's normalised coordinates — the
  /// rectangle L0 scores the detector's box against.
  Rect? guideRectAt(double azimuth) {
    final frame = frameAt(azimuth);
    if (frame == null || _viewport.isEmpty) return null;
    final b = frame.bounds;
    return Rect.fromLTRB(
      (b.left / _viewport.width).clamp(0.0, 1.0),
      (b.top / _viewport.height).clamp(0.0, 1.0),
      (b.right / _viewport.width).clamp(0.0, 1.0),
      (b.bottom / _viewport.height).clamp(0.0, 1.0),
    );
  }

  /// One detector box, in the upright normalised frame, and — when the plate
  /// reader found a plate on this car — where across the frame it was.
  void observeBox(Rect box, {double? plateX}) {
    final pose = _pose;
    if (pose == null || _viewport.isEmpty || !boxIsWhole(box)) return;
    // COCO SSD's box stops a little short of the roof and the tyres, so it
    // comes out ~4.5% flatter than the model's own bounds: 1.048 and 1.040 on
    // the two reference photos whose cameras were solved from the wheels
    // (tool/aqua_outline/). Uncorrected that is ~4° at the corners.
    final aspect =
        box.width *
        _viewport.width /
        (box.height * _viewport.height) /
        detectorAspectBias;
    double? side;
    if (plateX != null && plateX >= box.left && plateX <= box.right) {
      side = (plateX - box.center.dx) / box.width;
    }
    final candidates = pose.candidates(
      aspect,
      widthFraction: box.width,
      plateSide: side,
    );
    tracker.observe(candidates, prior: _target);
    if (_log) {
      debugPrint(
        'Orbit 偵測: aspect=${aspect.toStringAsFixed(2)} '
        'w=${box.width.toStringAsFixed(2)} '
        'plate=${side?.toStringAsFixed(2) ?? "-"} '
        '候選=${candidates.map((c) => c.round()).toList()} '
        '→ az=${tracker.azimuth?.toStringAsFixed(1) ?? "未定"}',
      );
    }
  }

  @override
  void dispose() {
    heading.removeListener(_onHeading);
    heading.dispose();
    tracker.dispose();
    super.dispose();
  }
}

/// The outline itself, drawn over the preview.
///
/// It eases towards the tracked azimuth on every vsync rather than jumping to
/// it: the gyroscope is smooth already, but the first fix and every
/// re-anchor would otherwise snap the whole car round in one frame, and a
/// guide that lurches reads as a guide that is broken.
class OrbitOutline extends StatefulWidget {
  const OrbitOutline({super.key, required this.guide, required this.color});

  final OrbitGuide guide;
  final Color color;

  @override
  State<OrbitOutline> createState() => _OrbitOutlineState();
}

class _OrbitOutlineState extends State<OrbitOutline>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  double? _shown;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    unawaited(_ticker.start());
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final want = widget.guide.azimuth ?? widget.guide.target;
    final shown = _shown;
    if (shown == null) {
      setState(() => _shown = want);
      return;
    }
    final error = wrapDegrees(want - shown);
    if (error.abs() < 0.05) return;
    final k = 1 - math.exp(-dt.clamp(0.0, 0.1) / 0.07);
    setState(() => _shown = wrapDegrees(shown + error * k));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown ?? widget.guide.azimuth ?? widget.guide.target;
    widget.guide.shownAzimuth = shown;
    final frame = widget.guide.frameAt(shown);
    if (frame == null) return const SizedBox.expand();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: OutlinePainter(frame: frame, color: widget.color),
      ),
    );
  }
}

/// Paints an [OutlineFrame]: a faint wash of the car's shape, a dark halo so
/// the lines survive a bright wall, and the lines.
class OutlinePainter extends CustomPainter {
  OutlinePainter({required this.frame, required this.color});

  final OutlineFrame frame;
  final Color color;

  static const double _silhouetteWidth = 2.6;
  static const double _lineWidth = 1.4;

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.fill.isNotEmpty) {
      // Opaque triangles inside a translucent layer, so where faces overlap
      // the wash does not build up into blotches.
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = color.withValues(alpha: 0.12),
      );
      canvas.drawVertices(
        ui.Vertices.raw(ui.VertexMode.triangles, frame.fill),
        BlendMode.srcOver,
        Paint()..color = const Color(0xFFFFFFFF),
      );
      canvas.restore();
    }

    Paint stroke(double width, Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width
      ..color = c;

    const halo = Color(0x59000000);
    canvas.drawRawPoints(
      ui.PointMode.lines,
      frame.details,
      stroke(_lineWidth + 1.6, halo),
    );
    canvas.drawRawPoints(
      ui.PointMode.lines,
      frame.creases,
      stroke(_lineWidth + 1.6, halo),
    );
    canvas.drawRawPoints(
      ui.PointMode.lines,
      frame.silhouette,
      stroke(_silhouetteWidth + 2, halo),
    );

    canvas.drawRawPoints(
      ui.PointMode.lines,
      frame.details,
      stroke(_lineWidth, color.withValues(alpha: 0.78)),
    );
    canvas.drawRawPoints(
      ui.PointMode.lines,
      frame.creases,
      stroke(_lineWidth, color.withValues(alpha: 0.78)),
    );
    canvas.drawRawPoints(
      ui.PointMode.lines,
      frame.silhouette,
      stroke(_silhouetteWidth, color.withValues(alpha: 0.96)),
    );
  }

  @override
  bool shouldRepaint(OutlinePainter old) =>
      old.frame != frame || old.color != color;
}

/// A corner of the orbit, as the mini-map draws it.
class OrbitStop {
  const OrbitStop({
    required this.azimuth,
    required this.done,
    required this.current,
  });

  final double azimuth;
  final bool done;
  final bool current;

  @override
  bool operator ==(Object other) =>
      other is OrbitStop &&
      other.azimuth == azimuth &&
      other.done == done &&
      other.current == current;

  @override
  int get hashCode => Object.hash(azimuth, done, current);
}

/// Top-down map: the car, the four corners to shoot, and the driver.
///
/// The one place the whole task is visible at once — which corner is next,
/// which way round to walk to it, and whether the phone has worked out where
/// the driver is yet.
class OrbitMap extends StatelessWidget {
  const OrbitMap({
    super.key,
    required this.stops,
    required this.azimuth,
    this.size = 76,
  });

  final List<OrbitStop> stops;

  /// Null until the driver has been placed.
  final double? azimuth;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xB814181E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: CustomPaint(
        painter: _OrbitMapPainter(stops: stops, azimuth: azimuth),
      ),
    );
  }
}

class _OrbitMapPainter extends CustomPainter {
  _OrbitMapPainter({required this.stops, required this.azimuth});

  final List<OrbitStop> stops;
  final double? azimuth;

  static const Color _done = Color(0xFF3CCF82);
  static const Color _next = Color(0xFFFFAE2B);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.40;
    // Nose up; the car's left is on the map's left, the way a plan is drawn.
    Offset at(double az) {
      final a = az * math.pi / 180;
      return c + Offset(-math.sin(a) * r, -math.cos(a) * r);
    }

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x33FFFFFF),
    );
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: c,
        width: size.width * 0.19,
        height: size.height * 0.42,
      ),
      Radius.circular(size.width * 0.05),
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xCCFFFFFF);
    canvas.drawRRect(body, line);
    // windscreen, so the nose reads as the nose
    final ws = body.outerRect;
    canvas.drawLine(
      Offset(ws.left + 2, ws.top + ws.height * 0.30),
      Offset(ws.right - 2, ws.top + ws.height * 0.30),
      line,
    );

    for (final s in stops) {
      canvas.drawCircle(
        at(s.azimuth),
        s.current ? 4.2 : 3.2,
        Paint()
          ..color = s.done
              ? _done
              : (s.current ? _next : const Color(0x59FFFFFF)),
      );
    }

    final az = azimuth;
    if (az != null) {
      final p = at(az);
      canvas.drawLine(
        p,
        c,
        Paint()
          ..strokeWidth = 1
          ..color = const Color(0x59FFFFFF),
      );
      canvas.drawCircle(p, 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        p,
        5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF14181E),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitMapPainter old) =>
      old.azimuth != azimuth || !listEquals(old.stops, stops);
}
