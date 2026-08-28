import 'package:flutter/material.dart';

import '../data/vehicle.dart';
import '../design/tokens.dart';
import 'back_button.dart';
import 'dark_sheet.dart';

/// Dark vehicle block shared by the map card and the vehicle-status screen:
/// service badges, plate, rental window, station and the car render.
class VehicleHeaderPanel extends StatelessWidget {
  const VehicleHeaderPanel({
    super.key,
    required this.vehicle,
    this.compact = false,
    this.leading,
    this.trailing,
    this.showGrabber = true,
  });

  final VehicleProfile vehicle;
  final bool compact;
  final Widget? leading;
  final Widget? trailing;
  final bool showGrabber;

  @override
  Widget build(BuildContext context) {
    // A back button in the badge row makes that row as tall as the tap target,
    // so the top padding and the gap below shrink by the same amount: the
    // chevron lines up with the floating back button on the map screens while
    // the badges and the plate stay exactly where they were.
    final hasLeading = leading != null;

    return Container(
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
          if (showGrabber)
            const Padding(
              padding: EdgeInsets.only(top: 10, bottom: 12),
              child: SheetGrabber(),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              showGrabber
                  ? 0
                  : hasLeading
                  ? 8
                  : 14,
              16,
              compact ? 14 : 18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: hasLeading ? AppBackButton.size : null,
                  child: Row(
                    children: [
                      if (hasLeading) ...[leading!, const SizedBox(width: 2)],
                      Image.asset(
                        'assets/images/irent_logo.png',
                        width: 30,
                        height: 24,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 10),
                      const _Badge(
                        text: '安心服務',
                        bg: AppColor.accentBlueSoft,
                        fg: AppColor.accentBlue,
                      ),
                      const Spacer(),
                      const _Badge(
                        text: '抗冠空氣清淨',
                        bg: AppColor.mint,
                        fg: Colors.white,
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 8),
                        trailing!,
                      ],
                    ],
                  ),
                ),
                SizedBox(height: hasLeading ? 2 : 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            vehicle.plate,
                            style: const TextStyle(
                              fontSize: 23,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Row(
                            children: [
                              Text(
                                '8/18  15:30',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Icon(
                                  Icons.arrow_forward,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                '8/18  17:30',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 16,
                                color: Colors.white,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '成大站',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Image.asset(
                        vehicle.heroImage,
                        width: compact ? 132 : 152,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.bg, required this.fg});

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: fg,
          height: 1.3,
        ),
      ),
    );
  }
}
