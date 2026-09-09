import 'package:flutter/material.dart';

import '../data/return_inspection.dart';
import '../design/tokens.dart';
import '../services/return_session.dart';
import '../widgets/return_footer.dart';

/// 還車分析中 → 還車分析完成 (Figma 825:3149, 827:4377, 830:5248).
///
/// Both states are one page: the bars fill, the verdict lines swap in, and the
/// footer appears. Only two things are ever *scored* here — whether the photos
/// can be read and whether the cabin is clean. Damage is deliberately absent;
/// that comparison runs in the back office and reaches the driver, if at all,
/// as a push hours later.
///
/// Two bars and nothing else. Whatever they land on, the problems themselves
/// are on the *next* page — see [ReturnIssuesScreen], which lists all of them
/// at once and offers one retake for the lot.
///
/// The cards used to be printed under the bars here. That put a decision — go
/// back and re-shoot, or hand the car over — in front of a driver who was
/// still watching a progress bar fill, and it made one page answer two
/// questions: 「收到了嗎」 and 「那要我做什麼」. This page answers the first and
/// the footer button carries them to the second.
class ReturnAnalysisScreen extends StatefulWidget {
  const ReturnAnalysisScreen({
    super.key,
    required this.analysis,
    required this.onContinue,
    this.session,
  });

  final ReturnAnalysis analysis;
  final VoidCallback onContinue;

  /// Live L1 screening. When present the page settles on the *answers* rather
  /// than on a timer.
  final ReturnSession? session;

  @override
  State<ReturnAnalysisScreen> createState() => _ReturnAnalysisScreenState();
}

/// Content column: 299.415pt wide, 80pt from the top, 19pt between blocks.
const double _columnWidth = 299.415;
const double _cardPad = 16.47;
const double _barWidth = 263.485;

class _ReturnAnalysisScreenState extends State<ReturnAnalysisScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..forward();

  /// The two bars settle one after the other, which is what makes the page
  /// read as work being done rather than a spinner.
  late final Animation<double> _photo = CurvedAnimation(
    parent: _run,
    curve: const Interval(0.05, 0.68, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _cabin = CurvedAnimation(
    parent: _run,
    curve: const Interval(0.2, 0.95, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: AnimatedBuilder(
        animation: widget.session == null
            ? _run
            : Listenable.merge([_run, widget.session]),
        builder: (context, _) {
          // Each bar settles on its own clock; the page turns over once the
          // slower of the two lands.
          final live = widget.session;

          // Recomputed **inside** the builder, not read off `widget`.
          //
          // The photos are still in flight when this page opens — that overlap
          // is the whole point of 逐張回報 — so `widget.analysis` is a snapshot
          // of whatever had answered at the moment the flow switched screens.
          // Nothing rebuilds the flow after that, so the page kept that
          // snapshot for ever: seven photos were taken, five had come back, and
          // the page said 「5 張照片皆可判讀」 with a straight face while the
          // other two landed unread behind it.
          final a = live?.analysis ?? widget.analysis;
          // Wait on work that is actually in flight. Waiting on "no answers
          // yet" instead would hang this page forever in the one case where
          // nothing was ever uploaded.
          final waitingOnL1 = live != null && live.anyScreening;
          final photoDone = _photo.value >= 1 && !waitingOnL1;
          final cabinDone = _cabin.value >= 1 && !waitingOnL1;
          final settled = photoDone && cabinDone;

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top + 33,
                      bottom: 24,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: _columnWidth,
                        child: Column(
                          children: [
                            SizedBox(
                              // Figma pins this block at 252pt, where its copy
                              // fits on one line at Inter's metrics. The
                              // bundled CJK face runs a hair wider, so the
                              // block takes the full column instead of
                              // wrapping "初步確認" onto a second line.
                              width: _columnWidth,
                              child: Column(
                                children: [
                                  Text(
                                    settled ? '還車分析完成' : '還車分析中',
                                    textAlign: TextAlign.center,
                                    style: ReturnText.headline,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    settled ? '您的初步分析已完成' : '照片已上傳，正在進行初步確認',
                                    textAlign: TextAlign.center,
                                    style: ReturnText.subhead,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 19),
                            _CheckCard(
                              check: a.photo,
                              progress: _photo.value,
                              settled: photoDone,
                            ),
                            const SizedBox(height: 16),
                            _CheckCard(
                              check: a.cabin,
                              progress: _cabin.value,
                              settled: cabinDone,
                            ),
                            const SizedBox(height: 19),
                            _Footnote(settled: settled),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // The footer only exists once there is something to decide.
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                child: settled
                    ? ReturnFooter(
                        children: [
                          ReturnButton(
                            label: a.continueLabel,
                            onPressed: widget.onContinue,
                          ),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.settled});

  final bool settled;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 14.971,
      height: 22.756 / 14.971,
      color: AppColor.textPlaceholder,
    );

    return Text(
      settled ? '紀錄外損傷比對於後台完成，不顯示給您。\n本頁不會顯示任何車損判定。' : '正在處理中，請勿關閉此頁面',
      textAlign: TextAlign.center,
      style: style,
    );
  }
}

/// One card: title, bar, verdict line.
///
/// Laid out as a column, not as absolute positions inside a fixed 113.778pt
/// box, which is what the Figma frame is and what this used to be. The verdict
/// line is the problem with that: 「後座和右後不通過」 wraps to two lines on a
/// 346dp screen and the second one was drawn straight through the bottom of
/// the card. The Figma height is reproduced by the paddings when the copy fits
/// on one line, and the card simply grows when it does not.
class _CheckCard extends StatelessWidget {
  const _CheckCard({
    required this.check,
    required this.progress,
    required this.settled,
  });

  final AnalysisCheck check;

  /// 0…1 of the way through this card's own fill animation.
  final double progress;
  final bool settled;

  @override
  Widget build(BuildContext context) {
    final fill = settled ? check.ratio : progress * 0.92;
    final barColor = settled
        ? (check.ok ? AppColor.successText : AppColor.aimNear)
        : AppColor.barBusy;
    final trackColor = settled ? AppColor.barTrack : AppColor.track;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(_cardPad, 17.22, _cardPad, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColor.divider, width: 1.497),
        borderRadius: BorderRadius.circular(17.965),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 5.988,
            offset: Offset(0, 2.994),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(check.title, style: ReturnText.cardTitle),
          const SizedBox(height: 13),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 8.982,
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: BorderRadius.circular(4.491),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) => Container(
                  height: 8.982,
                  width: constraints.maxWidth * fill.clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(4.491),
                  ),
                ),
              ),
              if (!settled)
                Positioned(
                  left: (_barWidth * fill - 18).clamp(0.0, _barWidth - 18),
                  top: 4.1,
                  child: Text(
                    '${(fill * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 8,
                      color: AppColor.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            settled ? check.resultLabel : check.pendingLabel,
            style: ReturnText.cardStatus.copyWith(
              color: settled ? check.resultColor : AppColor.textProcessing,
            ),
          ),
        ],
      ),
    );
  }
}
