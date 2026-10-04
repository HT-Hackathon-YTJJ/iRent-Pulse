import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import 'outline_renderer.dart';

/// Wrap an angle in degrees into [-180, 180).
double wrapDegrees(double a) => ((a + 180) % 360 + 360) % 360 - 180;

/// One azimuth a detector box is consistent with.
@immutable
class OrbitCandidate {
  const OrbitCandidate(
    this.azimuth, {
    this.sigma = 6,
    this.weight = 1,
    this.centre = 0,
  });

  final double azimuth;

  /// How tightly the box pins the angle down, in degrees. At the corners the
  /// box changes shape quickly as the driver moves and this is a few degrees;
  /// within ten or so of side-on it hardly changes at all and this is wide.
  final double sigma;

  /// Plausibility against the reading's other candidates. Equal unless the
  /// plate was read, which usually leaves one standing.
  final double weight;

  /// Degrees from the car's middle round to the box's centre, seen from
  /// [azimuth] — see [PoseTable.centre].
  final double centre;

  @override
  String toString() =>
      '${azimuth.round()}°±${sigma.round()}'
      '${weight == 1 ? "" : "×${weight.toStringAsFixed(2)}"}';
}

/// Where the driver is standing round the car, in the same azimuth the
/// renderer uses (degrees from the nose towards the car's left).
///
/// The azimuth is split into two parts that are measured in different ways:
///
///     azimuth = bearing + offset
///
/// * **bearing** is the direction from the phone to the car's middle, in the
///   gyroscope's frame: the phone's heading plus how far off the centre of
///   the frame the car's box is. Panning the phone to put the car in the
///   outline turns the heading one way and slides the box the other, so the
///   bearing — and the outline — stay where they are. It only changes when
///   the driver actually walks round the car. (The first version used the
///   heading alone, and every pan turned the car on screen with it.)
/// * **offset** is where the gyroscope's zero happens to point, relative to
///   the car's nose. It is a constant (up to the gyroscope's slow drift), so
///   every detector reading is a vote for it, and they pile up: the box's
///   shape is noisy and comes with mirror images, but the right offset gets
///   a vote from every reading while each wrong one only gets the readings
///   that happen to look the same — and once the driver moves, the mirror
///   images of a reading stop landing in the same place at all.
///
/// The tracker follows the strongest pile near where it already is, and
/// leaves it only for one that is clearly and persistently stronger. That
/// hysteresis is what keeps the outline from flipping between mirror images
/// on a noisy box.
///
/// **Only the camera can place the driver.** There is no way to drag the
/// outline round or to tell the tracker where you are: a guide the driver can
/// turn by hand is a guide they can turn green by hand, and then it proves
/// nothing about where the photo was taken from.
class OrbitTracker extends ChangeNotifier {
  double _yaw = 0;
  double? _bearing;

  /// How fast the bearing has been moving, degrees a second, from the
  /// readings themselves: a driver walking round with the car in view.
  double _turning = 0;
  double? _offset;
  double? _size;
  double _seenAt = double.negativeInfinity;

  /// Seconds spent walking since the last reading was taken, and when the
  /// heading last came in.
  double _walked = 0;
  double? _yawAt;

  final List<_Reading> _readings = [];
  final List<(double, double, double)> _odd = [];
  int _contested = 0;
  final Float64List _score = Float64List(360);

  /// Seconds over which a reading's vote fades to 1/e. Long enough to
  /// average the box's noise, short enough to follow the gyroscope's drift.
  static const double memory = 6;

  /// Readings (within [_recent] seconds) before the first fix — about half a
  /// second of the detector.
  static const int agreeToFix = 3;

  /// While the readings cannot tell two places apart, wait this many for the
  /// plate to be read before falling back on the slot being shot.
  static const int patience = 7;

  /// How many readings' worth of votes one place must lead another by for
  /// the readings to have told them apart. A reading with the plate in it
  /// puts nearly all of its vote on one place; one without splits it evenly
  /// over its mirror images, which adds the same to each and so cancels out
  /// of the difference.
  static const double decisive = 0.6;

  /// A rival place has to lead the one being followed by this many readings,
  /// for [switchAfter] readings in a row, before the tracker jumps to it.
  static const double switchMargin = 1.0;
  static const int switchAfter = 5;

  /// How far the car's bearing may move between two readings before the box
  /// is taken to be something else: a fixed allowance for the box's jitter,
  /// a little more per second for a driver shuffling where they stand, and
  /// what walking round the car can do for every second they walked.
  ///
  /// Walking, not the time between readings, is what opens the gate. The
  /// gaps are mostly a driver standing still with the car brushing the edge
  /// of the frame, and a gate that opened with time let the car in the next
  /// bay through at the end of every one of them.
  static const double gateDegrees = 9;
  static const double gateDrift = 4;
  static const double gateRate = 22;

  /// How much the box's width may change between two readings, as a log
  /// ratio, on the same terms: jitter, shuffling, and walking towards the
  /// car. The car in the next bay is usually much smaller or larger.
  static const double gateSize = 0.12;
  static const double gateSizeDrift = 0.05;
  static const double gateSizeRate = 0.35;

  /// Consecutive out-of-gate readings, agreeing with each other, that move
  /// the bearing anyway: the driver walked while the phone looked away. More
  /// of them if the driver has not walked, because then the likelier story is
  /// that the detector has settled on the car next door for a moment.
  static const int rebaseAfter = 3;
  static const int rebaseStill = 6;

  /// Seconds without a reading before the car counts as out of sight.
  static const double outOfSight = 0.5;

  /// Share of each reading's bearing taken into the estimate, and of what it
  /// says about how fast the bearing is moving.
  static const double bearingGain = 0.6;
  static const double turningGain = 0.25;

  /// Walking briskly round a car five metres away is about 12°/s.
  static const double maxTurning = 25;

  static const double _recent = 2.5;

  bool get hasFix => _offset != null && _bearing != null;

  /// The tracked azimuth, or null before anything has placed the driver.
  double? get azimuth => hasFix ? wrapDegrees(_bearing! + _offset!) : null;

  /// Feed the integrated heading, in degrees, anticlockwise positive, [at]
  /// seconds on the same clock as [observe].
  ///
  /// The heading only carries the bearing while the driver is [walking] and
  /// the car is out of sight. Standing still and panning the phone does not
  /// move them round the car, so the outline stays put; walking with the
  /// phone pointing elsewhere does, and the heading is the only thing that
  /// sees it. While the car is in view its box says where it is directly —
  /// and the footstep detector also fires on an arm swinging the phone about,
  /// which must not turn the outline — so between readings the bearing just
  /// carries on at the rate the readings have been moving it.
  void updateYaw(double yaw, {bool walking = false, double? at}) {
    final turned = yaw - _yaw;
    _yaw = yaw;
    final last = _yawAt;
    if (walking && at != null && last != null) {
      _walked += (at - last).clamp(0.0, 0.25);
    }
    _yawAt = at;
    final b = _bearing;
    if (b == null) return;
    if (at != null && last != null && at - _seenAt < outOfSight) {
      if (_turning == 0) return;
      _bearing = wrapDegrees(b + _turning * (at - last).clamp(0.0, 0.1));
    } else if (walking && turned != 0) {
      _bearing = wrapDegrees(b + turned);
    } else {
      return;
    }
    if (hasFix) notifyListeners();
  }

  /// Drop everything, e.g. when the viewfinder closes.
  void reset() {
    _bearing = null;
    _turning = 0;
    _offset = null;
    _size = null;
    _walked = 0;
    _readings.clear();
    _odd.clear();
    _contested = 0;
    _seenAt = double.negativeInfinity;
    notifyListeners();
  }

  /// One detector reading: every azimuth the box is consistent with, the
  /// bearing of the box's centre in the gyroscope's frame, and the box's
  /// width as a fraction of the frame.
  ///
  /// [at] is in seconds on any steady clock. [prior] is where the driver is
  /// expected to be — the slot they are on — and only breaks ties the
  /// readings themselves cannot.
  void observe(
    List<OrbitCandidate> candidates, {
    required double bearing,
    required double size,
    required double at,
    required double prior,
  }) {
    if (candidates.isEmpty) return;

    // The box's centre is not the car's middle: from a corner the near end
    // looms and the box leans towards it. Which way depends on where the
    // driver is, so ask the candidate nearest where they are thought to be.
    final near = _nearest(candidates, azimuth ?? prior);
    final middle = wrapDegrees(bearing - near.centre);

    final b = _bearing, last = _size;
    if (b == null || last == null) {
      _bearing = middle;
    } else {
      final gap = (at - _seenAt).clamp(0.0, 4.0);
      final walked = math.min(_walked, 4.0);
      final moved = wrapDegrees(middle - b);
      final grew = math.log(size / last).abs();
      if (moved.abs() > gateDegrees + gateDrift * gap + gateRate * walked ||
          grew > gateSize + gateSizeDrift * gap + gateSizeRate * walked) {
        // Not where the car was a moment ago, or not its size. Usually the
        // car in the next bay; sometimes the driver walked while the phone
        // looked away. Only a box that keeps saying so is believed.
        if (_odd.isNotEmpty) {
          final (m, s, t) = _odd.last;
          if (wrapDegrees(m - middle).abs() > 8 ||
              math.log(size / s).abs() > 0.15 ||
              at - t > 0.8) {
            _odd.clear();
          }
        }
        _odd.add((middle, size, at));
        if (_odd.length < (walked > 0.5 ? rebaseAfter : rebaseStill)) return;
        _bearing = middle;
        _turning = 0;
      } else if (gap > outOfSight) {
        _bearing = gap > 1 ? middle : wrapDegrees(b + moved * bearingGain);
        _turning = 0;
      } else {
        _bearing = wrapDegrees(b + moved * bearingGain);
        _turning = (_turning + turningGain * moved / math.max(gap, 0.1)).clamp(
          -maxTurning,
          maxTurning,
        );
      }
    }
    _odd.clear();
    _size = size;
    _seenAt = at;
    _walked = 0;

    var total = 0.0;
    for (final c in candidates) {
      total += c.weight;
    }
    _readings.add(
      _Reading(at, [
        for (final c in candidates)
          _Vote(
            // each candidate's own idea of where the middle is
            wrapDegrees(c.azimuth - wrapDegrees(bearing - c.centre)),
            c.sigma,
            c.weight / total,
          ),
      ]),
    );
    _readings.removeWhere((r) => at - r.at > memory * 2);
    _decide(at, prior);
    notifyListeners();
  }

  void _decide(double now, double prior) {
    _tally(now);
    final peaks = _peaks();
    if (peaks.isEmpty) return;
    final best = peaks.first;

    final offset = _offset;
    if (offset == null) {
      final recent = _readings.where((r) => now - r.at <= _recent).length;
      if (recent < agreeToFix) return;
      final mass = {for (final p in peaks) p.$1: _mass(p.$1, now)};
      final most = mass.values.reduce(math.max);
      final rivals = [
        for (final p in peaks)
          if (most - mass[p.$1]! < decisive) p,
      ];
      if (rivals.length > 1 && recent < patience) return;
      // Among the places the readings cannot tell apart, the corner the slot
      // is asking for: that is where a driver following the strip is.
      final towards = wrapDegrees(prior - _bearing!);
      var pick = rivals.first;
      for (final p in rivals) {
        if (_between(p.$1, towards) < _between(pick.$1, towards)) pick = p;
      }
      if (_support(pick.$1, now) < 0.6) return;
      _offset = _refine(pick.$1, now);
      _contested = 0;
      return;
    }

    // Follow the pile we are on as the votes come in.
    _offset = _refine(_climb(offset), now);
    final here = _mass(_offset!, now);
    var rival = best.$1, lead = 0.0;
    for (final p in peaks) {
      if (_between(p.$1, _offset!) <= 20) continue;
      final m = _mass(p.$1, now) - here;
      if (m > lead) (rival, lead) = (p.$1, m);
    }
    if (lead > switchMargin) {
      if (++_contested >= switchAfter) {
        _offset = _refine(rival, now);
        _contested = 0;
      }
    } else {
      _contested = 0;
    }
  }

  /// Sum every reading's votes into one-degree bins of offset.
  void _tally(double now) {
    _score.fillRange(0, 360, 0);
    for (final r in _readings) {
      final fade = math.exp(-(now - r.at) / memory);
      for (final v in r.votes) {
        final height = fade * v.weight * math.min(1.5, 5 / v.sigma);
        final reach = (v.sigma * 3).ceil();
        final centre = v.offset.round();
        for (var d = -reach; d <= reach; d++) {
          final x = (centre + d) - v.offset;
          _score[_bin((centre + d).toDouble())] +=
              height * math.exp(-x * x / (2 * v.sigma * v.sigma));
        }
      }
    }
  }

  /// Local maxima of the tally, strongest first, as (offset, score).
  List<(double, double)> _peaks() {
    var top = 0.0;
    for (final s in _score) {
      top = math.max(top, s);
    }
    if (top <= 0) return const [];
    final out = <(double, double)>[];
    for (var i = 0; i < 360; i++) {
      final s = _score[i];
      if (s < top * 0.05) continue;
      if (s >= _score[(i + 359) % 360] && s > _score[(i + 1) % 360]) {
        out.add(((i - 180).toDouble(), s));
      }
    }
    out.sort((a, b) => b.$2.compareTo(a.$2));
    return out;
  }

  /// Uphill from [offset] to the top of the pile it is on.
  double _climb(double offset) {
    var i = _bin(offset);
    for (var n = 0; n < 180; n++) {
      final l = (i + 359) % 360, r = (i + 1) % 360;
      final next = _score[l] > _score[r] ? l : r;
      if (_score[next] <= _score[i]) break;
      i = next;
    }
    return (i - 180).toDouble();
  }

  /// The votes near [offset], averaged by how sure each one was.
  double _refine(double offset, double now) {
    var sx = 0.0, sy = 0.0;
    for (final r in _readings) {
      final fade = math.exp(-(now - r.at) / memory);
      for (final v in r.votes) {
        if (_between(v.offset, offset) > math.max(8, v.sigma * 1.5)) continue;
        final w = fade * v.weight / (v.sigma * v.sigma);
        sx += w * math.cos(v.offset * math.pi / 180);
        sy += w * math.sin(v.offset * math.pi / 180);
      }
    }
    if (sx == 0 && sy == 0) return offset;
    return math.atan2(sy, sx) * 180 / math.pi;
  }

  /// Readings' worth of votes near [offset], faded by age. A vague vote
  /// counts for less: side-on, the box says little about where exactly.
  double _mass(double offset, double now) {
    var total = 0.0;
    for (final r in _readings) {
      final fade = math.exp(-(now - r.at) / memory);
      for (final v in r.votes) {
        if (_between(v.offset, offset) > math.max(10, v.sigma * 1.5)) continue;
        total += fade * v.weight * math.min(1, 6 / v.sigma);
      }
    }
    return total;
  }

  /// Share of the recent readings with a vote near [offset].
  double _support(double offset, double now) {
    var n = 0, agree = 0;
    for (final r in _readings) {
      if (now - r.at > _recent) continue;
      n++;
      if (r.votes.any(
        (v) => _between(v.offset, offset) <= math.max(6, v.sigma * 2),
      )) {
        agree++;
      }
    }
    return n == 0 ? 0 : agree / n;
  }

  static int _bin(double offset) => (offset.round() + 180) % 360;

  static OrbitCandidate _nearest(List<OrbitCandidate> candidates, double to) {
    var best = candidates.first;
    for (final c in candidates) {
      if (_between(c.azimuth, to) < _between(best.azimuth, to)) best = c;
    }
    return best;
  }

  static double _between(double a, double b) => wrapDegrees(a - b).abs();
}

class _Reading {
  _Reading(this.at, this.votes);
  final double at;
  final List<_Vote> votes;
}

class _Vote {
  const _Vote(this.offset, this.sigma, this.weight);
  final double offset;
  final double sigma;
  final double weight;
}

/// Reads the azimuth off a detector box.
///
/// The box's width in the frame says how far back the driver is; its shape,
/// compared against the model from that distance ([PoseTable]), says the
/// angle — up to a mirror: a car seen from 40° is the same shape from −40°,
/// 140° and −140°. The plate, when the reader found one, usually settles it:
/// across the box it says which side the plate end is on (left at 左前 and
/// 右後), and up the box which end it is — the front plate sits on the bumper
/// about 30% of the way up the box, the rear one on the tailgate about half
/// way.
class BoxPoseEstimator {
  BoxPoseEstimator(this.table);

  final PoseTable table;

  /// Relative noise on a detector box's aspect: ~1.5% on each edge, plus
  /// the model never being quite the car.
  static const double aspectNoise = 0.035;

  /// How far, as a fraction of the box, the read plate may sit from where the
  /// model puts it and still count as the same plate.
  static const double plateAcross = 0.12;
  static const double plateUp = 0.08;

  /// Every azimuth whose box, [widthFraction] of the frame wide, has
  /// [aspect]; optionally filtered by which side of the box the plate was on
  /// ([plateSide] < 0: left of centre).
  List<double> candidates(
    double aspect, {
    required double widthFraction,
    double? plateSide,
  }) {
    final out = _solve(aspect, widthFraction).$1;
    if (plateSide == null || plateSide.abs() < 0.08) return _dedupe(out);
    // plate left of centre  <=>  sin(2·az) > 0  (左前 / 右後)
    final wantPositive = plateSide < 0;
    final kept = out.where((az) {
      final s = math.sin(2 * az * math.pi / 180);
      return wantPositive ? s > 0 : s < 0;
    }).toList();
    return _dedupe(kept.isEmpty ? out : kept);
  }

  /// [candidates], each with how sharply the box pins it, where the box's
  /// centre sits from the car's middle, and — given where in the box the
  /// plate was read, as ([PoseTable.plateX], [PoseTable.plateUp]) — how well
  /// that fits.
  List<OrbitCandidate> read(
    double aspect, {
    required double widthFraction,
    (double, double)? plate,
  }) {
    final (azimuths, outside) = _solve(aspect, widthFraction);
    final n = table.azimuths;
    final out = <OrbitCandidate>[];
    for (final az in _dedupe(azimuths)) {
      final i = ((az + 180) / table.step).round() % n;
      final double sigma;
      if (outside) {
        sigma = 12;
      } else {
        final slope =
            (table.aspectFor((i + 1) % n, widthFraction) -
                table.aspectFor((i + n - 1) % n, widthFraction)) /
            (2 * table.step);
        sigma = (aspectNoise * aspect / math.max(slope.abs(), 1e-6)).clamp(
          2.5,
          25.0,
        );
      }
      out.add(
        OrbitCandidate(
          az,
          sigma: sigma,
          centre: table.centreFor(i, widthFraction),
          weight: plate == null ? 1 : _plateFit(i, widthFraction, plate),
        ),
      );
    }
    // A plate that fits none of them is somebody else's, or a sign: say
    // nothing rather than let it pick.
    if (plate != null && out.every((c) => c.weight < 0.07)) {
      return [
        for (final c in out)
          OrbitCandidate(c.azimuth, sigma: c.sigma, centre: c.centre),
      ];
    }
    return out;
  }

  double _plateFit(int i, double widthFraction, (double, double) seen) {
    final want = table.plateFor(i, widthFraction);
    if (want == null) return 0.02;
    final dx = (seen.$1 - want.$1) / plateAcross;
    final dy = (seen.$2 - want.$2) / plateUp;
    return 0.02 + math.exp(-(dx * dx + dy * dy) / 2);
  }

  /// The azimuths, and whether the box was outside anything the model can
  /// look like.
  (List<double>, bool) _solve(double aspect, double widthFraction) {
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
    if (out.isNotEmpty) return (out, false);
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
    return (out, true);
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
