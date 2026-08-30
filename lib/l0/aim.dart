import 'dart:math' as math;
import 'dart:ui' show Rect;

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
    this.streak = 0,
    this.relaxed = false,
    this.manualOffered = false,
    this.detectorAvailable = true,
  });

  final AimState state;

  /// Centre pill copy: the one thing to fix, never a list.
  final String? hint;

  /// Where the car is, in upright normalised frame coordinates.
  final Rect? carBox;

  final double coverage;
  final double blurScore;
  final double overExposed;
  final double underExposed;

  /// Overlap with the on-screen guide outline. Pure geometry, not a model.
  final double iou;

  /// Consecutive passing frames. The shutter fires on [AimEvaluator.holdFrames].
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
    'frames_confirmed': streak,
    'capture_mode': manual ? 'manual' : 'auto',
    'bypassed': manual && !isAcceptable,
    'relaxed': relaxed,
    'detector': detectorAvailable ? 'coco_ssd_mobilenet_v1' : 'none',
  };
}

/// Starting thresholds from 分層規格書 §L0. Every one of them needs calibrating
/// against real handsets — [blurFloor] most of all, because a Laplacian
/// variance has no absolute meaning across sensors and resolutions.
class AimThresholds {
  const AimThresholds({
    this.minScore = 0.7,
    this.minCoverage = 0.35,
    this.maxCoverage = 0.85,
    this.edgeMargin = 0.02,
    this.blurFloor = 80,
    this.maxOverExposed = 0.15,
    this.maxUnderExposed = 0.15,
    this.minIou = 0.55,
  });

  final double minScore;
  final double minCoverage;
  final double maxCoverage;
  final double edgeMargin;
  final double blurFloor;
  final double maxOverExposed;
  final double maxUnderExposed;
  final double minIou;

  /// Widen by [factor] on every axis that can be widened.
  ///
  /// This exists because of the one way L0 can genuinely hurt the business: a
  /// driver standing in a car park whose shutter simply never fires abandons
  /// the return, and that costs far more than one mediocre photo.
  AimThresholds relaxedBy(double factor) => AimThresholds(
    minScore: minScore * (1 - factor),
    minCoverage: minCoverage * (1 - factor),
    maxCoverage: math.min(0.98, maxCoverage * (1 + factor)),
    edgeMargin: edgeMargin * (1 - factor),
    blurFloor: blurFloor * (1 - factor),
    maxOverExposed: math.min(0.5, maxOverExposed * (1 + factor)),
    maxUnderExposed: math.min(0.5, maxUnderExposed * (1 + factor)),
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
    this.holdFrames = 5,
    this.guideRect,
  });

  final AimThresholds base;

  /// 連續確認 — how many passing frames in a row arm the shutter (~0.3s).
  final int holdFrames;

  /// The on-screen outline, in the same upright normalised space as the boxes.
  /// Null for the cabin shot, which has no silhouette to line up with.
  Rect? guideRect;

  DateTime? _openedAt;
  int _streak = 0;

  /// 0–15s strict, 15–30s widened 20%, 30s+ manual shutter offered.
  static const Duration relaxAfter = Duration(seconds: 15);
  static const Duration manualAfter = Duration(seconds: 30);

  void restart() {
    _openedAt = DateTime.now();
    _streak = 0;
  }

  Duration get _elapsed =>
      _openedAt == null ? Duration.zero : DateTime.now().difference(_openedAt!);

  AimVerdict evaluate({
    required FrameStats stats,
    required Detection? car,
    required bool detectorAvailable,
    required bool requireGuide,
  }) {
    final elapsed = _elapsed;
    final relaxed = elapsed >= relaxAfter;
    final manualOffered = elapsed >= manualAfter;
    final t = relaxed ? base.relaxedBy(0.2) : base;

    AimVerdict fail(AimState state, String hint) {
      _streak = 0;
      return AimVerdict(
        state: state,
        hint: hint,
        carBox: car?.box,
        coverage: car?.area ?? 0,
        blurScore: stats.blurScore,
        overExposed: stats.overExposed,
        underExposed: stats.underExposed,
        iou: _iou(car?.box),
        streak: 0,
        relaxed: relaxed,
        manualOffered: manualOffered,
        detectorAvailable: detectorAvailable,
      );
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
      if (car == null || car.score < t.minScore) {
        return fail(AimState.off, '對齊灰色輪廓線');
      }
      final coverage = car.area;
      if (coverage < t.minCoverage) return fail(AimState.near, '再靠近一點');
      if (coverage > t.maxCoverage) return fail(AimState.near, '請再退後一步');

      final box = car.box;
      final margin = t.edgeMargin;
      if (box.left < margin ||
          box.top < margin ||
          box.right > 1 - margin ||
          box.bottom > 1 - margin) {
        return fail(AimState.near, '車身被切到了，請退後一步');
      }

      if (requireGuide && guideRect != null && _iou(box) < t.minIou) {
        return fail(AimState.near, '對齊灰色輪廓線');
      }
    }

    _streak++;
    return AimVerdict(
      state: _streak >= holdFrames ? AimState.locked : AimState.near,
      hint: _streak >= holdFrames ? null : '保持不動…',
      carBox: car?.box,
      coverage: car?.area ?? 0,
      blurScore: stats.blurScore,
      overExposed: stats.overExposed,
      underExposed: stats.underExposed,
      iou: _iou(car?.box),
      streak: _streak,
      relaxed: relaxed,
      manualOffered: manualOffered,
      detectorAvailable: detectorAvailable,
    );
  }

  double _iou(Rect? box) {
    final guide = guideRect;
    if (box == null || guide == null) return 0;
    final overlap = box.intersect(guide);
    if (overlap.width <= 0 || overlap.height <= 0) return 0;
    final inter = overlap.width * overlap.height;
    final union =
        box.width * box.height + guide.width * guide.height - inter;
    return union <= 0 ? 0 : inter / union;
  }
}
