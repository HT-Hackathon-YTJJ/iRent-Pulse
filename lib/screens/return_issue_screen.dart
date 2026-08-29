import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/return_inspection.dart';
import '../design/tokens.dart';
import '../widgets/return_footer.dart';

/// 有一張照片需要重拍 / 車內偵測到垃圾 (Figma 827:4669, 830:5277).
///
/// One page for both, because the design treats them as the same object: a
/// 200pt mark, a headline, a sentence whose subject is bolded, an amber
/// advisory, and two pills. The second pill is always 仍要還車 — the driver can
/// decline the fix and still finish.
class ReturnIssueScreen extends StatelessWidget {
  const ReturnIssueScreen({
    super.key,
    required this.issue,
    required this.onRetake,
    required this.onSkip,
  });

  final ReturnIssue issue;

  /// 重拍照片 / 我已清理，重拍車內照
  final VoidCallback onRetake;

  /// 仍要還車
  final VoidCallback onSkip;

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
                  top: MediaQuery.paddingOf(context).top + 118,
                  bottom: 24,
                ),
                child: Center(
                  child: SizedBox(
                    width: 302.497,
                    child: Column(
                      children: [
                        SvgPicture.asset(issue.icon, width: 200, height: 200),
                        const SizedBox(height: 20),
                        Text(
                          issue.title,
                          textAlign: TextAlign.center,
                          style: ReturnText.headline,
                        ),
                        const SizedBox(height: 20),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${issue.emphasis} ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(text: issue.body),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          style: ReturnText.body,
                        ),
                        const SizedBox(height: 20),
                        _AmberNote(text: issue.note),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ReturnFooter(
            verticalPadding: 24,
            children: [
              ReturnButton(label: issue.primaryLabel, onPressed: onRetake),
              ReturnButton(
                label: issue.secondaryLabel,
                onPressed: onSkip,
                secondary: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The advisory block under the sentence — amber on a 28% amber wash.
class _AmberNote extends StatelessWidget {
  const _AmberNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 77.848),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13.05),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColor.noteAmberFill,
        border: Border.all(color: AppColor.noteAmber, width: 1.497),
        borderRadius: BorderRadius.circular(13.474),
      ),
      child: Text(text, textAlign: TextAlign.center, style: ReturnText.note),
    );
  }
}
