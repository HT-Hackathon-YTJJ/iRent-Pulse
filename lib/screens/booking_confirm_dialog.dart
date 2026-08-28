import 'package:flutter/material.dart';

import '../data/vehicle.dart';
import '../design/tokens.dart';
import '../widgets/pill_button.dart';

/// Final confirmation before the car is held. Returns true when the driver
/// confirms, null / false when they back out.
Future<bool?> showBookingConfirmDialog(
  BuildContext context, {
  required VehicleListing listing,
  required int hours,
  required bool assurance,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '確認預約',
    barrierColor: const Color(0x73000000),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => _BookingConfirmDialog(
      listing: listing,
      hours: hours,
      assurance: assurance,
    ),
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

class _BookingConfirmDialog extends StatelessWidget {
  const _BookingConfirmDialog({
    required this.listing,
    required this.hours,
    required this.assurance,
  });

  final VehicleListing listing;
  final int hours;
  final bool assurance;

  int get _rent => listing.hourlyRate * hours;

  int get _total => listing.estimate(hours: hours, assurance: assurance);

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.dialog),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 360, maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '確認預約內容',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: AppColor.textInk,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _Bullets(
                          items: [
                            '預約車型：${listing.vehicle.fullName}',
                            '車牌號碼：${listing.plate}',
                            '取車地點：${listing.address}',
                            '取車保留倒數：${listing.holdMinutes} 分鐘',
                          ],
                        ),
                        const SizedBox(height: 18),
                        const _SectionTitle('預估費用清單'),
                        const SizedBox(height: 8),
                        _FeeRow(
                          label:
                              '租金預計使用 $hours 小時（平日 \$${listing.hourlyRate}/時）',
                          amount: '\$$_rent',
                        ),
                        if (assurance)
                          _FeeRow(
                            label: '安心服務基礎保障（加購 / 趟）',
                            amount: '\$${listing.assuranceRate}',
                          ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColor.brandSoft,
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '本次預估授權金額',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColor.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                '\$$_total',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColor.brand,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        const _SectionTitle('待結算費用（還車時依實際用量計費）'),
                        const SizedBox(height: 8),
                        _Bullets(
                          muted: true,
                          items: [
                            '里程費：依實際行駛里程計算（約 \$${listing.mileageRate} / km，以車載系統回傳為準）。',
                            '高速公路通行費（eTag）：依遠通電收實際產生通行費結算。',
                            '逾時費：超過預約時間後，依逾時費率計收。',
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
                  child: Column(
                    children: [
                      PillButton(
                        label: listing.mode.bookLabel,
                        maxWidth: 260,
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text(
                          '返回',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColor.textPrimary,
                          ),
                        ),
                      ),
                    ],
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: AppColor.textInk,
      letterSpacing: 0.4,
    ),
  );
}

class _Bullets extends StatelessWidget {
  const _Bullets({required this.items, this.muted = false});

  final List<String> items;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 7, right: 8),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: muted ? AppColor.textSecondary : AppColor.brand,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: muted ? 12.5 : 13.5,
                      height: 1.5,
                      color: muted ? AppColor.textMuted : AppColor.textPrimary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow({required this.label, required this.amount});

  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColor.textPrimary,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            amount,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColor.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
