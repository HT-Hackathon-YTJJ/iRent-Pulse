import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../data/return_inspection.dart';
import 'car_detector.dart';
import 'frame_analysis.dart';

/// Everything L0 concluded about the frame that is on screen right now.
///
/// The screen reads only [state] and [hint]; the rest rides along because it is
/// the `l0` block that gets attached to the photo and handed to L1, which is
/// how L1 knows a manual shutter bypassed these checks.
class AimVerdict {
  const AimVerdict({
    required this.state,
    this.hint,
    this.carBox,
    this.coverage = 0,
    this.blurScore = 0,
    this.overExposed = 0,
    this.underExposed = 0,
    this.iou = 0,
    this.fill = 0,
    this.drift = 0,
    this.streak = 0,
    this.relaxed = false,
    this.manualOffered = false,
    this.detectorAvailable = true,
  });

  final AimState state;

  /// Centre pill copy: the one thing to fix, never a list.
  final String? hint;

  /// Where the car is, in upright normalised frame coordinates. Already
  /// smoothed — this is the box the verdict was reached on, so drawing it
  /// cannot disagree with the badge.
  final Rect? carBox;

  final double coverage;
  final double blurScore;
  final double overExposed;
  final double underExposed;

  /// Overlap with the on-screen guide outline. Reported for the L1 record and
  /// as a loose backstop; [fill] and [drift] are what actually decide.
  final double iou;

  /// How big the car is relative to the guide, as a **linear** ratio
  /// (√area). 1.0 means it fills the outline exactly; 0.7 means the driver is
  /// standing about 40% too far back.
  final double fill;

  /// How far the car's centre sits from the guide's, as a fraction of the
  /// guide's diagonal. 0 is dead centre.
  final double drift;

  /// Consecutive passing frames. The shutter arms at [AimEvaluator.holdFrames].
  final int streak;

  /// True once the thresholds have been widened because the driver has been
  /// standing there too long.
  final bool relaxed;

  /// True once a manual shutter is the honest way out.
  final bool manualOffered;

  final bool detectorAvailable;

  bool get isAcceptable => state == AimState.locked;

  /// The `l0` block attached to the photo (spec §L0 輸出).
  Map<String, Object?> report({required bool manual}) => {
    'passed': isAcceptable,
    'car_coverage': double.parse(coverage.toStringAsFixed(3)),
    'blur_score': double.parse(blurScore.toStringAsFixed(1)),
    'exposure': {
      'over': double.parse(overExposed.toStringAsFixed(3)),
      'under': double.parse(underExposed.toStringAsFixed(3)),
    },
    'guide_iou': double.parse(iou.toStringAsFixed(3)),
    'guide_fill': double.parse(fill.toStringAsFixed(3)),
    'guide_drift': double.parse(drift.toStringAsFixed(3)),
    'frames_confirmed': streak,
    'capture_mode': manual ? 'manual' : 'auto',
    'bypassed': manual && !isAcceptable,
    'relaxed': relaxed,
    'detector': detectorAvailable ? 'coco_ssd_mobilenet_v1' : 'none',
  };
}

/// Starting thresholds from 分層規格書 §L0, retuned after the first round of QA.
///
/// The original build gated alignment on a single IoU against the guide, and
/// that is what made the readout untrustworthy in both directions. IoU folds
/// *where* the car is and *how big* it is into one number, so a car that is the
/// right size but half a car-length to the left scores the same as one that is
/// centred and much too small — and both score the same as a perfectly aimed
/// frame whose bounding box is a little tall because the model included the
/// shadow. There was no threshold that let the good frames through and kept the
/// bad ones out, which is exactly the "框沒對到卻判定對到了" report.
///
/// So the two questions are asked separately, against the shape the driver can
/// actually see:
///
/// * [minFill] / [maxFill] — the car's linear size relative to the guide.
///   This is the one that maps onto a physical instruction: too small means
///   walk forward, too large means step back.
/// * [maxDrift] — how far the car's centre is from the guide's, as a fraction
///   of the guide's diagonal. This is what "對齊" means.
///
/// Both are scale-free, so they mean the same thing on every handset and for
/// every one of the four body angles, which the raw pixel thresholds did not.
///
/// **Widened after the second round of QA.** The numbers below are looser than
/// the ones the spec opens with, and deliberately so: the reported failure was
/// 「對準了還是說未對準」, which is the expensive direction to be wrong in. A
/// frame let through slightly off costs one imperfect photo that L1 still
/// reads; a frame held back that was fine costs a driver standing in a car
/// park shuffling back and forth at a badge that will not turn green, and some
/// of those drivers stop trying.
///
/// The two that were doing the rejecting are [maxDrift] and [minIou]: both
/// feed 未對準, and both were tuned against a silhouette rather than against a
/// detector's bounding box, which is a looser, shadow-inclusive, wing-mirror-
/// inclusive rectangle around the same car. [minFill] came down with them
/// because a bounding box drawn tight to the metal is smaller than the
/// outline it is being measured against almost by construction.
class AimThresholds {
  const AimThresholds({
    this.minScore = 0.35,
    this.minCoverage = 0.15,
    this.maxCoverage = 0.92,
    this.edgeMargin = 0.008,
    this.blurFloor = 55,
    this.maxOverExposed = 0.22,
    this.maxUnderExposed = 0.22,
    this.minFill = 0.62,
    this.maxFill = 1.45,
    this.maxDrift = 0.22,
    this.minIou = 0.26,
  });

  final double minScore;
  final double minCoverage;
  final double maxCoverage;
  final double edgeMargin;
  final double blurFloor;
  final double maxOverExposed;
  final double maxUnderExposed;
  final double minFill;
  final double maxFill;
  final double maxDrift;
  final double minIou;

  /// Widen by [factor] on every axis that can be widened.
  ///
  /// This exists because of the one way L0 can genuinely hurt the business: a
  /// driver standing in a car park whose shutter never goes green abandons the
  /// return, and that costs far more than one mediocre photo. It is also what
  /// [AimEvaluator] uses for hysteresis once a frame has locked.
  AimThresholds relaxedBy(double factor) => AimThresholds(
    minScore: minScore * (1 - factor),
    minCoverage: minCoverage * (1 - factor),
    maxCoverage: math.min(0.99, maxCoverage * (1 + factor)),
    edgeMargin: edgeMargin * (1 - factor),
    blurFloor: blurFloor * (1 - factor),
    maxOverExposed: math.min(0.5, maxOverExposed * (1 + factor)),
    maxUnderExposed: math.min(0.5, maxUnderExposed * (1 + factor)),
    minFill: minFill * (1 - factor),
    maxFill: maxFill * (1 + factor),
    maxDrift: maxDrift * (1 + factor),
    minIou: minIou * (1 - factor),
  );
}

/// Turns one frame into one verdict, and remembers how the last few went.
///
/// Tuning direction is **high pass rate**. Every check below reports the single
/// most actionable thing to fix, in the order a person would fix them, because
/// a pill that says "再靠近一點" moves someone and a pill that lists four
/// failures does not.
class AimEvaluator {
  AimEvaluator({
    this.base = const AimThresholds(),
    this.holdFrames = 3,
    this.guideRect,
    this.guideAllowsEdge = false,
  });

  final AimThresholds base;

  /// 連續確認 — how many passing frames in a row arm the shutter (~0.2s at the
  /// stream's 5 Hz). Three rather than five: the box is already exponentially
  /// smoothed, so the streak is there to reject a car that flashed past, not
  /// to smooth anything, and five frames was a visible beat between "this
  /// looks right" and the badge agreeing.
  final int holdFrames;

  /// The on-screen outline, in the same upright normalised space as the boxes.
  /// Null for the cabin shot, which has no silhouette to line up with.
  ///
  /// When the guide bleeds off an edge this is the **visible** part of it, so
  /// the car is scored against the shape the driver can actually fill.
  Rect? guideRect;

  /// True when the guide deliberately runs off a screen edge. The "車身被切到了"
  /// check is off for those slots — being cut off *is* the instruction.
  bool guideAllowsEdge;

  DateTime? _openedAt;
  int _streak = 0;

  /// Exponentially smoothed detection box.
  ///
  /// A single-shot SSD jitters by a few percent between frames even on a phone
  /// held still, and at 5 Hz that jitter was landing either side of the
  /// threshold and strobing the badge. Smoothing costs about 200ms of lag on a
  /// deliberate move, which nobody notices, and removes the flicker entirely.
  Rect? _smoothed;
  DateTime _smoothedAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const double _smoothing = 0.45;

  /// How long a detection stays usable. Without this the last box lived for
  /// ever, so a viewfinder pointed at a wall kept reporting 已對準 from a car
  /// that had left the frame ten seconds ago.
  static const Duration staleAfter = Duration(milliseconds: 700);

  /// 0–8s strict, 8–24s widened 20%, 24s+ manual shutter offered.
  ///
  /// Eight seconds because that is about how long someone tries before they
  /// start to think the thing is broken; fifteen was long enough that the
  /// widening arrived after they had already given up on it.
  static const Duration relaxAfter = Duration(seconds: 8);
  static const Duration manualAfter = Duration(seconds: 24);

  void restart() {
    _openedAt = DateTime.now();
    _streak = 0;
    _smoothed = null;
  }

  Duration get _elapsed =>
      _openedAt == null ? Duration.zero : DateTime.now().difference(_openedAt!);

  /// Feed a fresh detection in. Passing null means "the detector did not run
  /// this frame", which is different from "there is no car" — the smoothed box
  /// keeps its value until [staleAfter] passes.
  void observe(Detection? car, {DateTime? now}) {
    if (car == null) return;
    final at = now ?? DateTime.now();
    final previous = _smoothed;
    _smoothed = previous == null || at.difference(_smoothedAt) > staleAfter
        ? car.box
        : Rect.fromLTRB(
            _lerp(previous.left, car.box.left),
            _lerp(previous.top, car.box.top),
            _lerp(previous.right, car.box.right),
            _lerp(previous.bottom, car.box.bottom),
          );
    _smoothedAt = at;
  }

  static double _lerp(double from, double to) =>
      from + (to - from) * _smoothing;

  /// The box the verdict is reached on, or null once it has gone stale.
  Rect? boxAt(DateTime now) {
    final box = _smoothed;
    if (box == null || now.difference(_smoothedAt) > staleAfter) return null;
    return box;
  }

  AimVerdict evaluate({
    required FrameStats stats,
    required Detection? car,
    required bool detectorAvailable,
    required bool requireGuide,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    observe(car, now: at);

    final elapsed = _elapsed;
    final relaxed = elapsed >= relaxAfter;
    final manualOffered = elapsed >= manualAfter;
    var t = relaxed ? base.relaxedBy(0.2) : base;
    // Hysteresis: a frame that has already locked is held to a looser standard
    // than one trying to lock, so a breath in or out does not drop the shutter
    // out from under a driver who is already still.
    if (_streak >= holdFrames) t = t.relaxedBy(0.18);

    final box = boxAt(at);
    final guide = guideRect;
    final metrics = _measure(box, guide);

    AimVerdict verdict(AimState state, String? hint, int streak) => AimVerdict(
      state: state,
      hint: hint,
      carBox: box,
      coverage: box == null ? 0 : box.width * box.height,
      blurScore: stats.blurScore,
      overExposed: stats.overExposed,
      underExposed: stats.underExposed,
      iou: metrics.iou,
      fill: metrics.fill,
      drift: metrics.drift,
      streak: streak,
      relaxed: relaxed,
      manualOffered: manualOffered,
      detectorAvailable: detectorAvailable,
    );

    AimVerdict fail(AimState state, String hint) {
      _streak = 0;
      return verdict(state, hint, 0);
    }

    // Sharpness and exposure come first: they are true of the whole frame and
    // no amount of repositioning fixes them.
    if (stats.blurScore < t.blurFloor) {
      return fail(AimState.near, '請保持穩定，畫面有點模糊');
    }
    if (stats.overExposed > t.maxOverExposed) {
      return fail(AimState.near, '請換個角度避開強光');
    }
    if (stats.underExposed > t.maxUnderExposed) {
      return fail(AimState.near, '光線不足，已為你開啟閃光燈');
    }

    // Only the four body shots have a car to find. A cabin row or the sun
    // visor never will, so running the detector over them would hold those
    // slots on 未對準 for ever; sharpness and exposure are the whole of what L0
    // can honestly say about them.
    if (detectorAvailable && requireGuide) {
      if (box == null || (car != null && car.score < t.minScore)) {
        return fail(AimState.off, '對齊輪廓線');
      }

      // Order matters. Distance is asked before centring because a car that is
      // much too small is *also* far from centre by any measure, and telling
      // someone to centre a car they should be walking towards sends them the
      // wrong way. Both are amber: the frame is workable, it is the distance
      // that is wrong. Only "there is nothing here to align" is grey.
      if (guide != null) {
        if (metrics.fill < t.minFill) {
          return fail(AimState.near, '再靠近一點');
        }
        if (metrics.fill > t.maxFill) {
          return fail(AimState.near, '請再退後一步');
        }
        if (metrics.drift > t.maxDrift) {
          return fail(AimState.off, '對齊輪廓線');
        }
        // A backstop, not the decision: fill and drift can both pass on a car
        // whose box is the right size and place but a very different shape
        // (a van at the 右前 slot, a hedge the detector called a bus).
        if (metrics.iou < t.minIou) {
          return fail(AimState.off, '對齊輪廓線');
        }
      } else {
        final coverage = box.width * box.height;
        if (coverage < t.minCoverage) return fail(AimState.near, '再靠近一點');
        if (coverage > t.maxCoverage) return fail(AimState.near, '請再退後一步');
      }

      // With a bleeding guide the car is *supposed* to run off the edge, so
      // this only applies to the slots whose whole outline is on screen.
      if (!guideAllowsEdge) {
        final margin = t.edgeMargin;
        if (box.left < margin ||
            box.top < margin ||
            box.right > 1 - margin ||
            box.bottom > 1 - margin) {
          return fail(AimState.near, '車身被切到了，請退後一步');
        }
      }
    }

    _streak++;
    final locked = _streak >= holdFrames;
    return verdict(
      locked ? AimState.locked : AimState.near,
      locked ? null : '保持不動…',
      _streak,
    );
  }

  _GuideMetrics _measure(Rect? box, Rect? guide) {
    if (box == null || guide == null || guide.isEmpty) {
      return const _GuideMetrics(iou: 0, fill: 0, drift: 1);
    }

    final boxArea = box.width * box.height;
    final guideArea = guide.width * guide.height;

    final overlap = box.intersect(guide);
    final inter = overlap.width <= 0 || overlap.height <= 0
        ? 0.0
        : overlap.width * overlap.height;
    final union = boxArea + guideArea - inter;

    final diagonal = math.sqrt(
      guide.width * guide.width + guide.height * guide.height,
    );
    final offset = Offset(
      box.center.dx - guide.center.dx,
      box.center.dy - guide.center.dy,
    );

    return _GuideMetrics(
      iou: union <= 0 ? 0 : inter / union,
      fill: guideArea <= 0 ? 0 : math.sqrt(boxArea / guideArea),
      drift: diagonal <= 0 ? 1 : offset.distance / diagonal,
    );
  }
}

class _GuideMetrics {
  const _GuideMetrics({
    required this.iou,
    required this.fill,
    required this.drift,
  });

  final double iou;
  final double fill;
  final double drift;
}
