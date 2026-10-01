import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'car_model.dart';

/// Where the virtual camera stands: on a circle round the car, at eye height,
/// looking at the middle of the car.
///
/// [azimuth] is in degrees, measured from the car's nose towards its **left**
/// side — anticlockwise seen from above. So 左前 is +40, 右前 −40, 右後 −140 and
/// 左後 +140. The same number is what the gyroscope integrates: a driver
/// walking anticlockwise round the car turns the phone anticlockwise with
/// them.
class OrbitView {
  const OrbitView({
    required this.azimuth,
    required this.distance,
    required this.viewport,
    this.fovY = defaultFovY,
    this.eyeHeight = 1.40,
    this.lookHeight = 0.62,
    this.shiftX = 0,
  });

  /// Vertical field of view of a portrait 4:3 frame on a phone's main camera
  /// at 1×. The camera plugin does not report it; 66° is a 24–26 mm-equivalent
  /// lens, which is what the flagship main cameras are. Being a few degrees
  /// out only changes how strong the perspective looks, not the size — the
  /// distance is fitted to the frame separately.
  static const double defaultFovY = 66;

  final double azimuth;
  final double distance;
  final Size viewport;
  final double fovY;
  final double eyeHeight;
  final double lookHeight;

  /// Horizontal shift of the image centre, in viewport pixels. A car seen
  /// from its corner is not centred on its own middle — the near end is
  /// bigger — so the guide shifts the picture to centre the car's box at the
  /// corner being shot, and keeps that shift while the driver walks.
  final double shiftX;

  OrbitView copyWith({
    double? azimuth,
    double? distance,
    Size? viewport,
    double? fovY,
  }) => OrbitView(
    azimuth: azimuth ?? this.azimuth,
    distance: distance ?? this.distance,
    viewport: viewport ?? this.viewport,
    fovY: fovY ?? this.fovY,
    eyeHeight: eyeHeight,
    lookHeight: lookHeight,
  );
}

/// One rendered outline, in the viewport's own pixels.
class OutlineFrame {
  const OutlineFrame({
    required this.fill,
    required this.silhouette,
    required this.creases,
    required this.details,
    required this.bounds,
  });

  /// Triangle positions (x, y, x, y, x, y …) of every face turned towards the
  /// camera, for `Canvas.drawVertices`.
  final Float32List fill;

  /// Line segments (x0, y0, x1, y1 …) for `Canvas.drawRawPoints`.
  final Float32List silhouette;
  final Float32List creases;
  final Float32List details;

  /// Where the whole car lands, hidden parts included — the box L0's detector
  /// is compared against.
  final Rect bounds;
}

/// Draws a [CarModel] as an outline, in software, on the CPU.
///
/// Flutter's 3D stack (flutter_scene / Flutter GPU) still needs the master
/// channel, and the WebView viewers cannot draw an outline at all — so this is
/// the few hundred lines an outline actually needs:
///
/// 1. project every vertex through a pinhole camera
/// 2. mark each face as facing the camera or not
/// 3. rasterise the facing faces into a small inverse-depth buffer
/// 4. candidate lines: silhouettes (an edge between a facing and a hidden
///    face), creases, and the detail lines
/// 5. walk each candidate in ~1 buffer-pixel steps and keep the runs that are
///    not behind the buffer
///
/// Visibility is tested against the *farthest* depth in each 3×3 buffer
/// neighbourhood. A silhouette sits exactly on the boundary of the surface it
/// belongs to; testing it against its own pixel would hide it half the time
/// behind the very surface it outlines.
class OutlineRenderer {
  OutlineRenderer(this.model)
    : _sx = Float32List(model.vertexCount),
      _sy = Float32List(model.vertexCount),
      _sz = Float32List(model.vertexCount),
      _facing = Uint8List(model.faceCount);

  final CarModel model;

  final Float32List _sx;
  final Float32List _sy;
  final Float32List _sz;
  final Uint8List _facing;
  Float32List _depth = Float32List(0);
  Float32List _far = Float32List(0);
  int _bw = 0;
  int _bh = 0;
  double _scale = 0.5;

  // camera, refreshed per frame
  double _ex = 0, _ey = 0, _ez = 0;
  double _rx = 0, _ry = 0, _rz = 0;
  double _ux = 0, _uy = 0, _uz = 0;
  double _fx = 0, _fy = 0, _fz = 0;
  double _focal = 1, _cx = 0, _cy = 0;

  static const double _near = 0.1;

  void _setCamera(OrbitView view) {
    final a = view.azimuth * math.pi / 180;
    _ex = view.distance * math.cos(a);
    _ey = view.distance * math.sin(a);
    _ez = view.eyeHeight;
    var fx = -_ex, fy = -_ey, fz = view.lookHeight - _ez;
    final fl = math.sqrt(fx * fx + fy * fy + fz * fz);
    fx /= fl;
    fy /= fl;
    fz /= fl;
    // right = forward × up(0, 0, 1)
    var rx = fy, ry = -fx;
    const rz = 0.0;
    final rl = math.sqrt(rx * rx + ry * ry);
    rx /= rl;
    ry /= rl;
    // camera up = right × forward
    _ux = ry * fz - rz * fy;
    _uy = rz * fx - rx * fz;
    _uz = rx * fy - ry * fx;
    _rx = rx;
    _ry = ry;
    _rz = rz;
    _fx = fx;
    _fy = fy;
    _fz = fz;
    _focal = view.viewport.height / 2 / math.tan(view.fovY * math.pi / 360);
    _cx = view.viewport.width / 2 + view.shiftX;
    _cy = view.viewport.height / 2;
  }

  void _projectVertices() {
    final v = model.vertices;
    for (var i = 0, n = model.vertexCount; i < n; i++) {
      final dx = v[i * 3] - _ex,
          dy = v[i * 3 + 1] - _ey,
          dz = v[i * 3 + 2] - _ez;
      final xc = dx * _rx + dy * _ry + dz * _rz;
      final yc = dx * _ux + dy * _uy + dz * _uz;
      final zc = dx * _fx + dy * _fy + dz * _fz;
      _sz[i] = zc;
      final inv = zc > _near ? 1 / zc : 1 / _near;
      _sx[i] = _cx + _focal * xc * inv;
      _sy[i] = _cy - _focal * yc * inv;
    }
  }

  /// Where the car lands in [view], without drawing anything.
  ///
  /// This is the box the detector should report for the car, so it is taken
  /// over the model's hull ([CarModel.hull]) — which leaves out the roof
  /// antenna the detector never boxes — and projects only those vertices.
  Rect bounds(OrbitView view) {
    _setCamera(view);
    final v = model.vertices;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final i in model.hull) {
      final dx = v[i * 3] - _ex, dy = v[i * 3 + 1] - _ey;
      final dz = v[i * 3 + 2] - _ez;
      final zc = math.max(_near, dx * _fx + dy * _fy + dz * _fz);
      final x = _cx + _focal * (dx * _rx + dy * _ry + dz * _rz) / zc;
      final y = _cy - _focal * (dx * _ux + dy * _uy + dz * _uz) / zc;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// [bounds] for the camera [render] just projected.
  Rect _bounds() {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final i in model.hull) {
      final x = _sx[i], y = _sy[i];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// The distance at which the car, seen from [azimuth], is [widthFraction]
  /// of the viewport wide.
  double fitDistance(OrbitView view, {double widthFraction = 0.82}) {
    var lo = 2.0, hi = 20.0;
    final want = view.viewport.width * widthFraction;
    for (var i = 0; i < 28; i++) {
      final mid = (lo + hi) / 2;
      final w = bounds(view.copyWith(distance: mid)).width;
      if (w > want) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  OutlineFrame render(OrbitView view, {double bufferScale = 0.5}) {
    _setCamera(view);
    _projectVertices();
    _scale = bufferScale;
    _classifyFaces();
    _rasterise(view.viewport);

    final fill = <double>[];
    final f = model.faces;
    for (var i = 0, n = model.faceCount; i < n; i++) {
      if (_facing[i] == 0) continue;
      for (var k = 0; k < 3; k++) {
        final v = f[i * 3 + k];
        fill
          ..add(_sx[v])
          ..add(_sy[v]);
      }
    }

    final silhouette = <double>[];
    final creases = <double>[];
    final e = model.edges;
    for (var i = 0, n = model.edgeCount; i < n; i++) {
      final f1 = e[i * 4 + 2], f2 = e[i * 4 + 3];
      final a = _facing[f1] == 1;
      final b = f2 >= 0 && _facing[f2] == 1;
      final isSilhouette = f2 >= 0 && a != b;
      if (isSilhouette) {
        _emitEdge(e[i * 4], e[i * 4 + 1], silhouette, view.viewport);
      } else if (model.creases[i] == 1 && (a || b)) {
        _emitEdge(e[i * 4], e[i * 4 + 1], creases, view.viewport);
      }
    }

    final details = <double>[];
    for (final line in model.lines) {
      _emitDetail(line, details, view.viewport);
    }

    return OutlineFrame(
      fill: Float32List.fromList(fill),
      silhouette: Float32List.fromList(silhouette),
      creases: Float32List.fromList(creases),
      details: Float32List.fromList(details),
      bounds: _bounds(),
    );
  }

  void _classifyFaces() {
    final n = model.faceNormals, c = model.faceCentres;
    for (var i = 0, m = model.faceCount; i < m; i++) {
      final dot =
          n[i * 3] * (_ex - c[i * 3]) +
          n[i * 3 + 1] * (_ey - c[i * 3 + 1]) +
          n[i * 3 + 2] * (_ez - c[i * 3 + 2]);
      _facing[i] = dot > 0 ? 1 : 0;
    }
  }

  void _rasterise(Size viewport) {
    _bw = math.max(1, (viewport.width * _scale).ceil());
    _bh = math.max(1, (viewport.height * _scale).ceil());
    final size = _bw * _bh;
    if (_depth.length != size) {
      _depth = Float32List(size);
      _far = Float32List(size);
    } else {
      _depth.fillRange(0, size, 0);
    }
    final f = model.faces;
    final s = _scale;
    for (var i = 0, n = model.faceCount; i < n; i++) {
      if (_facing[i] == 0) continue;
      final a = f[i * 3], b = f[i * 3 + 1], c = f[i * 3 + 2];
      if (_sz[a] <= _near || _sz[b] <= _near || _sz[c] <= _near) continue;
      _triangle(
        _sx[a] * s,
        _sy[a] * s,
        1 / _sz[a],
        _sx[b] * s,
        _sy[b] * s,
        1 / _sz[b],
        _sx[c] * s,
        _sy[c] * s,
        1 / _sz[c],
      );
    }
    // farthest depth (smallest inverse depth) in each 3×3 neighbourhood
    final w = _bw, h = _bh;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var m = _depth[y * w + x];
        for (var dy = -1; dy <= 1 && m > 0; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) {
            m = 0;
            break;
          }
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) {
              m = 0;
              break;
            }
            final d = _depth[yy * w + xx];
            if (d < m) m = d;
          }
        }
        _far[y * w + x] = m;
      }
    }
  }

  void _triangle(
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    double x2,
    double y2,
    double z2,
  ) {
    final area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
    if (area.abs() < 1e-9) return;
    final minX = math.max(0, math.min(x0, math.min(x1, x2)).floor());
    final maxX = math.min(_bw - 1, math.max(x0, math.max(x1, x2)).ceil());
    final minY = math.max(0, math.min(y0, math.min(y1, y2)).floor());
    final maxY = math.min(_bh - 1, math.max(y0, math.max(y1, y2)).ceil());
    if (minX > maxX || minY > maxY) return;
    final inv = 1 / area;
    const eps = -1e-4;
    for (var py = minY; py <= maxY; py++) {
      final y = py + 0.5;
      for (var px = minX; px <= maxX; px++) {
        final x = px + 0.5;
        final w0 = ((x1 - x) * (y2 - y) - (x2 - x) * (y1 - y)) * inv;
        if (w0 < eps) continue;
        final w1 = ((x2 - x) * (y0 - y) - (x0 - x) * (y2 - y)) * inv;
        if (w1 < eps) continue;
        final w2 = 1 - w0 - w1;
        if (w2 < eps) continue;
        final iz = w0 * z0 + w1 * z1 + w2 * z2;
        final k = py * _bw + px;
        if (iz > _depth[k]) _depth[k] = iz;
      }
    }
  }

  void _emitEdge(int a, int b, List<double> out, Size viewport) {
    if (_sz[a] <= _near || _sz[b] <= _near) return;
    _emitSegment(_sx[a], _sy[a], _sz[a], _sx[b], _sy[b], _sz[b], out, viewport);
  }

  void _emitDetail(DetailLine line, List<double> out, Size viewport) {
    final p = line.points, n = line.normals;
    double? px, py, pz;
    for (var i = 0; i < line.length; i++) {
      final wx = p[i * 3], wy = p[i * 3 + 1], wz = p[i * 3 + 2];
      final dx = wx - _ex, dy = wy - _ey, dz = wz - _ez;
      final zc = dx * _fx + dy * _fy + dz * _fz;
      final x = _cx + _focal * (dx * _rx + dy * _ry + dz * _rz) / zc;
      final y = _cy - _focal * (dx * _ux + dy * _uy + dz * _uz) / zc;
      // a line on a surface facing away from the camera is on the far side
      final facing =
          n[i * 3] * (_ex - wx) +
              n[i * 3 + 1] * (_ey - wy) +
              n[i * 3 + 2] * (_ez - wz) >
          0;
      if (px != null && facing && zc > _near) {
        _emitSegment(px, py!, pz!, x, y, zc, out, viewport);
      }
      if (facing && zc > _near) {
        px = x;
        py = y;
        pz = zc;
      } else {
        px = null;
      }
    }
  }

  /// Walk a projected segment and append the runs that are not hidden.
  void _emitSegment(
    double u0,
    double v0,
    double z0,
    double u1,
    double v1,
    double z1,
    List<double> out,
    Size viewport,
  ) {
    final len =
        math.sqrt((u1 - u0) * (u1 - u0) + (v1 - v0) * (v1 - v0)) * _scale;
    final n = math.max(2, len.ceil() + 1);
    final iz0 = 1 / z0, iz1 = 1 / z1;
    var runStart = -1;
    double su = 0, sv = 0, lu = 0, lv = 0;
    for (var i = 0; i < n; i++) {
      final t = i / (n - 1);
      final u = u0 + (u1 - u0) * t;
      final v = v0 + (v1 - v0) * t;
      final iz = iz0 + (iz1 - iz0) * t;
      var visible =
          u >= 0 && v >= 0 && u < viewport.width && v < viewport.height;
      if (visible) {
        final bx = math.min(_bw - 1, (u * _scale).floor());
        final by = math.min(_bh - 1, (v * _scale).floor());
        final far = _far[by * _bw + bx];
        if (far > 0) {
          final zs = 1 / iz;
          final zb = 1 / far;
          visible = zs <= zb + 0.03 + 0.006 * zs;
        }
      }
      if (visible) {
        if (runStart < 0) {
          runStart = i;
          su = u;
          sv = v;
        }
        lu = u;
        lv = v;
      }
      if ((!visible || i == n - 1) && runStart >= 0) {
        if (lu != su || lv != sv) out.addAll([su, sv, lu, lv]);
        runStart = -1;
      }
    }
  }

  /// The car's box — how wide in the frame, and what shape — for every
  /// [step] degrees of azimuth at each of [PoseTable.distances]. What the
  /// detector's box is matched against to read the angle off it.
  PoseTable poseTable(OrbitView view, {double step = 2}) {
    final n = (360 / step).round();
    final d = PoseTable.distances;
    final width = Float64List(n * d.length);
    final aspect = Float64List(n * d.length);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < d.length; j++) {
        final b = bounds(
          view.copyWith(azimuth: -180 + i * step, distance: d[j]),
        );
        width[i * d.length + j] = b.width / view.viewport.width;
        aspect[i * d.length + j] = b.width / b.height;
      }
    }
    return PoseTable(step: step, width: width, aspect: aspect);
  }
}

/// How the car's box looks from every azimuth at a range of distances.
///
/// The shape of the box alone is not enough: stand further back and the near
/// end of the car stops looming, the roof drops out of view, and the same
/// corner reads as a longer, flatter box — at 40° it goes from 1.86 at 4.7 m
/// to 2.17 at 11 m, which is the difference between 40° and 55°. The box's
/// *width in the frame* says how far back the driver is, so the shape is only
/// compared against what the model looks like from that distance.
class PoseTable {
  PoseTable({required this.step, required this.width, required this.aspect});

  /// Metres. Denser near the car, where a step changes the view most.
  static const List<double> distances = [
    2.5,
    3.0,
    3.5,
    4.2,
    5.0,
    6.0,
    7.2,
    8.6,
    10.5,
    13.0,
    16.0,
    20.0,
  ];

  final double step;

  /// Box width as a fraction of the viewport, [azimuth][distance].
  final Float64List width;

  /// Box width ÷ height, [azimuth][distance].
  final Float64List aspect;

  int get azimuths => width.length ~/ distances.length;

  /// The box aspect the model predicts at azimuth index [i] for a box
  /// [widthFraction] of the frame wide.
  double aspectFor(int i, double widthFraction) {
    final n = distances.length;
    final base = i * n;
    // Width falls as distance grows; clamp outside the table.
    if (widthFraction >= width[base]) return aspect[base];
    if (widthFraction <= width[base + n - 1]) return aspect[base + n - 1];
    for (var j = 0; j < n - 1; j++) {
      final w0 = width[base + j], w1 = width[base + j + 1];
      if (widthFraction <= w0 && widthFraction >= w1) {
        final t = (w0 - widthFraction) / (w0 - w1);
        return aspect[base + j] + (aspect[base + j + 1] - aspect[base + j]) * t;
      }
    }
    return aspect[base + n - 1];
  }
}
