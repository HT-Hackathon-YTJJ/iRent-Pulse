import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';

import '../data/return_inspection.dart';
import '../data/vehicle.dart';
import '../l0/capture_session.dart';
import 'inspection_api.dart';

/// Where one slot stands, from the driver's point of view.
enum SlotPhase {
  /// No frame yet.
  empty,

  /// The photo is with L1 and the driver is waiting on it. This is the only
  /// blocking state in the whole flow.
  screening,

  /// L1 could read it.
  passed,

  /// L1 could not read it and the retake budget is not spent.
  retake,

  /// L1 never answered. The driver is released; the car is not.
  failed,
}

class SlotStatus {
  const SlotStatus({
    this.phase = SlotPhase.empty,
    this.file,
    this.result,
    this.message,
  });

  final SlotPhase phase;

  /// The local frame, shown in the strip while (and after) it is screened.
  final File? file;

  final L1Photo? result;

  /// Short line under the tile — 反光過強、請換角度 and the like.
  final String? message;

  bool get settled => phase == SlotPhase.passed || phase == SlotPhase.failed;
}

/// Drives one return: uploads each photo to L1 as it is taken, reports them one
/// by one, and synthesises the 還車分析 page from what actually came back.
///
/// 逐張回報 is not a presentation detail. Six photos screened in parallel means
/// 26% of drivers wait past p95 on the slowest one; reporting each as it lands
/// turns that into "the first one back", and lets a rejected frame be retaken
/// while the others are still in flight.
class ReturnSession extends ChangeNotifier {
  ReturnSession({
    required this.orderId,
    required this.carNo,
    InspectionApi? api,
  }) : api = api ?? InspectionApi();

  final String orderId;
  final String carNo;
  final InspectionApi api;

  /// False until the service answers /healthz. The scripted demo scenarios run
  /// unchanged when it does not, so a dead Wi-Fi never costs a demo.
  bool live = false;

  final Map<CaptureSpot, SlotStatus> _slots = {
    for (final spot in CaptureSpot.values) spot: const SlotStatus(),
  };

  L3Decision? decision;

  /// Slots that have already been screened once this trip. Drives the `retake`
  /// flag, and therefore the retake budget that L1 enforces — so it survives
  /// [clear], which only resets what the driver sees.
  final Set<CaptureSpot> _screenedOnce = {};

  Map<CaptureSpot, SlotStatus> get slots => Map.unmodifiable(_slots);

  SlotStatus statusOf(CaptureSpot spot) => _slots[spot] ?? const SlotStatus();

  Future<bool> probe() async {
    live = await api.reachable();
    notifyListeners();
    return live;
  }

  /// Push this car's 租用履歷 onto the service's 車輛歷程留言板.
  ///
  /// The board is the second thing L2 weighs a damage finding against, after
  /// the pickup photo — see `api/app/board.py`. In this app the board is real
  /// and visible: it is the 租用履歷 tab the driver read on the booking sheet
  /// before they ever touched the car. It is just *local*, which would leave
  /// L2 judging this trip without the one piece of context the driver already
  /// has.
  ///
  /// So it is uploaded when a live return opens, carrying each entry's own
  /// date. That matters twice over: notes are only prior evidence if they
  /// predate the rental, and 客服 reading a withheld claim gets the sentence
  /// with the date the driver saw next to it.
  ///
  /// Best effort. A board that fails to upload costs a 既有 verdict that could
  /// have been reached; it never costs a return.
  Future<void> publishBoard(List<RentalReview> reviews) async {
    if (!live || reviews.isEmpty) return;
    for (final review in reviews) {
      try {
        await api.addNote(
          carNo: carNo,
          text: review.text,
          createdAt: _isoFrom(review.date),
        );
      } catch (error) {
        debugPrint('留言板上傳失敗（不影響還車） — $error');
        return;
      }
    }
  }

  /// `2026/07/28` → `2026-07-28T00:00:00Z`. The board's dates are days, and a
  /// day is precise enough for a cut-off measured against a rental that starts
  /// when the first photo is taken.
  static String? _isoFrom(String date) {
    final parts = date.split('/');
    if (parts.length != 3) return null;
    final y = parts[0].padLeft(4, '0');
    final m = parts[1].padLeft(2, '0');
    final d = parts[2].padLeft(2, '0');
    return '$y-$m-${d}T00:00:00+00:00';
  }

  bool get anyScreening =>
      _slots.values.any((s) => s.phase == SlotPhase.screening);

  /// Slots that hold a frame, in strip order — the 逐張回報 row.
  List<CaptureSpot> get reportedSpots => CaptureSpot.values
      .where((spot) => statusOf(spot).phase != SlotPhase.empty)
      .toList();

  /// Called when the driver goes back to redo one slot, so the strip does not
  /// keep showing the rejected frame's verdict next to the new photo.
  void clear(CaptureSpot spot) => _set(spot, const SlotStatus());

  /// Slots L1 asked to see again.
  List<CaptureSpot> get retakeSpots => _slots.entries
      .where((e) => e.value.phase == SlotPhase.retake)
      .map((e) => e.key)
      .toList();

  void _set(CaptureSpot spot, SlotStatus status) {
    _slots[spot] = status;
    notifyListeners();
  }

  /// Hand one frame to L1. Returns when that photo has an answer; callers fire
  /// these off in parallel and let the UI update per slot.
  Future<void> submit(CaptureSpot spot, CapturedShot shot) async {
    _set(spot, SlotStatus(phase: SlotPhase.screening, file: shot.file));
    final retake = !_screenedOnce.add(spot);
    try {
      final result = await api.screen(
        photo: shot.file,
        orderId: orderId,
        carNo: carNo,
        slot: spot.label,
        stage: 'return',
        l0: shot.report,
        retake: retake,
      );
      _set(spot, _classify(shot.file, result));
    } catch (error) {
      // fail-open on the driver: they are released with "檢查中，稍後通知".
      // L3 puts the car into 停用(system_error) on the back of the same failure.
      _set(
        spot,
        SlotStatus(
          phase: SlotPhase.failed,
          file: shot.file,
          message: '檢查未完成，稍後通知',
        ),
      );
      debugPrint('L1 失敗（$spot）— $error');
    }
  }

  SlotStatus _classify(File file, L1Photo result) {
    if (result.error != null) {
      return SlotStatus(
        phase: SlotPhase.failed,
        file: file,
        result: result,
        message: '檢查未完成，稍後通知',
      );
    }
    if (result.retakeRequired) {
      return SlotStatus(
        phase: SlotPhase.retake,
        file: file,
        result: result,
        message: result.assessableReason ?? '需要重拍',
      );
    }
    return SlotStatus(
      phase: SlotPhase.passed,
      file: file,
      result: result,
      message: result.coverageAdequate ? null : result.coverageHint,
    );
  }

  /// Build the 還車分析 page out of real answers.
  ///
  /// Two things are reported and no more: whether the photos can be read, and
  /// whether the cabin is clean. Damage never appears here even when L1 already
  /// found it — the finding exists while the driver is still standing there,
  /// and withholding it is a deliberate product decision, not a technical one.
  ReturnAnalysis get analysis {
    final answered = _slots.entries
        .where((e) => e.value.result != null)
        .toList();
    if (answered.isEmpty) return ReturnAnalysis.clear;

    final unreadable = answered
        .where((e) => e.value.phase == SlotPhase.retake)
        .toList();
    final readable = answered.length - unreadable.length;

    final photoCheck = unreadable.isEmpty
        ? AnalysisCheck(
            title: '照片可判讀性',
            pendingLabel: '正在處理中',
            resultLabel: '${answered.length} 張照片皆可判讀',
            ok: true,
          )
        : AnalysisCheck(
            title: '照片可判讀性',
            pendingLabel: '正在處理中',
            resultLabel:
                '${unreadable.first.key.label}照片'
                '${unreadable.first.value.result?.assessableReason ?? '無法判讀'}，需重拍',
            ok: false,
            ratio: answered.isEmpty ? 0 : readable / answered.length,
          );

    final cabin = _slots[CaptureSpot.interiorRear]?.result;
    final dirty = cabin?.cleanliness == '髒汙';
    final cabinCheck = dirty
        ? AnalysisCheck(
            title: '車內整潔度',
            pendingLabel: '正在處理中',
            resultLabel: '${CaptureSpot.interiorRear.label}：${cabin!.items.join('、')}',
            ok: false,
            ratio: 0.78,
          )
        : const AnalysisCheck(
            title: '車內整潔度',
            pendingLabel: '正在處理中',
            resultLabel: '車內整潔，無需清理',
            ok: true,
          );

    return ReturnAnalysis(
      photo: photoCheck,
      cabin: cabinCheck,
      issue: _issue(dirty, cabin, unreadable),
    );
  }

  /// 髒汙 outranks a retake, matching L3's rule order: dirt lands on the next
  /// driver in half an hour, an unreadable frame only costs a review.
  ReturnIssue? _issue(
    bool dirty,
    L1Photo? cabin,
    List<MapEntry<CaptureSpot, SlotStatus>> unreadable,
  ) {
    if (dirty) {
      final items = cabin!.items.isEmpty ? '垃圾' : cabin.items.join('、');
      return ReturnIssue(
        icon: 'assets/images/return/icon_trash.svg',
        title: '車內偵測到垃圾',
        emphasis: CaptureSpot.interiorRear.label,
        body: '偵測到$items，請將垃圾帶走後再完成還車。',
        note: '順手帶走垃圾，維持你的優良駕駛等級；若未清理，可能會影響信用分數',
        primaryLabel: '我已清理，重拍車內照',
        secondaryLabel: '仍要還車',
        retakeSpot: CaptureSpot.interiorRear,
      );
    }
    if (unreadable.isEmpty) return null;
    final first = unreadable.first;
    final result = first.value.result!;
    return ReturnIssue(
      icon: 'assets/images/return/icon_lightness.svg',
      title: '有一張照片需要重拍',
      emphasis: first.key.label,
      body: '${result.assessableReason ?? '照片無法判讀'}。'
          '${result.retakeHint ?? '請補拍一張。'}',
      note: '只需重拍這一張，\n其他 ${_slots.values.where((s) => s.phase == SlotPhase.passed).length} 張已通過確認。',
      primaryLabel: '重拍照片',
      secondaryLabel: '仍要還車',
      retakeSpot: first.key,
    );
  }

  /// L2 + L3. Deliberately not awaited by the UI — the driver has left.
  Future<void> finalizeInBackground() async {
    if (!live) return;
    try {
      decision = await api.finalize(orderId: orderId, carNo: carNo);
      notifyListeners();
    } catch (error) {
      debugPrint('finalize 失敗 — $error');
    }
  }

  @override
  void dispose() {
    api.close();
    super.dispose();
  }
}
