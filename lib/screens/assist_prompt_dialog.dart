import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../widgets/pill_button.dart';

/// Returns true = 開啟安心上路輔助, false = 暫不開啟, null = dismissed.
Future<bool?> showAssistPromptDialog(BuildContext context) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '安心上路輔助',
    barrierColor: const Color(0x66000000),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => const _AssistPromptDialog(),
    transitionBuilder: (context, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(
          begin: 0.92,
          end: 1.0,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
        child: child,
      ),
    ),
  );
}

class _AssistPromptDialog extends StatelessWidget {
  const _AssistPromptDialog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.dialog),
          clipBehavior: Clip.antiAlias,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 350),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColor.successMint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    size: 40,
                    color: AppColor.success,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  '是否啟用安心上路輔助？',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColor.textInk,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '依照本次車款提供儀表板、方向盤、中控臺\n與各項操作方式的互動說明。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: AppColor.textMuted,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AppColor.warningSoftAlt,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_rounded,
                        size: 15,
                        color: AppColor.warningText,
                      ),
                      SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          '您第一次使用這款車輛，建議查看安心上路輔助',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            fontWeight: FontWeight.w700,
                            color: AppColor.warningText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                PillButton(
                  label: '開啟安心上路輔助',
                  maxWidth: 260,
                  textStyle: AppText.bodyL.copyWith(fontSize: 16),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
                const SizedBox(height: 10),
                PillButton(
                  label: '暫不開啟，直接查看車輛數據',
                  maxWidth: 260,
                  color: AppColor.textSecondary,
                  textStyle: AppText.bodyM.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
