import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../design/tokens.dart';
import '../widgets/return_footer.dart';

/// 還車完成 (Figma 827:3910).
///
/// The last page of the flow. Unlike the earlier steps this one carries no
/// footer slab — the button sits directly under the copy, 32pt down.
class ReturnDoneScreen extends StatelessWidget {
  const ReturnDoneScreen({super.key, required this.onHome});

  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + 126,
            bottom: 40,
          ),
          child: Center(
            child: SizedBox(
              width: 248.018,
              child: Column(
                children: [
                  SvgPicture.asset(
                    'assets/images/return/icon_success.svg',
                    width: 200,
                    height: 200,
                  ),
                  const SizedBox(height: 48),
                  const Text(
                    '還車完成',
                    textAlign: TextAlign.center,
                    style: ReturnText.headline,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '感謝使用 iRent。\n本次初步分析已完成。',
                    textAlign: TextAlign.center,
                    style: ReturnText.body,
                  ),
                  const SizedBox(height: 32),
                  ReturnButton(label: '回到主頁', onPressed: onHome),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
