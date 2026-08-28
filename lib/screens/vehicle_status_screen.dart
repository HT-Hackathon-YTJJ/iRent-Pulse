import 'package:flutter/material.dart';

import '../data/vehicle.dart';
import '../design/tokens.dart';
import '../widgets/pill_button.dart';
import '../widgets/vehicle_header.dart';
import 'return_checklist_dialog.dart';
import 'safe_drive_assist_screen.dart';

/// The three states the demo walks through on the vehicle-status screen.
enum TripStage { departure, driving, lowFuel }

class _StageData {
  const _StageData({
    required this.label,
    required this.fuelPercent,
    required this.rangeKm,
    required this.drivenKm,
    required this.timeLabel,
    required this.hours,
    required this.minutes,
  });

  final String label;
  final int fuelPercent;
  final int rangeKm;
  final int drivenKm;
  final String timeLabel;
  final int hours;
  final int minutes;

  bool get canReturn => fuelPercent >= 25;
}

const _stages = <TripStage, _StageData>{
  TripStage.departure: _StageData(
    label: '出發時',
    fuelPercent: 85,
    rangeKm: 600,
    drivenKm: 0,
    timeLabel: '剩餘時間',
    hours: 1,
    minutes: 30,
  ),
  TripStage.driving: _StageData(
    label: '行駛中',
    fuelPercent: 60,
    rangeKm: 454,
    drivenKm: 190,
    timeLabel: '剩餘時間',
    hours: 1,
    minutes: 30,
  ),
  TripStage.lowFuel: _StageData(
    label: '油量不足',
    fuelPercent: 24,
    rangeKm: 190,
    drivenKm: 200,
    timeLabel: '已使用時間',
    hours: 1,
    minutes: 55,
  ),
};

class VehicleStatusScreen extends StatefulWidget {
  const VehicleStatusScreen({
    super.key,
    required this.vehicle,
    this.stage = TripStage.departure,
  });

  final VehicleProfile vehicle;
  final TripStage stage;

  @override
  State<VehicleStatusScreen> createState() => _VehicleStatusScreenState();
}

class _VehicleStatusScreenState extends State<VehicleStatusScreen> {
  late TripStage _stage = widget.stage;

  _StageData get _data => _stages[_stage]!;

  Future<void> _return() async {
    final ok = await showReturnChecklistDialog(
      context,
      fuelPercent: _data.fuelPercent,
    );
    if (!mounted || ok != true) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColor.success,
        content: Text('已確認車輛狀態，進入還車流程'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final low = !data.canReturn;
    final accent = low ? AppColor.brand : AppColor.success;

    return Scaffold(
      backgroundColor: AppColor.page,
      body: Column(
        children: [
          Container(
            color: AppColor.sheetDark,
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
            child: VehicleHeaderPanel(
              vehicle: widget.vehicle,
              showGrabber: false,
              trailing: _StageMenu(
                stage: _stage,
                onChanged: (s) => setState(() => _stage = s),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(15, 16, 15, 20),
              children: [
                _FuelCard(
                  percent: data.fuelPercent,
                  rangeKm: data.rangeKm,
                  accent: accent,
                ),
                const SizedBox(height: 12),
                _MetricCard(
                  icon: Icons.directions_car_filled_outlined,
                  label: '已行駛里程數',
                  values: [('${data.drivenKm}', 'km')],
                ),
                const SizedBox(height: 12),
                _MetricCard(
                  icon: Icons.schedule,
                  label: data.timeLabel,
                  values: [('${data.hours}', '小時'), ('${data.minutes}', '分鐘')],
                ),
                const SizedBox(height: 16),
                const _Banner(
                  color: AppColor.successText,
                  background: AppColor.successSoft,
                  title: '背景服務運作中',
                  subtitle: '即時計算里程、油量與使用時間',
                ),
                if (low) ...[
                  const SizedBox(height: 12),
                  _Banner(
                    color: AppColor.warning,
                    background: AppColor.warningSoft,
                    title: '目前油量過低，無法還車',
                    subtitle: '請先加油後再回到還車流程',
                    onTap: () {},
                  ),
                ],
                const SizedBox(height: 12),
                _AssistShortcut(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          SafeDriveAssistScreen(vehicle: widget.vehicle),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: AppShadow.bottomBar,
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            child: PillButton(label: '還車', onPressed: _return),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _StageMenu extends StatelessWidget {
  const _StageMenu({required this.stage, required this.onChanged});

  final TripStage stage;
  final ValueChanged<TripStage> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TripStage>(
      initialValue: stage,
      onSelected: onChanged,
      tooltip: '切換示範情境',
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final entry in _stages.entries)
          PopupMenuItem(value: entry.key, child: Text(entry.value.label)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _stages[stage]!.label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Icon(Icons.expand_more, size: 15, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class _FuelCard extends StatelessWidget {
  const _FuelCard({
    required this.percent,
    required this.rangeKm,
    required this.accent,
  });

  final int percent;
  final int rangeKm;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Icon(
                Icons.local_gas_station,
                size: 20,
                color: AppColor.textPrimary,
              ),
              const SizedBox(width: 9),
              const Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Text(
                  '當前油量',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColor.textPrimary,
                  ),
                ),
              ),
              const Spacer(),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: percent.toDouble()),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text(
                  '${v.round()}%',
                  style: TextStyle(
                    fontSize: 46,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: accent,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '油量若低於 25% 將無法還車',
            style: TextStyle(fontSize: 9.5, color: AppColor.textSecondary),
          ),
          const SizedBox(height: 5),
          _FuelBar(percent: percent, color: accent),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '預估可行駛里程 $rangeKm km',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w500,
                color: accent,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              '實際續航里程將依路況及駕駛方式變動',
              style: TextStyle(fontSize: 12, color: AppColor.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _FuelBar extends StatelessWidget {
  const _FuelBar({required this.percent, required this.color});

  final int percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return SizedBox(
          height: 7,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColor.track,
                  borderRadius: BorderRadius.circular(AppRadius.bar),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: percent / 100),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Container(
                  width: w * v,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(AppRadius.bar),
                  ),
                ),
              ),
              // The "cannot return below 25%" zone, hatched over the fill.
              SizedBox(
                width: w * 0.25,
                child: ClipRRect(
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(AppRadius.bar),
                  ),
                  child: CustomPaint(
                    painter: const _HatchPainter(),
                    size: Size(w * 0.25, 7),
                  ),
                ),
              ),
              Positioned(
                left: w * 0.25 - 1,
                top: -2,
                child: Container(width: 2, height: 11, color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HatchPainter extends CustomPainter {
  const _HatchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x40000000)
      ..strokeWidth = 1.4;
    for (double x = -size.height; x < size.width; x += 5) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.values,
  });

  final IconData icon;
  final String label;
  final List<(String, String)> values;

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 23, color: AppColor.textPrimary),
          const SizedBox(width: 11),
          Text(
            label,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColor.textPrimary,
            ),
          ),
          const Spacer(),
          for (final (value, unit) in values) ...[
            Text(
              value,
              style: const TextStyle(
                fontSize: 30,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: AppColor.warning,
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                unit,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColor.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(18)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.card),
      boxShadow: AppShadow.card,
    ),
    child: child,
  );
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.background,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final Color color;
  final Color background;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, onTap == null ? 20 : 8, 12),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColor.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  size: 30,
                  color: color.withValues(alpha: 0.8),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistShortcut extends StatelessWidget {
  const _AssistShortcut({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColor.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColor.brandSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  size: 21,
                  color: AppColor.brand,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '安心上路輔助',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColor.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '隨時查看本車儀表板與各項操作說明',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColor.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 24,
                color: AppColor.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
