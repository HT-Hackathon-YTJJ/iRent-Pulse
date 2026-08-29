import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Domain model for the 還車拍照 flow (Figma group 986:1342).
///
/// The Figma board lays the flow out as six numbered scenarios. Everything the
/// screens need in order to play one of them back — the shot list, what the
/// on-device check reports, whether the driver is stopped, and which push
/// arrives afterwards — is declared here, so the widgets stay presentational
/// and the demo can be re-pointed at a real detector later by swapping
/// [ReturnScenario.analysis] for live data.

const String _kAssetRoot = 'assets/images/return';

// ---------------------------------------------------------------------------
// Shot list
// ---------------------------------------------------------------------------

/// One frame the driver has to hand in. Four corners plus the rear cabin.
enum CaptureSpot {
  frontLeft('左前'),
  frontRight('右前'),
  rearRight('右後'),
  rearLeft('左後'),
  interiorRear('後座');

  const CaptureSpot(this.label);

  /// Short name used inside the copy ("**右後** 照片有不明亮點…").
  final String label;

  bool get isCorner => this != CaptureSpot.interiorRear;

  /// Header title: the four corners are one 車身拍照 task, the cabin is its own.
  String get screenTitle => isCorner ? '車身拍照' : '車內裝（後座）';

  /// Sub-header under the title.
  String get instruction => isCorner ? '請拍攝車輛四角（含車牌）' : '請拍攝後座照片';

  /// Live view behind the viewfinder chrome. A still stands in for the camera
  /// feed until a real preview is wired up.
  String get viewfinderAsset => isCorner
      ? '$_kAssetRoot/camera_scene.png'
      : '$_kAssetRoot/shot_interior.jpg';

  /// Frame shown in the strip once the shot has been taken.
  String get shotAsset => isCorner
      ? '$_kAssetRoot/shot_scene.jpg'
      : '$_kAssetRoot/shot_interior.jpg';

  /// Silhouette shown in the strip while the slot is still empty.
  String get placeholderAsset {
    const outlines = [
      '$_kAssetRoot/corner_1.png',
      '$_kAssetRoot/corner_2.png',
      '$_kAssetRoot/corner_3.png',
    ];
    return outlines[index % outlines.length];
  }
}

/// What the on-device check makes of the current frame.
///
/// This is the 防亂拍 signal: it is evaluated live while the viewfinder is
/// open, never after the fact. The shutter stays armed in every state — an
/// off-target frame is warned about, not blocked (Figma scenario ⑥).
enum AimState {
  /// 未對準 — nothing recognisable in frame.
  off('未對準', AppColor.aimOff, '對齊灰色輪廓線'),

  /// 接近 — the car is found but too small or cropped.
  near('接近', AppColor.aimNear, '再靠近一點'),

  /// 已對準 — good enough to submit.
  locked('已對準', AppColor.aimLocked, null);

  const AimState(this.label, this.color, this.hint);

  final String label;
  final Color color;

  /// Centre pill copy; null once the frame is good, when the pill disappears.
  final String? hint;

  bool get isAcceptable => this == AimState.locked;
}

// ---------------------------------------------------------------------------
// Analysis
// ---------------------------------------------------------------------------

/// One row of the 還車分析 page — a title, a bar, and a verdict line.
class AnalysisCheck {
  const AnalysisCheck({
    required this.title,
    required this.pendingLabel,
    required this.resultLabel,
    required this.ok,
    this.ratio = 1.0,
  });

  final String title;

  /// Shown while the bar is still filling.
  final String pendingLabel;

  /// Shown once the bar settles.
  final String resultLabel;

  /// Drives the colour of the settled bar and its verdict line.
  final bool ok;

  /// How far the settled bar fills. A failed check stops short of the end.
  final double ratio;

  Color get resultColor => ok ? AppColor.successText : AppColor.aimNear;
}

/// The blocking problem the driver is shown after the analysis, if any.
class ReturnIssue {
  const ReturnIssue({
    required this.icon,
    required this.title,
    required this.emphasis,
    required this.body,
    required this.note,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.retakeSpot,
  });

  /// 200×200 vector shown above the headline.
  final String icon;
  final String title;

  /// Leading run set in bold inside [body] ("右後", "後座").
  final String emphasis;
  final String body;

  /// Copy of the amber advisory block.
  final String note;

  /// 重拍照片 / 我已清理，重拍車內照
  final String primaryLabel;

  /// 仍要還車 — always present. Nothing here blocks the return.
  final String secondaryLabel;

  /// Which slot the primary button sends the driver back to.
  final CaptureSpot retakeSpot;
}

/// The verdict the 還車分析 page renders.
class ReturnAnalysis {
  const ReturnAnalysis({required this.photo, required this.cabin, this.issue});

  final AnalysisCheck photo;
  final AnalysisCheck cabin;
  final ReturnIssue? issue;

  bool get allClear => issue == null;

  /// The primary button under the settled cards.
  String get continueLabel => allClear ? '繼續還車' : '前往下一步';

  static const _photoOk = AnalysisCheck(
    title: '照片可判讀性',
    pendingLabel: '正在處理中',
    resultLabel: '7 張照片皆可判讀',
    ok: true,
  );

  static const _cabinOk = AnalysisCheck(
    title: '車內整潔度',
    pendingLabel: '正在處理中',
    resultLabel: '車內整潔，無需清理',
    ok: true,
  );

  /// 情境①④⑤ — everything passes; any damage verdict is deliberately absent
  /// from this page and handled off-screen.
  static const clear = ReturnAnalysis(photo: _photoOk, cabin: _cabinOk);

  /// 情境② — one frame is unreadable and has to come back.
  static const glare = ReturnAnalysis(
    photo: AnalysisCheck(
      title: '照片可判讀性',
      pendingLabel: '正在處理中',
      resultLabel: '右後照片有局部反光，需重拍',
      ok: false,
      ratio: 0.82,
    ),
    cabin: _cabinOk,
    issue: ReturnIssue(
      icon: '$_kAssetRoot/icon_lightness.svg',
      title: '有一張照片需要重拍',
      emphasis: '右後',
      body: '照片有不明亮點（局部反光），影響判讀，請補拍一張。',
      note: '只需重拍這一張，\n其他 6 張已通過確認。',
      primaryLabel: '重拍照片',
      secondaryLabel: '仍要還車',
      retakeSpot: CaptureSpot.rearRight,
    ),
  );

  /// 情境③ — the only thing the driver is ever asked to fix on the spot.
  static const trash = ReturnAnalysis(
    photo: _photoOk,
    cabin: AnalysisCheck(
      title: '車內整潔度',
      pendingLabel: '正在處理中',
      resultLabel: '後座腳踏墊：飲料杯、紙袋',
      ok: false,
      ratio: 0.78,
    ),
    issue: ReturnIssue(
      icon: '$_kAssetRoot/icon_trash.svg',
      title: '車內偵測到垃圾',
      emphasis: '後座',
      body: '腳踏墊處有飲料杯與紙袋，請將垃圾帶走後再完成還車。',
      note: '順手帶走垃圾，維持你的優良駕駛等級；若未清理，可能會影響信用分數',
      primaryLabel: '我已清理，重拍車內照',
      secondaryLabel: '仍要還車',
      retakeSpot: CaptureSpot.interiorRear,
    ),
  );
}

// ---------------------------------------------------------------------------
// Follow-up notifications
// ---------------------------------------------------------------------------

/// A push that lands after the driver has already walked away.
///
/// The Figma boards show these on a lock screen; in the demo they arrive as an
/// in-app banner once the flow returns to the map, because the point being
/// demonstrated is the timing — nothing about damage is said at the counter.
class ReturnNotice {
  const ReturnNotice({
    required this.body,
    required this.age,
    required this.delay,
  });

  final String body;

  /// Timestamp shown on the banner, straight from the mock ("1h ago").
  final String age;

  /// How long after the return the banner appears in the demo.
  final Duration delay;
}

// ---------------------------------------------------------------------------
// Scenarios
// ---------------------------------------------------------------------------

/// The six columns of the Figma board, in board order.
enum ReturnScenario {
  /// ① 一切順利（最常見）— 全程放行
  allClear(number: '①', title: '一切順利', caption: '拍照全達標，分析全過，直接放行，事後零通知。'),

  /// ② 局部反光・需重拍 — 唯一會擋下的照片問題
  glare(number: '②', title: '有一張需要重拍', caption: '右後照片反光影響判讀，補拍一張後放行。'),

  /// ③ 車內偵測到垃圾（整潔度）— 唯一強制處理點
  trash(number: '③', title: '車內偵測到垃圾', caption: '可清理後重拍，或接受信用影響直接還車。'),

  /// ④ 紀錄外損傷・輕微 — 使用者全程無感
  minorDamage(
    number: '④',
    title: '輕微損傷（無感放行）',
    caption: '畫面與情境①相同，差異只在事後一則好消息。',
  ),

  /// ⑤ 紀錄外損傷・嚴重 — 當下放行・事後人工
  severeDamage(number: '⑤', title: '嚴重損傷（求償）', caption: '放行頁一字不提，求償由客服人工聯繫。'),

  /// ⑥ 亂拍・自負責任送出 — 還車不阻斷
  sloppy(number: '⑥', title: '亂拍・自負責任送出', caption: '快門永不鎖定，不合格照片可直接送出。');

  const ReturnScenario({
    required this.number,
    required this.title,
    required this.caption,
  });

  final String number;
  final String title;
  final String caption;

  /// What the 還車分析 page reports for this scenario.
  ReturnAnalysis get analysis => switch (this) {
    ReturnScenario.glare => ReturnAnalysis.glare,
    ReturnScenario.trash => ReturnAnalysis.trash,
    _ => ReturnAnalysis.clear,
  };

  /// Pushes that arrive after the driver has left.
  List<ReturnNotice> get notices => switch (this) {
    ReturnScenario.trash => const [
      ReturnNotice(
        body: '已確認車內整潔，您的信用分數維持不變，感謝配合✨',
        age: '1h ago',
        delay: Duration(seconds: 3),
      ),
    ],
    ReturnScenario.minorDamage => const [
      ReturnNotice(
        body: '本次還車深度分析已完成，您無需負擔任何費用。感謝愛惜車輛，優良駕駛進度 +1',
        age: '1h ago',
        delay: Duration(seconds: 3),
      ),
    ],
    ReturnScenario.severeDamage => const [
      ReturnNotice(
        body: '本次還車偵測到需進一步確認之車況，客服人員複核中，將於 24 小時內與您聯繫。',
        age: '1h ago',
        delay: Duration(seconds: 3),
      ),
      ReturnNotice(
        body:
            '經人工複核，本次租用期間新增「後保險桿脫落」。求償金額 NT\$8,500。'
            '點此查看取車／還車比對照片 · 7 日內提出申訴',
        age: '20m ago',
        delay: Duration(seconds: 9),
      ),
    ],
    _ => const [],
  };

  /// 情境⑥ opens the viewfinder already off-target so the 判定未達標 panel is
  /// the first thing the demo shows.
  bool get startsMisaligned => this == ReturnScenario.sloppy;
}
