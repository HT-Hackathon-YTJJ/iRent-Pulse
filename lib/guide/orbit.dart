import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import 'outline_renderer.dart';

/// Wrap an angle in degrees into [-180, 180).
double wrapDegrees(double a) => ((a + 180) % 360 + 360) % 360 - 180;

/// Where the driver is standing round the car, in the same azimuth the
/// renderer uses (degrees from the nose towards the car's left).
///
/// Two sources, because neither is enough alone:
///
/// * **The gyroscope** is fast and smooth but only knows *how far* the phone
///   has turned, never where it started, and it drifts.
/// * **The detector** knows roughly where the driver is — the box of a car
///   seen from its corner is a very different shape from the box of the same
///   car seen side-on — but only a few times a second, noisily, and with a
///   mirror ambiguity it cannot resolve on its own.
///
/// So the detector sets the anchor ("the driver is at 38° right now") and the
/// gyroscope carries it from there. Every later detector reading pulls the
/// anchor a little towards itself, which is what stops the drift; a reading
/// that keeps disagreeing by a lot, for long enough, replaces it.
///
/// **Only the camera can place the driver.** There is no way to drag the
/// outline round or to tell the tracker where you are: a guide the driver can
/// turn by hand is a guide they can turn green by hand, and then it proves
/// nothing about where the photo was taken from.
class OrbitTracker extends ChangeNotifier {
  double _yaw = 0;
  double? _anchorAzimuth;
  double _anchorYaw = 0;

  final List<double> _pending = [];
  final List<double> _dissent = [];

  /// Readings that must agree before the first anchor is set: about 0.6 s of
  /// the detector at 5 Hz.
  static const int agreeToFix = 3;

  /// Readings within this of the tracked angle nudge it; further out they
  /// count as dissent.
  static const double nudgeWindow = 25;

  /// Share of each agreeing reading's error folded into the anchor.
  static const double nudgeGain = 0.12;

  /// Consecutive dissenting readings (that agree with each other) before the
  /// anchor is replaced outright.
  static const int dissentToRefix = 8;

  bool get hasFix => _anchorAzimuth != null;

  /// The tracked azimuth, or null before anything has anchored it.
  double? get azimuth => _anchorAzimuth == null
      ? null
      : wrapDegrees(_anchorAzimuth! + _yaw - _anchorYaw);

  /// Feed the integrated heading, in degrees, anticlockwise positive.
  void updateYaw(double yaw) {
    if (yaw == _yaw) return;
    _yaw = yaw;
    if (hasFix) notifyListeners();
  }

  /// Drop everything, e.g. when the viewfinder closes.
  void reset() {
    _anchorAzimuth = null;
    _pending.clear();
    _dissent.clear();
    notifyListeners();
  }

  void _anchor(double azimuth) {
    _anchorAzimuth = wrapDegrees(azimuth);
    _anchorYaw = _yaw;
    _dissent.clear();
    notifyListeners();
  }

  /// One detector reading: every azimuth the box is consistent with.
  ///
  /// [prior] is where the driver is expected to be — the slot they are on —
  /// and is only used until the first anchor exists.
  void observe(List<double> candidates, {required double prior}) {
    if (candidates.isEmpty) return;
    final current = azimuth;
    if (current == null) {
      final pick = _nearest(candidates, prior);
      if (_pending.isNotEmpty && _angleBetween(_pending.last, pick) > 15) {
        _pending.clear();
      }
      _pending.add(pick);
      if (_pending.length >= agreeToFix) {
        _anchor(_circularMean(_pending));
        _pending.clear();
      }
      return;
    }

    final pick = _nearest(candidates, current);
    final error = wrapDegrees(pick - current);
    if (error.abs() <= nudgeWindow) {
      _dissent.clear();
      if (error.abs() > 2) {
        _anchorAzimuth = wrapDegrees(_anchorAzimuth! + error * nudgeGain);
        notifyListeners();
      }
      return;
    }
    if (_dissent.isNotEmpty && _angleBetween(_dissent.last, pick) > 15) {
      _dissent.clear();
    }
    _dissent.add(pick);
    if (_dissent.length >= dissentToRefix) {
      _anchor(_circularMean(_dissent));
    }
  }

  static double _nearest(List<double> candidates, double to) {
    var best = candidates.first;
    for (final c in candidates) {
      if (_angleBetween(c, to) < _angleBetween(best, to)) best = c;
    }
    return best;
  }

  static double _angleBetween(double a, double b) => wrapDegrees(a - b).abs();

  static double _circularMean(List<double> angles) {
    var sx = 0.0, sy = 0.0;
    for (final a in angles) {
      sx += math.cos(a * math.pi / 180);
      sy += math.sin(a * math.pi / 180);
    }
    return math.atan2(sy, sx) * 180 / math.pi;
  }
}

/// Reads the azimuth off a detector box.
///
/// The box's width in the frame says how far back the driver is; its shape,
/// compared against the model from that distance ([PoseTable]), says the
/// angle — up to a mirror: a car seen from 40° is the same shape from −40°,
/// 140° and −140°. The plate, when the reader found one, halves that — at
/// 左前 and 右後 the plate end of the car is on the left of the box, at 右前 and
/// 左後 on the right — and the [OrbitTracker] settles the rest from where the
/// driver was a moment ago.
class BoxPoseEstimator {
  BoxPoseEstimator(this.table);

  final PoseTable table;

  /// Every azimuth whose box, [widthFraction] of the frame wide, has
  /// [aspect]; optionally filtered by which side of the box the plate was on
  /// ([plateSide] < 0: left of centre).
  List<double> candidates(
    double aspect, {
    required double widthFraction,
    double? plateSide,
  }) {
    final n = table.azimuths;
    final step = table.step;
    final predicted = [
      for (var i = 0; i < n; i++) table.aspectFor(i, widthFraction),
    ];
    final out = <double>[];
    for (var i = 0; i < n; i++) {
      final a = predicted[i], b = predicted[(i + 1) % n];
      final lo = math.min(a, b), hi = math.max(a, b);
      if (aspect < lo || aspect > hi || hi == lo) continue;
      final t = (aspect - a) / (b - a);
      out.add(wrapDegrees(-180 + (i + t) * step));
    }
    if (out.isEmpty) {
      // Wider than any side view or narrower than any end-on view: take every
      // azimuth that comes within a hair of the closest the model can do.
      //
      // *Every* one, not the first found. A box narrower than the model's
      // head-on view is as close to the nose as to the tail, and handing back
      // only the first match — the tail, because the table starts at −180 —
      // is how a driver standing at the front bumper was re-anchored behind
      // the car on the phone.
      var nearest = double.infinity;
      for (final a in predicted) {
        nearest = math.min(nearest, (a - aspect).abs());
      }
      for (var i = 0; i < n; i++) {
        if ((predicted[i] - aspect).abs() <= nearest + 0.03) {
          out.add(wrapDegrees(-180 + i * step));
        }
      }
    }
    if (plateSide == null || plateSide.abs() < 0.08) return _dedupe(out);
    // plate left of centre  <=>  sin(2·az) > 0  (左前 / 右後)
    final wantPositive = plateSide < 0;
    final kept = out.where((az) {
      final s = math.sin(2 * az * math.pi / 180);
      return wantPositive ? s > 0 : s < 0;
    }).toList();
    return _dedupe(kept.isEmpty ? out : kept);
  }

  static List<double> _dedupe(List<double> xs) {
    final out = <double>[];
    for (final x in xs) {
      if (out.every((y) => wrapDegrees(x - y).abs() > 3)) out.add(x);
    }
    return out;
  }
}

/// A detector box is only worth reading an angle off if the whole car is in
/// it — a box cut off by the frame edge has the frame's aspect, not the car's.
bool boxIsWhole(Rect box) =>
    box.left > 0.015 &&
    box.top > 0.015 &&
    box.right < 0.985 &&
    box.bottom < 0.985;
