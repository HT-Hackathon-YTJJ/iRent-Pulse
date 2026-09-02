import 'package:flutter/material.dart';

import '../data/vehicle.dart';
import '../design/tokens.dart';
import '../widgets/back_button.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/map_backdrop.dart';
import '../widgets/pill_button.dart';
import '../widgets/vehicle_header.dart';
import 'assist_prompt_dialog.dart';
import 'detecting_dialog.dart';
import 'safe_drive_assist_screen.dart';
import 'start_vehicle_sheet.dart';
import 'vehicle_spec_sheet.dart';
import 'vehicle_status_screen.dart';

/// Map + vehicle card. Entry point of the "安心上路輔助" flow:
/// 開鎖 → 偵測車款 → 車輛規格 → 如何啟動 → 是否啟用輔助 → 輔助 / 車輛資訊
class TripScreen extends StatefulWidget {
  const TripScreen({super.key, this.vehicle = corollaCross});

  /// The car that was booked on the map. Defaults to the demo vehicle.
  final VehicleProfile vehicle;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  bool _busy = false;

  VehicleProfile get _vehicle => widget.vehicle;

  Future<void> _runUnlockFlow() async {
    if (_busy) return;
    setState(() => _busy = true);

    await showDetectingDialog(context, _vehicle);
    if (!mounted) return;

    final startNow = await showVehicleSpecSheet(context, _vehicle);
    if (!mounted) return;
    if (startNow != true) {
      setState(() => _busy = false);
      return;
    }

    await showStartVehicleSheet(context, _vehicle);
    if (!mounted) return;

    final enableAssist = await showAssistPromptDialog(context);
    if (!mounted) return;
    setState(() => _busy = false);

    if (enableAssist == true) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              SafeDriveAssistScreen(vehicle: _vehicle, replaceWithStatus: true),
        ),
      );
    } else if (enableAssist == false) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VehicleStatusScreen(vehicle: _vehicle),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: MapBackdrop(
                center: DemoPlace.chengKung,
                zoom: 14.9,
                bottomPadding: 226 + MediaQuery.paddingOf(context).bottom,
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: AppBackButton(
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // No grabber: this panel is pinned to the bottom of the
                  // 開鎖 screen and there is nothing above it to pull up to, so
                  // the handle was promising a gesture the page does not have.
                  VehicleHeaderPanel(
                    vehicle: _vehicle,
                    compact: true,
                    showGrabber: false,
                  ),
                  BottomActionBar(
                    shadow: false,
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColor.textSecondary,
                              width: 1.4,
                            ),
                          ),
                          child: const Icon(
                            Icons.question_mark,
                            size: 17,
                            color: AppColor.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: PillButton(
                            label: '開鎖',
                            icon: Icons.lock_open_rounded,
                            onPressed: _busy ? null : _runUnlockFlow,
                          ),
                        ),
                        const SizedBox(width: 42),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
