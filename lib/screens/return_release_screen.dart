import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../widgets/return_footer.dart';

/// 已完成初步判斷・可安心還車 (Figma 825:3683).
///
/// The release page. Whatever the back office is still chewing on, this screen
/// says nothing about it — the driver is told they may leave, and that is the
/// entire message.
class ReturnReleaseScreen extends StatelessWidget {
  const ReturnReleaseScreen({super.key, required this.onFinish});

  final VoidCallback onFinish;

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
                  top: MediaQuery.paddingOf(context).top + 131,
                  bottom: 24,
                ),
                child: Center(
                  child: SizedBox(
                    width: 320,
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: 431 / 292,
                          child: Image.asset(
                            'assets/images/return/car_release.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 48),
                        const Text(
                          '已完成初步判斷\n可安心還車',
                          textAlign: TextAlign.center,
                          style: ReturnText.headline,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '後續將於背景進行深度分析，\n結果將以通知告知，您可立即離開。',
                          textAlign: TextAlign.center,
                          style: ReturnText.body,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ReturnFooter(
            children: [ReturnButton(label: '完成還車', onPressed: onFinish)],
          ),
        ],
      ),
    );
  }
}
