import 'package:flutter/material.dart';

import '../data/vehicle.dart';
import '../design/tokens.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/dark_sheet.dart';
import '../widgets/pill_button.dart';

Future<bool?> showVehicleSpecSheet(
  BuildContext context,
  VehicleProfile vehicle,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x59000000),
    builder: (_) => _VehicleSpecSheet(vehicle: vehicle),
  );
}

class _VehicleSpecSheet extends StatelessWidget {
  const _VehicleSpecSheet({required this.vehicle});

  final VehicleProfile vehicle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: AppColor.sheetDark,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.sheet),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 10, bottom: 10),
                child: SheetGrabber(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 6, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            vehicle.brand,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColor.textOnDark,
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            vehicle.model,
                            style: const TextStyle(
                              fontSize: 24,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                            ),
                            child: Text(
                              vehicle.plate,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Image.asset(
                        vehicle.sideImage,
                        width: 206,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
        BottomActionBar(
          shadow: false,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SpecTable(specs: vehicle.specs),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColor.brandSoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.airline_seat_recline_normal,
                      size: 18,
                      color: AppColor.brand,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '請先繫上安全帶',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColor.brand,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              PillButton(
                label: '開始使用車輛',
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpecTable extends StatelessWidget {
  const _SpecTable({required this.specs});

  final List<SpecRow> specs;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColor.subtle,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < specs.length; i++)
            Container(
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : const Border(
                        top: BorderSide(color: Color(0xFFE8E8EC), width: 1),
                      ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  SizedBox(
                    width: 108,
                    child: Text(
                      specs[i].label,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColor.textSecondary,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 16,
                    color: const Color(0xFFDEDEE3),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      specs[i].value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColor.textPrimary,
                        letterSpacing: 0.6,
                      ),
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
