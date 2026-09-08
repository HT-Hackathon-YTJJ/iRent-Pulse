import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';

import '../data/return_inspection.dart';
import '../data/vehicle.dart';
import '../design/tokens.dart';
import '../services/notifications.dart';
import '../services/return_session.dart';
import '../services/trip_state.dart';
import 'return_analysis_screen.dart';
import 'return_capture_screen.dart';
import 'return_done_screen.dart';
import 'return_release_screen.dart';

/// The 還車拍照 flow end to end (Figma group 986:1342).
///
/// Every step lives on one route rather than a stack of pushes: there is one
/// thing to leave, and leaving it abandons the return.
///
/// There used to be a fifth step between the analysis and the release — one
/// screen about one problem, with a 重拍 button on it. It is gone. The analysis
/// page reports every problem the return has, each with the photo it is about
/// and L1's own words for it, which is strictly more than that screen could say
/// and says it without a second round trip. Retaking is still possible and
/// always was: tapping a tile in the viewfinder goes back to that slot.
///
/// Which branch plays is decided by [ReturnScenario]. Long-pressing the
/// viewfinder title opens the picker, which is how the six board scenarios are
/// demonstrated without six entry points.
class ReturnFlowScreen extends StatefulWidget {
  const ReturnFlowScreen({
    super.key,
    this.scenario = ReturnScenario.allClear,
    this.orderId = '47352776',
    this.carNo,
    this.vehicle = corollaCross,
  });

  final ReturnScenario scenario;

  /// The car being handed back. Its 租用履歷 is the 留言板 L2 reads.
  final VehicleProfile vehicle;

  /// Carried on every L1 call and used by L2 to find this trip's pickup photos.
  final String orderId;
  /// Overrides the plate for a run that is not about [vehicle] — a test, or a
  /// scripted scenario. Normally null, and then the car being handed back is
  /// the one the driver has been looking at all along: see [_ReturnFlowScreenState._carNo].
  final String? carNo;

  @override
  State<ReturnFlowScreen> createState() => _ReturnFlowScreenState();
}

enum _Step { capture, analysis, release, done }

/// The board's 拍照流程 is all seven slots, in enum order: 加油卡/停車卡, both
/// cabin rows, then the four body corners.
const List<CaptureSpot> _allSpots = CaptureSpot.values;

class _ReturnFlowScreenState extends State<ReturnFlowScreen> {
  late ReturnScenario _scenario = widget.scenario;
  Set<CaptureSpot> _taken = {};
  late Set<CaptureSpot> _pending = _allSpots.toSet();
  _Step _step = _Step.capture;

  /// Keyed so the viewfinder rebuilds from scratch on a retake — which is why
  /// the photos live out here and not in its state.
  int _captureRun = 0;

  /// The frame taken for each filled slot, so the strip keeps showing the
  /// driver's own photos across a retake.
  final Map<CaptureSpot, File> _frames = {};

  /// The plate of the car being returned.
  ///
  /// Defaults to [VehicleProfile.plate] rather than to a literal. It used to be
  /// a hard-coded `RDS-6583` while the car on screen — the one in the booking
  /// sheet, the trip card and the 車輛資訊 header — was `REN-0000`, so every L1
  /// upload was filed against a car the driver had never seen. Harmless while
  /// nothing compared the two; the moment L0 started reading plates it became
  /// the viewfinder telling the driver 「這不是你租的車」 about the car the app
  /// itself had rented them.
  String get _carNo => widget.carNo ?? widget.vehicle.plate;

  late final ReturnSession _session = ReturnSession(
    orderId: widget.orderId,
    carNo: _carNo,
  );

  /// True when the backend answered and this run is doing the real thing.
  bool get _live => _session.live && _scenario == ReturnScenario.live;

  /// True when the flow opened wanting the live path and nothing answered.
  ///
  /// The screens are then exactly the scripted 情境① — every photo readable,
  /// the cabin clean — because that is the only verdict an app with no
  /// analysis behind it is entitled to reach. What this flag adds is the
  /// ending: 情境① is documented as 事後零通知, and a run that *tried* to be
  /// real has to finish with the push, or a demo on a dead network stops one
  /// screen short of the point it is making.
  ///
  /// Only ever set by [_probe], so picking ① by hand still gets its silence.
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    unawaited(_probe());
  }

  /// Ask the service once. If it is there, the flow opens in live mode; if it
  /// is not, the scripted board plays and nothing about the demo changes.
  Future<void> _probe() async {
    final reachable = await _session.probe();
    if (!mounted) return;
    if (!reachable) {
      if (widget.scenario == ReturnScenario.allClear) {
        setState(() => _offline = true);
      }
      return;
    }
    // Before any photo is taken, so every note predates the rental L2 is about
    // to judge. `Order.started_at` is stamped by the first L1 upload.
    unawaited(_session.publishBoard(widget.vehicle.reviews));
    if (widget.scenario == ReturnScenario.allClear) {
      // Not _restart: this runs from initState, so there is nothing to reset —
      // and _restart bumps _captureRun, which remounts the viewfinder and tears
      // the camera down a second after it opened. Switching the scenario is the
      // whole of what going live means here.
      setState(() => _scenario = ReturnScenario.live);
    }
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  ReturnAnalysis get _analysis =>
      _live ? _session.analysis : _scenario.analysis;

  void _restart(ReturnScenario scenario) => setState(() {
    // A previous run's verdict must not land on top of the new one.
    ReturnNotifications.instance.cancelPending();
    _scenario = scenario;
    // Hand-picking a scenario takes the run off the offline path: ① is then
    // being demonstrated for itself, silence included.
    _offline = false;
    _taken = {};
    _pending = _allSpots.toSet();
    _frames.clear();
    _step = _Step.capture;
    _captureRun++;
  });

  Future<void> _pickScenario() async {
    final picked = await showModalBottomSheet<ReturnScenario>(
      context: context,
      backgroundColor: Colors.white,
      // Seven scenarios with two lines of copy each do not fit above the fold
      // on a 346dp display, and a modal sheet does not scroll unless it is told
      // it may grow past half the screen.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) => _ScenarioPicker(current: _scenario),
    );
    if (picked != null) _restart(picked);
  }

  /// No camera means no real photos, so there is nothing honest for the live
  /// path to report. The scripted board takes over mid-flow; the viewfinder
  /// keeps its own copy of the shot list, so the screen the driver is looking
  /// at does not change under them.
  void _fallBackToScript() {
    if (_scenario != ReturnScenario.live) return;
    setState(() => _scenario = ReturnScenario.allClear);
  }

  void _afterAnalysis() {
    // Asked here, not at launch and not next to the camera prompt: the page the
    // driver is about to see says 「結果將以通知告知，您可立即離開」, so the reason for
    // the permission is on screen while the system dialog is up. A refusal
    // costs the driver the verdict — the return itself still completes, and
    // 訂單明細 carries the same copy whenever they go looking for it.
    unawaited(ReturnNotifications.instance.requestPermission());
    setState(() => _step = _Step.release);
  }

  /// 回到主頁 — drop back to the map, then let the follow-up pushes land.
  ///
  /// In live mode this is where L2 and L3 run. The driver is already walking
  /// away, which is the entire reason those layers are not part of the wait.
  void _goHome() {
    // The car is back. Nothing about this rental should survive a restart —
    // and popping to the map would otherwise leave 車輛資訊 restorable.
    unawaited(TripStore.end());

    if (_live) {
      unawaited(
        _session.finalizeInBackground().then((_) {
          final message = _session.decision?.notifyUser;
          _deliver([
            // No message means L2/L3 either found nothing worth saying or
            // never answered at all. Both end the same way for the driver.
            if (message == null)
              offlineReturnNotice
            else
              ReturnNotice(
                body: message,
                delay: const Duration(seconds: 1),
              ),
          ]);
        }),
      );
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }

    final scripted = _scenario.notices;
    final notices = scripted.isEmpty && _offline
        ? const [offlineReturnNotice]
        : scripted;
    Navigator.of(context).popUntil((r) => r.isFirst);
    _deliver(notices);
  }

  /// Send each verdict as a real OS notification, and only as that.
  ///
  /// There used to be an in-app banner alongside it, drawn the way the Figma
  /// boards show the push — on a lock screen, iOS-styled. Rendering that
  /// *inside* the app put an iOS notification on top of an Android phone, so
  /// the one surface that was meant to read as the system reading it out loud
  /// read instead as a bug. The tray is the real product behaviour, it is the
  /// one that still arrives when the app is closed, and it looks like whatever
  /// the driver's own phone looks like — so it is the only one left.
  void _deliver(List<ReturnNotice> notices) {
    if (notices.isEmpty) return;
    for (final notice in notices) {
      unawaited(
        ReturnNotifications.instance.notify(
          body: notice.body,
          delay: notice.delay,
          orderId: widget.orderId,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: KeyedSubtree(key: ValueKey('$_step-$_captureRun'), child: _body()),
    );
  }

  Widget _body() => switch (_step) {
    _Step.capture => ReturnCaptureScreen(
      spots: _allSpots,
      taken: _taken,
      pending: _pending,
      frames: _frames,
      onCaptured: (spot, file) => _frames[spot] = file,
      session: _live ? _session : null,
      // The 車牌比對 compares against the car on the rental agreement — the
      // same string every L1 upload is keyed by, so there is one answer to
      // "which car is this" and the viewfinder and the backend share it.
      expectedPlate: _carNo,
      startMisaligned: _scenario.startsMisaligned,
      onFinished: () => setState(() {
        _taken = {..._taken, ..._pending};
        _step = _Step.analysis;
      }),
      onExit: () => Navigator.of(context).maybePop(),
      onLongPressTitle: _pickScenario,
      onNoCamera: _fallBackToScript,
    ),
    _Step.analysis => ReturnAnalysisScreen(
      analysis: _analysis,
      session: _live ? _session : null,
      onContinue: _afterAnalysis,
    ),
    _Step.release => ReturnReleaseScreen(
      onFinish: () => setState(() => _step = _Step.done),
    ),
    _Step.done => ReturnDoneScreen(onHome: _goHome),
  };
}

// ---------------------------------------------------------------------------

/// Demo control: the six numbered scenarios from the Figma board.
class _ScenarioPicker extends StatelessWidget {
  const _ScenarioPicker({required this.current});

  final ReturnScenario current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        // Never taller than most of the screen, and scrollable inside that.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('還車情境', style: AppText.titleS),
                const SizedBox(height: 2),
                const Text(
                  '選一個情境重新開始拍照流程',
                  style: TextStyle(fontSize: 13, color: AppColor.textMuted),
                ),
                const SizedBox(height: 14),
                for (final s in ReturnScenario.values)
                  InkWell(
                    onTap: () => Navigator.of(context).pop(s),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 26,
                            child: Text(
                              s.number,
                              style: TextStyle(
                                fontSize: 16,
                                color: s == current
                                    ? AppColor.brand
                                    : AppColor.textSecondary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.title,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: s == current
                                        ? AppColor.brand
                                        : AppColor.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s.caption,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    height: 1.4,
                                    color: AppColor.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
