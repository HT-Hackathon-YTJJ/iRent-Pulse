import 'package:flutter/material.dart';

import '../data/return_inspection.dart';
import '../design/tokens.dart';
import '../widgets/return_footer.dart';

/// 還車分析中 → 還車分析完成 (Figma 825:3149, 827:4377, 830:5248).
///
/// Both states are one page: the bars fill, the verdict lines swap in, and the
/// footer appears. Only two things are ever reported here — whether the photos
/// can be read and whether the cabin is clean. Damage is deliberately absent;
/// that comparison runs in the back office and reaches the driver, if at all,
/// as a push hours later.
class ReturnAnalysisScreen extends StatefulWidget {
  const ReturnAnalysisScreen({
    super.key,
    required this.analysis,
    required this.onContinue,
  });

  final ReturnAnalysis analysis;
  final VoidCallback onContinue;

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
    final a = widget.analysis;

    return Scaffold(
      backgroundColor: Colors.white,
      body: AnimatedBuilder(
        animation: _run,
        builder: (context, _) {
          // Each bar settles on its own clock; the page turns over once the
          // slower of the two lands.
          final photoDone = _photo.value >= 1;
          final cabinDone = _cabin.value >= 1;
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

/// One 113.778pt card: title, bar, verdict line — all absolutely placed so the
/// two states line up pixel for pixel as the copy under the bar changes.
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
      height: 113.778,
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: _cardPad,
            top: 17.22,
            child: Text(check.title, style: ReturnText.cardTitle),
          ),
          Positioned(
            left: _cardPad,
            top: 52.4,
            child: SizedBox(
              width: _barWidth,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 8.982,
                    decoration: BoxDecoration(
                      color: trackColor,
                      borderRadius: BorderRadius.circular(4.491),
                    ),
                  ),
                  Container(
                    height: 8.982,
                    width: _barWidth * fill.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(4.491),
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
            ),
          ),
          Positioned(
            left: _cardPad,
            right: _cardPad,
            top: 71.86,
            child: Text(
              settled ? check.resultLabel : check.pendingLabel,
              style: ReturnText.cardStatus.copyWith(
                color: settled ? check.resultColor : AppColor.textProcessing,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
