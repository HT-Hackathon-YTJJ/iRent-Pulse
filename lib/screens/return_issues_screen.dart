import 'package:flutter/material.dart';

import '../data/return_inspection.dart';
import '../design/tokens.dart';
import '../widgets/finding_card.dart';
import '../widgets/return_footer.dart';

/// 需處理 — the page after 還車分析完成, when the analysis found something
/// (Figma 830:5277, 831:6202).
///
/// The split is deliberate and it is the *only* thing this page adds over
/// printing the same cards under the two bars. The analysis page answers 「收到
/// 了嗎、過了幾張」 while the bars are still filling; this one answers 「那要我
/// 做什麼」 once they have settled. Mixing the two put a decision in front of a
/// driver who was still watching a progress bar.
///
/// **Every problem is on this page, not the worst one.** Figma draws one screen
/// per problem with one 重拍 button on it, which means a driver with a dirty
/// cabin *and* a glared corner tidies up, walks round, re-shoots, waits — and
/// only then learns about the second one. Listing them together costs one
/// scroll and buys one lap of the car instead of two: the 重拍 button below
/// re-opens the viewfinder with *all* the flagged slots pending, so they are
/// re-shot in a single pass.
class ReturnIssuesScreen extends StatelessWidget {
  const ReturnIssuesScreen({
    super.key,
    required this.findings,
    required this.onRetake,
    required this.onContinue,
  });

  /// Everything the analysis found, in slot order.
  final List<ReturnFinding> findings;

  /// 重拍 — back to the viewfinder with every flagged slot pending.
  final ValueChanged<Set<CaptureSpot>> onRetake;

  /// 仍要還車 — the escape hatch. Nothing on this page blocks the return; a
  /// driver who cannot fix a problem (or does not want to) still gets their
  /// car handed back, and the consequences are the ones the push describes.
  final VoidCallback onContinue;

  /// Content column, matching 還車分析 so the two pages line up as the driver
  /// moves between them.
  static const double _columnWidth = 299.415;

  /// The slots 重拍 re-opens. A finding with no slot behind it — nothing
  /// produces one today — would silently drop out rather than send the driver
  /// to a viewfinder with nothing pending in it.
  Set<CaptureSpot> get _retakeSpots =>
      findings.map((f) => f.spot).whereType<CaptureSpot>().toSet();

  bool get _allTrash =>
      findings.isNotEmpty && findings.every((f) => f.kind == FindingKind.trash);

  /// One problem gets named; several get counted.
  ///
  /// Naming the single case is what keeps the Figma's voice — 「車內偵測到垃圾」
  /// says what happened before the driver has read a word of the card. With
  /// three problems there is no single headline that is true, and a count is
  /// the one thing the driver needs before they start scrolling.
  String get _headline => findings.length == 1
      ? findings.single.title
      : '有 ${findings.length} 項需要處理';

  String get _subhead => findings.length == 1
      ? '處理後可以重拍，也可以直接完成還車'
      : '可以一次處理完再重拍，也可以直接完成還車';

  /// 我已清理 only when there is nothing but rubbish to clear — it is a claim
  /// about what the driver just did, and putting it on a glared bumper shot
  /// asks them to agree to something they did not do.
  String get _retakeLabel {
    if (_allTrash) return '我已清理，重拍車內照';
    return findings.length == 1 ? '重拍這張照片' : '重拍這 ${findings.length} 張照片';
  }

  /// The amber block under the cards. Rubbish is the one thing on this page
  /// with a consequence attached, so it is the one case that says so.
  String get _note => _allTrash
      ? '這不是違規紀錄，維持乾淨環境可以累積獎勵；\n若不清理，可能影響信用點數分數。'
      : '仍要還車不會被阻擋。補拍清楚的照片能讓後續的車況比對更準確，\n也是對你自己的保護。';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
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
                        Text(
                          _headline,
                          textAlign: TextAlign.center,
                          style: ReturnText.headline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _subhead,
                          textAlign: TextAlign.center,
                          style: ReturnText.subhead,
                        ),
                        const SizedBox(height: 19),
                        for (final finding in findings) ...[
                          FindingCard(finding: finding),
                          const SizedBox(height: 12),
                        ],
                        const SizedBox(height: 4),
                        _NoteBlock(text: _note),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ReturnFooter(
            children: [
              // 重拍 first and filled: it is the thing the page is asking for.
              // 仍要還車 is available in the same breath — it is not a warning
              // to be read past, it is the other half of a genuine choice — but
              // it is the one that is not being recommended, so it is the ring.
              ReturnButton(
                label: _retakeLabel,
                onPressed: _retakeSpots.isEmpty
                    ? null
                    : () => onRetake(_retakeSpots),
              ),
              ReturnButton(
                label: '仍要還車',
                secondary: true,
                onPressed: onContinue,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The amber advisory under the cards (Figma 1010:5904 — 10% #D4A82C, r4).
class _NoteBlock extends StatelessWidget {
  const _NoteBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColor.noteAmber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          height: 18 / 12,
          color: AppColor.noteAmberText,
        ),
      ),
    );
  }
}
