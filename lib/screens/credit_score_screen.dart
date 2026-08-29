import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../widgets/back_button.dart';

/// 信用分數與會員權益 (Figma: 信用點數 → 信用分數＆獎勵金).
///
/// The Figma board draws four boards for the same screen — PRO / 一般 / 停權 —
/// so the demo keeps them as one screen with a scenario switch in the header,
/// the same affordance 車輛資訊 already uses.
enum CreditScenario { pro, standard, suspended }

class CreditScoreScreen extends StatefulWidget {
  const CreditScoreScreen({super.key, this.scenario = CreditScenario.pro});

  final CreditScenario scenario;

  @override
  State<CreditScoreScreen> createState() => _CreditScoreScreenState();
}

class _CreditScoreScreenState extends State<CreditScoreScreen> {
  late CreditScenario _scenario = widget.scenario;
  int _tab = 0;

  _ScenarioData get _data => _scenarios[_scenario]!;

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final records = _tab == 0 ? data.creditRecords : data.rewardRecords;

    return Scaffold(
      // Figma puts the cards on white; on white they needed a heavy 25% shadow
      // to separate, which is what made the screen read as "cards inside a
      // card". A page-grey ground lets the same cards float on a 10% shadow.
      backgroundColor: AppColor.page,
      body: Column(
        children: [
          _Header(
            data: data,
            scenario: _scenario,
            onScenarioChanged: (s) => setState(() => _scenario = s),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
              children: [
                _MembershipCard(data: data),
                const SizedBox(height: 14),
                // The two cards carry different amounts of text, so the row
                // is pinned to one height instead of each card sizing itself.
                // 88 is the floor rather than the height: on a narrow display
                // 獎勵金兌換 wraps onto a second line and the row has to grow
                // with it.
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 88),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _RewardBalanceCard(points: data.rewardPoints),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(child: _RewardExchangeCard()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _RecordTabs(
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
                const SizedBox(height: 6),
                for (final record in records) _RecordRow(record: record),
                if (records.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Text(
                      '目前沒有紀錄',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColor.textPlaceholder,
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

// ---------------------------------------------------------------- header ---

class _Header extends StatelessWidget {
  const _Header({
    required this.data,
    required this.scenario,
    required this.onScenarioChanged,
  });

  final _ScenarioData data;
  final CreditScenario scenario;
  final ValueChanged<CreditScenario> onScenarioChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColor.sheetDark,
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 8),
      child: Column(
        children: [
          // Same metrics as every other header in the flow: a 44pt target
          // 16pt in from the edge, so the chevron never moves between screens.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: AppBackButton.size,
              // A Stack let the centred title run under the scenario chip once
              // the screen was narrow enough for the two to meet. As a row the
              // title only ever gets the space the chevron and the chip leave,
              // and scales down inside it rather than colliding.
              child: Row(
                children: [
                  AppBackButton(
                    onTap: () => Navigator.of(context).maybePop(),
                    filled: false,
                    color: Colors.white,
                    tooltip: '返回',
                  ),
                  const Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '信用分數與會員權益',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _ScenarioMenu(
                    scenario: scenario,
                    onChanged: onScenarioChanged,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            child: _ScoreCard(data: data),
          ),
        ],
      ),
    );
  }
}

class _ScenarioMenu extends StatelessWidget {
  const _ScenarioMenu({required this.scenario, required this.onChanged});

  final CreditScenario scenario;
  final ValueChanged<CreditScenario> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<CreditScenario>(
      initialValue: scenario,
      onSelected: onChanged,
      tooltip: '切換示範情境',
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final entry in _scenarios.entries)
          PopupMenuItem(value: entry.key, child: Text(entry.value.menuLabel)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _scenarios[scenario]!.chipLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Icon(Icons.expand_more, size: 15, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

/// The score panel.
///
/// Figma drew the axis with the ticks 0·50·60·100·200·300 spread at even
/// pixel steps, which makes the first 60 points occupy a third of the bar and
/// the fill land somewhere the number can't explain. Here the axis is linear
/// 0–300: the fill, the knob and the two threshold notches all sit at their
/// true position, so 235 reads where you'd expect it.
class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.data});

  static const _max = 300.0;
  static const _suspendThreshold = 50.0;
  static const _upgradeThreshold = 200.0;

  final _ScenarioData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColor.sheetPanel,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                '當前信用分數',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${data.score}',
                style: TextStyle(
                  fontSize: 42,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  color: data.scoreIsAlarming ? AppColor.brand : Colors.white,
                ),
              ),
              if (data.tierBadge != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColor.brand,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    data.tierBadge!,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColor.brandSoft,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ScoreAxis(
                  score: data.score.toDouble(),
                  max: _max,
                  notches: const [_suspendThreshold, _upgradeThreshold],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (data.gaugeNoteIcon != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          data.gaugeNoteIcon,
                          size: 13,
                          color: AppColor.warning,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        data.gaugeNote,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
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

class _ScoreAxis extends StatelessWidget {
  const _ScoreAxis({
    required this.score,
    required this.max,
    required this.notches,
  });

  static const _trackHeight = 7.0;
  static const _knob = 14.0;

  final double score;
  final double max;
  final List<double> notches;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double xOf(double value) => (value / max).clamp(0.0, 1.0) * width;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: _knob,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      height: _trackHeight,
                      decoration: BoxDecoration(
                        color: AppColor.sheetDark,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: _trackHeight,
                      width: xOf(score),
                      decoration: BoxDecoration(
                        color: AppColor.brand,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                  // Threshold notches sit on the track itself, so the label
                  // below never has to be read as a scale of its own.
                  for (final notch in notches)
                    Positioned(
                      left: xOf(notch) - 1,
                      top: (_knob - _trackHeight) / 2,
                      child: Container(
                        width: 2,
                        height: _trackHeight,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  Positioned(
                    left: (xOf(score) - _knob / 2).clamp(0.0, width - _knob),
                    child: Container(
                      width: _knob,
                      height: _knob,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: AppShadow.floating,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 14,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned(left: 0, child: _AxisLabel('0')),
                  for (final notch in notches)
                    Positioned(
                      left: xOf(notch) - 12,
                      child: _AxisLabel('${notch.toInt()}'),
                    ),
                  const Positioned(right: 0, child: _AxisLabel('300')),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AxisLabel extends StatelessWidget {
  const _AxisLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: Colors.white70,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- cards ---

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({required this.data});

  final _ScenarioData data;

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _RoundIcon(
            icon: Icons.workspace_premium,
            background: data.hasMembership
                ? AppColor.brandSoft
                : const Color(0xFFE9E9E9),
            foreground: data.hasMembership
                ? AppColor.brand
                : AppColor.sheetDark,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (data.membershipLabel != null) ...[
                  Text(
                    data.membershipLabel!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColor.textPlaceholder,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                _ValueLine(parts: data.membershipValue),
              ],
            ),
          ),
          if (data.orderQuota != null) ...[
            const SizedBox(width: 12),
            Container(width: 1, height: 62, color: AppColor.divider),
            const SizedBox(width: 12),
            Expanded(child: _OrderQuota(quota: data.orderQuota!)),
          ],
        ],
      ),
    );
  }
}

class _OrderQuota extends StatelessWidget {
  const _OrderQuota({required this.quota});

  final _OrderQuotaData quota;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Half a card is not enough for this line at its designed sizes once
        // the display width drops, and none of the three parts can be
        // shortened, so the line scales as a whole.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                '本期訂單',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColor.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${quota.done}',
                      style: const TextStyle(color: AppColor.brand),
                    ),
                    TextSpan(text: '/${quota.total}'),
                  ],
                  style: const TextStyle(
                    fontSize: 19,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: AppColor.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              const Text(
                '筆',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColor.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: quota.done / quota.total,
            minHeight: 5,
            backgroundColor: AppColor.track,
            valueColor: const AlwaysStoppedAnimation(AppColor.brand),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          quota.hint,
          style: const TextStyle(
            fontSize: 11,
            height: 1.3,
            fontWeight: FontWeight.w500,
            color: AppColor.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _RewardBalanceCard extends StatelessWidget {
  const _RewardBalanceCard({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          const _RoundIcon(
            icon: Icons.paid_outlined,
            background: AppColor.brand,
            foreground: Colors.white,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '獎勵金',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColor.textSecondary,
                  ),
                ),
                const SizedBox(height: 1),
                _ValueLine(
                  parts: [
                    _ValuePart(
                      '$points',
                      size: 26,
                      color: AppColor.textPrimary,
                    ),
                    const _ValuePart('點', size: 15, weight: FontWeight.w500),
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

class _RewardExchangeCard extends StatelessWidget {
  const _RewardExchangeCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('獎勵金兌換：清潔・停車場・駕駛時間（示範版）'),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          const _RoundIcon(
            icon: Icons.card_giftcard,
            background: AppColor.brand,
            foreground: Colors.white,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '獎勵金兌換',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColor.textPrimary,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '清潔・停車場・駕駛時間',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                    color: AppColor.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 20,
            color: AppColor.textPlaceholder,
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- record list --

class _RecordTabs extends StatelessWidget {
  const _RecordTabs({required this.index, required this.onChanged});

  static const _labels = ['信用紀錄', '獎勵金紀錄'];

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _labels[i],
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: i == index
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: i == index
                            ? AppColor.brand
                            : AppColor.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 9),
                    // One 3pt rail across both tabs — the Figma版 had a 5pt
                    // red bar sitting 3px above a 2pt grey rail, which read as
                    // a misalignment rather than an indicator.
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: i == index ? AppColor.brand : AppColor.track,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});

  final _Record record;

  @override
  Widget build(BuildContext context) {
    final positive = record.delta > 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColor.divider)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              record.date,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColor.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              record.reason,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColor.textPrimary,
              ),
            ),
          ),
          Text(
            '${positive ? '+' : ''}${record.delta}',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: positive ? AppColor.success : AppColor.brand,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ small parts --

class _Card extends StatelessWidget {
  const _Card({required this.child, required this.padding, this.onTap});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(AppRadius.chip));

    // The shadow has to hang *outside* the Material, not inside it as an Ink
    // decoration: a Material clips its ink features to its own rectangle, so
    // the blur got squared off and the part of it between the rounded corner
    // and that rectangle stayed on screen as a dark notch at each corner.
    return DecoratedBox(
      // 10% / 10px instead of Figma's 25% / 5px: on the grey ground the cards
      // still lift, without the halo that made the screen feel crowded.
      decoration: const BoxDecoration(
        borderRadius: radius,
        boxShadow: AppShadow.card,
      ),
      child: Material(
        color: AppColor.card,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, size: 22, color: foreground),
    );
  }
}

class _ValuePart {
  const _ValuePart(
    this.text, {
    this.size = 18,
    this.color = AppColor.textPrimary,
    this.weight = FontWeight.w700,
  });

  final String text;
  final double size;
  final Color color;
  final FontWeight weight;
}

/// A "剩餘 42 天" style line: mixed sizes on one baseline.
class _ValueLine extends StatelessWidget {
  const _ValueLine({required this.parts});

  final List<_ValuePart> parts;

  @override
  Widget build(BuildContext context) {
    // Bottom-aligned rather than baseline-aligned: baseline alignment cannot
    // be resolved inside IntrinsicHeight, and with these sizes the two read
    // the same. Scaled as a whole for the same reason 本期訂單 is: a value line
    // is one phrase at two sizes, and no part of it can be dropped.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final part in parts)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Text(
                part.text,
                maxLines: 1,
                style: TextStyle(
                  fontSize: part.size,
                  height: 1.1,
                  fontWeight: part.weight,
                  color: part.color,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ data ---

class _Record {
  const _Record(this.date, this.reason, this.delta);

  final String date;
  final String reason;
  final int delta;
}

class _OrderQuotaData {
  const _OrderQuotaData({
    required this.done,
    required this.total,
    required this.hint,
  });

  final int done;
  final int total;
  final String hint;
}

class _ScenarioData {
  const _ScenarioData({
    required this.menuLabel,
    required this.chipLabel,
    required this.score,
    required this.gaugeNote,
    required this.membershipValue,
    required this.rewardPoints,
    required this.creditRecords,
    required this.rewardRecords,
    this.tierBadge,
    this.membershipLabel,
    this.orderQuota,
    this.gaugeNoteIcon,
    this.hasMembership = true,
    this.scoreIsAlarming = false,
  });

  final String menuLabel;
  final String chipLabel;
  final int score;
  final String gaugeNote;
  final IconData? gaugeNoteIcon;
  final String? tierBadge;
  final String? membershipLabel;
  final List<_ValuePart> membershipValue;
  final _OrderQuotaData? orderQuota;
  final int rewardPoints;
  final List<_Record> creditRecords;
  final List<_Record> rewardRecords;
  final bool hasMembership;
  final bool scoreIsAlarming;
}

const _proCreditRecords = <_Record>[
  _Record('2026/07/01', '完成訂單', 1),
  _Record('2026/06/25', '車輛歷程留言', 1),
  _Record('2026/06/25', '完成訂單', 1),
  _Record('2026/05/06', '完成訂單', 1),
  _Record('2026/04/22', '完成訂單', 1),
];

const _proRewardRecords = <_Record>[
  _Record('2026/07/01', 'PRO 會員每月獎勵', 1),
  _Record('2026/06/25', 'PRO 會員每月獎勵', 1),
  _Record('2026/06/25', 'PRO 會員每月獎勵', 1),
  _Record('2026/05/06', 'PRO 會員每月獎勵', 1),
  _Record('2026/04/22', 'PRO 會員每月獎勵', 1),
];

final _scenarios = <CreditScenario, _ScenarioData>{
  CreditScenario.pro: const _ScenarioData(
    menuLabel: 'PRO 會員（235 分）',
    chipLabel: 'PRO 會員',
    score: 235,
    tierBadge: 'PRO',
    gaugeNote: '距離升級 訂閱制+ 還差 65 分',
    membershipLabel: 'PRO 會員效期',
    membershipValue: [
      _ValuePart('剩餘', size: 17),
      _ValuePart('42', size: 26, color: AppColor.brand),
      _ValuePart('天', size: 17),
    ],
    orderQuota: _OrderQuotaData(done: 6, total: 10, hint: '再完成 4 筆訂單即可續期 3 個月'),
    rewardPoints: 25,
    creditRecords: _proCreditRecords,
    rewardRecords: _proRewardRecords,
  ),
  CreditScenario.standard: const _ScenarioData(
    menuLabel: '一般會員（65 分）',
    chipLabel: '一般會員',
    score: 65,
    gaugeNote: '低於 50 分將停權一個月',
    gaugeNoteIcon: Icons.warning_amber_rounded,
    membershipValue: [_ValuePart('尚未獲得會員權益', size: 17)],
    rewardPoints: 1,
    hasMembership: false,
    creditRecords: [_Record('2026/01/04', '成功註冊會員', 1)],
    rewardRecords: [_Record('2026/01/04', '成功註冊會員', 1)],
  ),
  CreditScenario.suspended: const _ScenarioData(
    menuLabel: '已停權（49 分）',
    chipLabel: '已停權',
    score: 49,
    scoreIsAlarming: true,
    gaugeNote: '目前已累積停權一次，第三次將終身停權',
    gaugeNoteIcon: Icons.error_outline,
    membershipLabel: '停權累積',
    membershipValue: [
      _ValuePart('停權次數', size: 17),
      _ValuePart('1/3', size: 26, color: AppColor.brand),
      _ValuePart('次', size: 17),
    ],
    rewardPoints: 1,
    hasMembership: false,
    creditRecords: [
      _Record('2026/03/12', '逾時還車', -10),
      _Record('2026/02/20', '未依規定停放', -5),
      _Record('2026/01/04', '成功註冊會員', 1),
    ],
    rewardRecords: [_Record('2026/01/04', '成功註冊會員', 1)],
  ),
};
