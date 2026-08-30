import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';

/// Pixel access to one camera frame, in the frame's own (unrotated) space.
///
/// Android streams YUV420 and iOS streams BGRA8888, so every read goes through
/// here rather than through a per-platform copy of the whole frame. Nothing in
/// L0 needs a decoded image — the checks are a luma histogram, a Laplacian and
/// a 300×300 tensor, and all three are cheaper as strided reads than as a
/// conversion of two million pixels we then throw away.
abstract class FramePixels {
  int get width;
  int get height;

  /// Luma at (x, y), 0–255.
  int luma(int x, int y);

  /// Packed 0xRRGGBB at (x, y).
  int rgb(int x, int y);

  factory FramePixels.of(CameraImage image) {
    switch (image.format.group) {
      case ImageFormatGroup.bgra8888:
        return _Bgra(image);
      case ImageFormatGroup.yuv420:
        return _Yuv420(image);
      default:
        // nv21 and jpeg never appear on the stream configs we request; treating
        // an unknown layout as luma-only still lets blur/exposure work.
        return _Yuv420(image);
    }
  }
}

class _Yuv420 implements FramePixels {
  _Yuv420(this._image)
    : _y = _image.planes[0].bytes,
      _yStride = _image.planes[0].bytesPerRow,
      _u = _image.planes.length > 1 ? _image.planes[1].bytes : null,
      _v = _image.planes.length > 2 ? _image.planes[2].bytes : null,
      _uvStride = _image.planes.length > 1 ? _image.planes[1].bytesPerRow : 0,
      _uvPixel = _image.planes.length > 1
          ? (_image.planes[1].bytesPerPixel ?? 1)
          : 1;

  final CameraImage _image;
  final Uint8List _y;
  final int _yStride;
  final Uint8List? _u;
  final Uint8List? _v;
  final int _uvStride;
  final int _uvPixel;

  @override
  int get width => _image.width;

  @override
  int get height => _image.height;

  @override
  int luma(int x, int y) {
    final i = y * _yStride + x;
    return i >= 0 && i < _y.length ? _y[i] : 0;
  }

  @override
  int rgb(int x, int y) {
    final yy = luma(x, y);
    final u = _u, v = _v;
    if (u == null || v == null) return (yy << 16) | (yy << 8) | yy;
    final uvIndex = (y >> 1) * _uvStride + (x >> 1) * _uvPixel;
    if (uvIndex < 0 || uvIndex >= u.length || uvIndex >= v.length) {
      return (yy << 16) | (yy << 8) | yy;
    }
    final uu = u[uvIndex] - 128;
    final vv = v[uvIndex] - 128;
    final r = (yy + 1.402 * vv).round().clamp(0, 255);
    final g = (yy - 0.344 * uu - 0.714 * vv).round().clamp(0, 255);
    final b = (yy + 1.772 * uu).round().clamp(0, 255);
    return (r << 16) | (g << 8) | b;
  }
}

class _Bgra implements FramePixels {
  _Bgra(this._image)
    : _bytes = _image.planes[0].bytes,
      _stride = _image.planes[0].bytesPerRow;

  final CameraImage _image;
  final Uint8List _bytes;
  final int _stride;

  @override
  int get width => _image.width;

  @override
  int get height => _image.height;

  int _offset(int x, int y) => y * _stride + x * 4;

  @override
  int luma(int x, int y) {
    final i = _offset(x, y);
    if (i < 0 || i + 2 >= _bytes.length) return 0;
    // ITU-R BT.601 in fixed point; the fractional precision is irrelevant to a
    // histogram bucket and this runs on every pixel we touch.
    return (_bytes[i + 2] * 77 + _bytes[i + 1] * 150 + _bytes[i] * 29) >> 8;
  }

  @override
  int rgb(int x, int y) {
    final i = _offset(x, y);
    if (i < 0 || i + 2 >= _bytes.length) return 0;
    return (_bytes[i + 2] << 16) | (_bytes[i + 1] << 8) | _bytes[i];
  }
}

// ---------------------------------------------------------------------------

/// The pure-arithmetic half of L0: sharpness and exposure.
///
/// Both are measured over a fixed-size grid rather than the raw frame, so the
/// numbers mean the same thing on a 720p stream and a 1080p one — otherwise
/// every threshold would have to be re-tuned per resolution, on top of the
/// per-device calibration the spec already asks for.
class FrameStats {
  const FrameStats({
    required this.blurScore,
    required this.overExposed,
    required this.underExposed,
    required this.meanLuma,
  });

  /// Variance of the Laplacian. Low means soft focus or motion blur.
  final double blurScore;

  /// Share of sampled pixels at the top of the range (blown highlights).
  final double overExposed;

  /// Share at the bottom (crushed shadows) — this is what turns the torch on.
  final double underExposed;

  final double meanLuma;

  static const _grid = 192;
  static const _overThreshold = 245;
  static const _underThreshold = 30;

  /// Measure the centre 80% of the frame: the edges are usually sky, tarmac or
  /// a neighbouring car, and letting them drag the exposure numbers around is
  /// what makes a torch flicker on and off while the driver stands still.
  static FrameStats measure(FramePixels px) {
    final left = (px.width * 0.1).round();
    final top = (px.height * 0.1).round();
    final w = (px.width * 0.8).round();
    final h = (px.height * 0.8).round();
    final stepX = math.max(1, w ~/ _grid);
    final stepY = math.max(1, h ~/ _grid);
    final cols = w ~/ stepX;
    final rows = h ~/ stepY;
    if (cols < 3 || rows < 3) {
      return const FrameStats(
        blurScore: 0,
        overExposed: 0,
        underExposed: 0,
        meanLuma: 0,
      );
    }

    final grid = Uint8List(cols * rows);
    var over = 0, under = 0, sum = 0;
    for (var r = 0; r < rows; r++) {
      final y = top + r * stepY;
      for (var c = 0; c < cols; c++) {
        final value = px.luma(left + c * stepX, y);
        grid[r * cols + c] = value;
        sum += value;
        if (value >= _overThreshold) over++;
        if (value <= _underThreshold) under++;
      }
    }

    // 4-neighbour Laplacian, variance over the interior.
    var lapSum = 0.0, lapSquares = 0.0;
    var n = 0;
    for (var r = 1; r < rows - 1; r++) {
      for (var c = 1; c < cols - 1; c++) {
        final i = r * cols + c;
        final lap =
            (4 * grid[i] -
                    grid[i - 1] -
                    grid[i + 1] -
                    grid[i - cols] -
                    grid[i + cols])
                .toDouble();
        lapSum += lap;
        lapSquares += lap * lap;
        n++;
      }
    }
    final mean = lapSum / n;
    final total = cols * rows;
    return FrameStats(
      blurScore: (lapSquares / n) - mean * mean,
      overExposed: over / total,
      underExposed: under / total,
      meanLuma: sum / total,
    );
  }
}

// ---------------------------------------------------------------------------

/// Squash the frame into a rotated `size × size` RGB tensor for the detector.
///
/// The rotation is folded into the sampling loop instead of being a separate
/// pass: the loop already reads one source pixel per destination pixel, so an
/// upright result costs exactly the same as a sideways one, and every box the
/// model returns is then in screen-upright coordinates.
Uint8List sampleRotatedRgb(FramePixels px, int rotationDegrees, int size) {
  final out = Uint8List(size * size * 3);
  final rotated = rotationDegrees == 90 || rotationDegrees == 270;
  final srcW = rotated ? px.height : px.width;
  final srcH = rotated ? px.width : px.height;

  var i = 0;
  for (var dy = 0; dy < size; dy++) {
    final uy = (dy * srcH) ~/ size;
    for (var dx = 0; dx < size; dx++) {
      final ux = (dx * srcW) ~/ size;
      // Inverse of an N-degree clockwise rotation, so (ux, uy) walks the
      // upright image while (sx, sy) walks the sensor's own layout.
      final int sx, sy;
      switch (rotationDegrees) {
        case 90:
          sx = uy;
          sy = px.height - 1 - ux;
        case 180:
          sx = px.width - 1 - ux;
          sy = px.height - 1 - uy;
        case 270:
          sx = px.width - 1 - uy;
          sy = ux;
        default:
          sx = ux;
          sy = uy;
      }
      final packed = px.rgb(
        sx.clamp(0, px.width - 1),
        sy.clamp(0, px.height - 1),
      );
      out[i++] = (packed >> 16) & 0xFF;
      out[i++] = (packed >> 8) & 0xFF;
      out[i++] = packed & 0xFF;
    }
  }
  return out;
}
