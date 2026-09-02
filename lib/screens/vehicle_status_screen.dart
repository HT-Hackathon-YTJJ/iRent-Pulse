import 'package:flutter/material.dart';

import '../data/vehicle.dart';
import '../design/tokens.dart';
import '../services/trip_state.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/map_backdrop.dart';
import '../widgets/pill_button.dart';
import '../widgets/vehicle_header.dart';
import 'return_checklist_dialog.dart';
import 'return_flow_screen.dart';
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

/// 車輛資訊 — what the driver is looking at while the car is out.
///
/// This is a **sheet over the live map**, not a page.
///
/// It used to be a full-screen route with a back chevron, and that was wrong in
/// two ways at once. The chevron pointed at a screen the driver could not
/// usefully be on — the car is unlocked and running, so "back" is not a state
/// that exists — and the page hid the one thing someone driving actually needs
/// on screen: where they are, and where the nearest petrol station is. Putting
/// the panel on a sheet keeps the map underneath it and lets the driver push it
/// out of the way with a thumb, which is the whole point.
///
/// The sheet has two stops and cannot be dismissed. It opens full height —
/// everything but the status bar, which stays uncovered so the clock and the
/// battery are not sitting on the sheet's own header — and a pull down takes
/// it straight to the shallow stop, which still shows the plate, the fuel and
/// 還車.
///
/// Two stops rather than three on purpose. The middle stop showed the fuel
/// card and half of the next one, which is neither of the two things anyone
/// opens this screen for: the whole panel, or the map with the panel out of
/// the way. Every drag ended in one more drag, so the stop in between was a
/// stop nobody wanted to be at. There is no gesture that makes a running
/// rental disappear — the only way out of this screen is through the return.
class VehicleStatusScreen extends StatefulWidget {
  const VehicleStatusScreen({
    super.key,
    required this.vehicle,
    this.stage = TripStage.departure,
    this.initialSheetSize,
  });

  final VehicleProfile vehicle;
  final TripStage stage;

  /// Where the sheet was left last time, restored by [TripStore]. Null opens
  /// full height.
  final double? initialSheetSize;

  @override
  State<VehicleStatusScreen> createState() => _VehicleStatusScreenState();
}

class _VehicleStatusScreenState extends State<VehicleStatusScreen>
    with WidgetsBindingObserver {
  /// The shallow stop. The fuel card and 還車 stay on screen here, so
  /// collapsing the sheet means seeing more map rather than losing the
  /// controls.
  static const _minSheet = 0.40;

  /// Fallback for the frame before the media query is known.
  static const _defaultMaxSheet = 0.94;

  /// The tallest the sheet goes: the whole screen less the notification bar.
  /// A fraction of a screen height the widget cannot know until it is in a
  /// tree, so it is recomputed in [didChangeDependencies] — the old fixed 0.96
  /// was more than the status bar leaves on most handsets, which is what put
  /// the header underneath it.
  double _maxSheet = _defaultMaxSheet;

  /// Held as one list rather than rebuilt per frame:
  /// [DraggableScrollableSheet] compares `snapSizes` by identity, and a new
  /// list every build reads to it as "the stops changed" — which schedules a
  /// re-snap after the frame and cancels any scroll animation in flight.
  List<double> _snapSizes = const [_minSheet, _defaultMaxSheet];

  final _sheet = DraggableScrollableController();

  late TripStage _stage = widget.stage;

  /// Where the sheet opens. A restored height is honoured — the driver put it
  /// there — and anything else opens full.
  ///
  /// Resolved in [didChangeDependencies], not in [initState]: it is measured
  /// against [_maxSheet], and [_maxSheet] is not known until there is a media
  /// query to read. Working it out a frame earlier is what had the sheet
  /// opening at the fallback height instead of flush under the status bar.
  double _initialSize = _defaultMaxSheet;

  _StageData get _data => _stages[_stage]!;

  /// False until the sheet's opening height has been settled and written out.
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    final height = media.size.height;
    // 1 − the notification bar, as a fraction.
    final max = height <= 0
        ? _defaultMaxSheet
        : (1 - media.padding.top / height).clamp(_minSheet + 0.02, 1.0);
    if (max != _maxSheet) {
      _maxSheet = max;
      _snapSizes = [_minSheet, max];
    }
    if (_started) return;
    _started = true;
    _initialSize = (widget.initialSheetSize ?? _maxSheet).clamp(
      _minSheet,
      _maxSheet,
    );
    // Idempotent, and it covers both ways onto this screen: a fresh unlock and
    // a cold start that restored one. Whichever it was, the store now agrees
    // with what is on screen.
    TripStore.start(
      plate: widget.vehicle.plate,
      stage: _stage.name,
      sheetSize: _initialSize,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sheet.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The last chance to record where the sheet is before the process may be
    // killed. Drag-end already writes; this covers a swipe-away mid-drag.
    if (state == AppLifecycleState.paused && _sheet.isAttached) {
      TripStore.saveSheet(_sheet.size);
    }
  }

  void _setStage(TripStage stage) {
    setState(() => _stage = stage);
    TripStore.saveStage(stage.name);
  }

  // --- sheet dragging -------------------------------------------------------

  /// Lets the whole dark header act as a drag handle, not just the grabber.
  void _dragSheet(double deltaY) {
    if (!_sheet.isAttached) return;
    final height = MediaQuery.sizeOf(context).height;
    if (height == 0) return;
    _sheet.jumpTo((_sheet.size - deltaY / height).clamp(_minSheet, _maxSheet));
  }

  void _settleSheet(double velocityY) {
    if (!_sheet.isAttached) return;
    final current = _sheet.size;
    final double target;
    if (velocityY < -320) {
      target = _snapSizes.firstWhere(
        (s) => s > current + 0.01,
        orElse: () => _maxSheet,
      );
    } else if (velocityY > 320) {
      target = _snapSizes.lastWhere(
        (s) => s < current - 0.01,
        orElse: () => _minSheet,
      );
    } else {
      target = _snapSizes.reduce(
        (a, b) => (a - current).abs() <= (b - current).abs() ? a : b,
      );
    }
    _sheet
        .animateTo(
          target,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => TripStore.saveSheet(target));
  }

  /// The system back gesture. There is nothing behind this screen to go back
  /// to, so it does the next most useful thing and gets out of the map's way.
  void _handleBack() {
    if (!_sheet.isAttached) return;
    _sheet
        .animateTo(
          _minSheet,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => TripStore.saveSheet(_minSheet));
  }

  Future<void> _return() async {
    final ok = await showReturnChecklistDialog(
      context,
      fuelPercent: _data.fuelPercent,
    );
    if (!mounted || ok != true) return;
    // The checklist is the last thing asked indoors; everything after it is
    // the camera flow.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReturnFlowScreen(vehicle: widget.vehicle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColor.page,
        body: SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(
                child: MapBackdrop(
                  center: DemoPlace.chengKung,
                  zoom: 15.4,
                  // Keep the basemap attribution clear of the collapsed sheet.
                  bottomPadding: MediaQuery.sizeOf(context).height * _minSheet,
                ),
              ),
              DraggableScrollableSheet(
                controller: _sheet,
                initialChildSize: _initialSize,
                minChildSize: _minSheet,
                maxChildSize: _maxSheet,
                snap: true,
                snapSizes: _snapSizes,
                builder: (context, scrollController) =>
                    _sheetBody(scrollController),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetBody(ScrollController scrollController) {
    final data = _data;
    final low = !data.canReturn;
    final accent = low ? AppColor.brand : AppColor.success;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColor.page,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        boxShadow: AppShadow.bottomBar,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        child: Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => _dragSheet(d.primaryDelta ?? 0),
              onVerticalDragEnd: (d) =>
                  _settleSheet(d.velocity.pixelsPerSecond.dy),
              child: VehicleHeaderPanel(
                vehicle: widget.vehicle,
                badgesTrailing: true,
                trailing: _StageMenu(stage: _stage, onChanged: _setStage),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
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
                    values: [
                      ('${data.hours}', '小時'),
                      ('${data.minutes}', '分鐘'),
                    ],
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
            // Page-coloured rather than white: over the grey list a white slab
            // read as a separate panel instead of a footer.
            BottomActionBar(
              background: AppColor.page,
              padding: const EdgeInsets.fromLTRB(
                16,
                12,
                16,
                BottomActionBar.minBottomGap,
              ),
              child: PillButton(label: '還車', onPressed: _return),
            ),
          ],
        ),
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
                size: 19,
                color: AppColor.textPrimary,
              ),
              const SizedBox(width: 9),
              const Text(
                '當前油量',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  color: AppColor.textPrimary,
                ),
              ),
              const Spacer(),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: percent.toDouble()),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text(
                  '${v.round()}%',
                  // Trimmed to the glyphs, so the 40pt numeral's baseline is
                  // the row's baseline rather than the bottom of a line box a
                  // third of which is empty. That empty third is what the
                  // label beside it used to be nudged 2pt up to compensate for.
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  ),
                  style: TextStyle(
                    fontSize: 40,
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
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: accent,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              '實際續航里程將依路況及駕駛方式變動',
              style: TextStyle(fontSize: 11, color: AppColor.textSecondary),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 21, color: AppColor.textPrimary),
          const SizedBox(width: 11),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: AppColor.textPrimary,
            ),
          ),
          const Spacer(),
          // "190 km" and "1 小時 30 分鐘" are each one phrase at two sizes, so
          // each is one paragraph: inline spans share a baseline, where a row
          // of Texts only ever shares the bottom of its line boxes — which is
          // what left the numerals riding high and needed a hand-tuned 3pt
          // nudge under every unit to look almost right.
          Text.rich(
            TextSpan(
              children: [
                for (final (i, (value, unit)) in values.indexed) ...[
                  if (i > 0) const TextSpan(text: ' '),
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColor.warning,
                    ),
                  ),
                  TextSpan(text: ' $unit'),
                ],
              ],
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppColor.textPrimary,
              ),
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

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
                  size: 26,
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
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColor.brandSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  size: 19,
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
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColor.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '隨時查看本車儀表板與各項操作說明',
                      style: TextStyle(
                        fontSize: 11.5,
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
