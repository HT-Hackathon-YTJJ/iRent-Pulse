import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';

import '../data/return_inspection.dart';
import '../data/vehicle.dart';
import '../design/tokens.dart';
import '../services/notifications.dart';
import '../services/return_session.dart';
import '../services/trip_state.dart';
import '../widgets/return_notice_banner.dart';
import 'order_detail_screen.dart';
import 'return_analysis_screen.dart';
import 'return_capture_screen.dart';
import 'return_done_screen.dart';
import 'return_issue_screen.dart';
import 'return_release_screen.dart';

/// The 還車拍照 flow end to end (Figma group 986:1342).
///
/// Every step lives on one route rather than a stack of pushes, because the
/// board's branches loop: a retake sends the driver back to the viewfinder for
/// a single slot and then forward through the same analysis page. Modelling
/// that as a step machine keeps the back stack honest — there is one thing to
/// leave, and leaving it abandons the return.
///
/// Which branch plays is decided by [ReturnScenario]. Long-pressing the
/// viewfinder title opens the picker, which is how the six board scenarios are
/// demonstrated without six entry points.
class ReturnFlowScreen extends StatefulWidget {
  const ReturnFlowScreen({
    super.key,
    this.scenario = ReturnScenario.allClear,
    this.orderId = '47352776',
    this.carNo = 'RDS-6583',
    this.vehicle = corollaCross,
  });

  final ReturnScenario scenario;

  /// The car being handed back. Its 租用履歷 is the 留言板 L2 reads.
  final VehicleProfile vehicle;

  /// Carried on every L1 call and used by L2 to find this trip's pickup photos.
  final String orderId;
  final String carNo;

  @override
  State<ReturnFlowScreen> createState() => _ReturnFlowScreenState();
}

enum _Step { capture, analysis, issue, release, done }

/// The board's 拍照流程 is all seven slots, in enum order: 加油卡/停車卡, both
/// cabin rows, then the four body corners.
const List<CaptureSpot> _allSpots = CaptureSpot.values;

class _ReturnFlowScreenState extends State<ReturnFlowScreen> {
  late ReturnScenario _scenario = widget.scenario;
  Set<CaptureSpot> _taken = {};
  late Set<CaptureSpot> _pending = _allSpots.toSet();
  _Step _step = _Step.capture;

  /// Once the driver has redone the flagged shot (or cleared the cabin), the
  /// second pass through the analysis comes back clean. Scripted scenarios only
  /// — in live mode the second pass is answered by L1 like the first one.
  bool _resolved = false;

  /// Keyed so the viewfinder rebuilds from scratch on a retake — which is why
  /// the photos live out here and not in its state.
  int _captureRun = 0;

  /// The frame taken for each filled slot, so the strip keeps showing the
  /// driver's own photos across a retake.
  final Map<CaptureSpot, File> _frames = {};

  late final ReturnSession _session = ReturnSession(
    orderId: widget.orderId,
    carNo: widget.carNo,
  );

  /// True when the backend answered and this run is doing the real thing.
  bool get _live => _session.live && _scenario == ReturnScenario.live;

  @override
  void initState() {
    super.initState();
    unawaited(_probe());
  }

  /// Ask the service once. If it is there, the flow opens in live mode; if it
  /// is not, the scripted board plays and nothing about the demo changes.
  Future<void> _probe() async {
    final reachable = await _session.probe();
    if (!mounted || !reachable) return;
    // Before any photo is taken, so every note predates the rental L2 is about
    // to judge. `Order.started_at` is stamped by the first L1 upload.
    unawaited(_session.publishBoard(widget.vehicle.reviews));
    if (widget.scenario == ReturnScenario.allClear) {
      _restart(ReturnScenario.live);
    }
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  ReturnAnalysis get _analysis {
    if (_live) return _session.analysis;
    return _resolved ? ReturnAnalysis.clear : _scenario.analysis;
  }

  void _restart(ReturnScenario scenario) => setState(() {
    // A previous run's verdict must not land on top of the new one.
    ReturnNotifications.instance.cancelPending();
    _scenario = scenario;
    _taken = {};
    _pending = _allSpots.toSet();
    _frames.clear();
    _resolved = false;
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
    // the permission is on screen while the system dialog is up. A refusal is
    // not a dead end — ReturnNoticeBanner shows the same copy in-app.
    unawaited(ReturnNotifications.instance.requestPermission());
    setState(() {
      _step = _analysis.issue == null ? _Step.release : _Step.issue;
    });
  }

  void _retake(ReturnIssue issue) {
    // The flagged slot goes back to empty so the strip stops showing the
    // rejected frame's verdict beside the replacement.
    if (_live) _session.clear(issue.retakeSpot);
    _frames.remove(issue.retakeSpot);
    setState(() {
      _taken = {..._taken}..remove(issue.retakeSpot);
      _pending = {issue.retakeSpot};
      _resolved = true;
      _step = _Step.capture;
      _captureRun++;
    });
  }

  /// 回到主頁 — drop back to the map, then let the follow-up pushes land.
  ///
  /// In live mode this is where L2 and L3 run. The driver is already walking
  /// away, which is the entire reason those layers are not part of the wait.
  void _goHome() {
    // Resolved before the pop: this route is what is being torn down.
    final overlay = Overlay.of(context, rootOverlay: true);

    // The car is back. Nothing about this rental should survive a restart —
    // and popping to the map would otherwise leave 車輛資訊 restorable.
    unawaited(TripStore.end());

    if (_live) {
      unawaited(
        _session.finalizeInBackground().then((_) {
          final message = _session.decision?.notifyUser;
          if (message == null) return;
          _deliver([
            ReturnNotice(
              body: message,
              age: 'just now',
              delay: const Duration(seconds: 1),
            ),
          ], overlay);
        }),
      );
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }

    final notices = _scenario.notices;
    Navigator.of(context).popUntil((r) => r.isFirst);
    _deliver(notices, overlay);
  }

  /// Send each verdict twice over: once as a real OS notification, once as the
  /// in-app banner the boards draw.
  ///
  /// Not a fallback chain — both, deliberately. The OS notification is the real
  /// product behaviour and the one that still arrives when the app is closed;
  /// the banner is what a projector, a muted simulator, the web build or a
  /// declined permission can still show. Whichever the driver taps opens the
  /// same 訂單明細 page.
  void _deliver(List<ReturnNotice> notices, OverlayState overlay) {
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
    ReturnNoticeBanner.schedule(overlay, notices, onTap: _openOrder);
  }

  void _openOrder() {
    ReturnNotifications.navigatorKey.currentState?.push(
      OrderDetailScreen.route(),
    );
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
      startMisaligned: _scenario.startsMisaligned && !_resolved,
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
    _Step.issue => ReturnIssueScreen(
      issue: _analysis.issue!,
      onRetake: () => _retake(_analysis.issue!),
      onSkip: () => setState(() => _step = _Step.release),
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
