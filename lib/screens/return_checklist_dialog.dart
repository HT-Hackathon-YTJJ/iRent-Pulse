import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../widgets/pill_button.dart';

/// Returns true when the driver confirmed and the trip can move on to 還車.
Future<bool?> showReturnChecklistDialog(
  BuildContext context, {
  required int fuelPercent,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '下車前確認',
    barrierColor: const Color(0x73000000),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => _ReturnChecklistDialog(fuelPercent: fuelPercent),
    transitionBuilder: (context, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(
          begin: 0.94,
          end: 1.0,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
        child: child,
      ),
    ),
  );
}

class _CheckEntry {
  const _CheckEntry(this.title, this.detail, {this.ok = true});
  final String title;
  final String detail;
  final bool ok;
}

class _ReturnChecklistDialog extends StatelessWidget {
  const _ReturnChecklistDialog({required this.fuelPercent});

  final int fuelPercent;

  bool get _fuelOk => fuelPercent >= 25;

  List<_CheckEntry> get _entries => [
    const _CheckEntry('個人物品', '未偵測到遺留物品'),
    _fuelOk
        ? const _CheckEntry('排檔桿', '已切換至 P 檔')
        : const _CheckEntry('排檔桿', '排檔桿未切換至 P 檔', ok: false),
    const _CheckEntry('手煞車', '電子手煞車已啟用'),
    const _CheckEntry('車窗與車燈', '車窗關閉、車燈及空調已關閉'),
    _fuelOk
        ? _CheckEntry('油量', '目前油量為 $fuelPercent%，符合還車標準')
        : _CheckEntry('油量', '目前油量為 $fuelPercent%，低於還車標準，請先完成加油', ok: false),
  ];

  @override
  Widget build(BuildContext context) {
    final allOk = _entries.every((e) => e.ok);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 40),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.dialog),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 350),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: allOk
                            ? AppColor.successMint
                            : AppColor.warningSoftAlt,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        allOk
                            ? Icons.check_rounded
                            : Icons.priority_high_rounded,
                        size: 30,
                        color: allOk ? AppColor.success : AppColor.warning,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '下車前請再次確認',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColor.textInk,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      allOk ? '車輛已完成檢查，請確認以下狀態' : '請依照以下提示完成檢查後再還車',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: AppColor.textMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 18),
                    for (final e in _entries) ...[
                      _ChecklistRow(entry: e),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 8),
                    PillButton(
                      label: allOk ? '已確認，繼續還車' : '重新檢查',
                      color: allOk ? AppColor.brand : AppColor.warning,
                      onPressed: () => Navigator.of(context).pop(allOk),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.entry});

  final _CheckEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: entry.ok ? AppColor.subtle : AppColor.warningSoft,
        borderRadius: BorderRadius.circular(AppRadius.checklist),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: entry.ok ? AppColor.successBright : AppColor.warning,
              shape: BoxShape.circle,
            ),
            child: Icon(
              entry.ok ? Icons.check_rounded : Icons.priority_high_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColor.textInk,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  entry.detail,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppColor.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
