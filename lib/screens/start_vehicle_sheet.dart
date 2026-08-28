import 'package:flutter/material.dart';

import '../data/vehicle.dart';
import '../design/tokens.dart';
import '../widgets/dark_sheet.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/pill_button.dart';

Future<void> showStartVehicleSheet(
  BuildContext context,
  VehicleProfile vehicle,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x59000000),
    builder: (_) => _StartVehicleSheet(vehicle: vehicle),
  );
}

class _StartVehicleSheet extends StatelessWidget {
  const _StartVehicleSheet({required this.vehicle});

  final VehicleProfile vehicle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DarkSheetSurface(
          child: DarkSheetHeader(
            centered: true,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
            title: '如何啟動這輛車',
            titleStyle: AppText.titleXl,
            subtitle: vehicle.fullName,
          ),
        ),
        Container(
          width: double.infinity,
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 22, 24, 14),
                child: Text(
                  '啟動方式',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColor.textPrimary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                child: Column(
                  children: [
                    for (var i = 0; i < vehicle.startupSteps.length; i++)
                      _Step(index: i + 1, text: vehicle.startupSteps[i].text),
                  ],
                ),
              ),
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
                child: Image.asset(
                  vehicle.interiorImage,
                  width: double.infinity,
                  height: 208,
                  fit: BoxFit.cover,
                ),
              ),
              BottomActionBar(
                shadow: false,
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 17,
                          color: AppColor.textSecondary,
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            vehicle.startupNote,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColor.textSecondary,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    PillButton(
                      label: '了解了',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColor.brandBright,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15.5,
                color: AppColor.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
