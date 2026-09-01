import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../widgets/back_button.dart';
import 'home_map_screen.dart';

/// 訂單明細 (Figma 1010:6493) — where the 分支A 通知 lands.
///
/// The push says the cabin was clean and the credit score is unchanged; this is
/// the page that shows the driver what that actually cost them. It is
/// deliberately the *whole* receipt rather than a damage report: the return is
/// over, the interesting number is the bill, and the credit line at the bottom
/// is the one place the check's outcome shows up as something the driver keeps.
///
/// Leaving it goes all the way back to the map at its opening position rather
/// than one step back up whatever stack got here. A notification tap can arrive
/// with no history behind it at all, and the trip that produced this order is
/// finished — there is nothing behind this page to return to except the start.
class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, this.order = OrderSummary.demo});

  final OrderSummary order;

  static Route<void> route({OrderSummary order = OrderSummary.demo}) =>
      MaterialPageRoute<void>(builder: (_) => OrderDetailScreen(order: order));

  void _back(BuildContext context) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    HomeMapScreen.resetToStart?.call();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back(context);
      },
      child: Scaffold(
        backgroundColor: AppColor.page,
        body: Column(
          children: [
            _Header(order: order, onBack: () => _back(context)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  _Section(
                    title: '訂單資訊',
                    note: '(${order.orderNo})',
                    action: '查看合約',
                    child: _VehicleCard(order: order),
                  ),
                  _Section(
                    title: '付款資訊',
                    note: '(${order.plan})',
                    child: _PaymentCard(order: order),
                  ),
                  _Section(
                    title: '信用分數',
                    action: '查看完整記錄',
                    child: _CreditCard(order: order),
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

// ---------------------------------------------------------------- header ---

class _Header extends StatelessWidget {
  const _Header({required this.order, required this.onBack});

  final OrderSummary order;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColor.sheetDark,
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 8,
        bottom: 18,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: AppBackButton.size,
              child: Row(
                children: [
                  AppBackButton(
                    onTap: onBack,
                    filled: false,
                    color: Colors.white,
                    tooltip: '回到地圖',
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        '訂單明細',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: AppBackButton.size,
                    child: Icon(
                      Icons.more_horiz,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            order.total,
            style: const TextStyle(
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppColor.sheetDarkDeep,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              order.window,
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _HeaderStat(
                      value: order.duration,
                      label: '使用時數',
                    ),
                  ),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Colors.white24,
                  ),
                  Expanded(
                    child: _HeaderStat(
                      value: order.distance,
                      label: '里程數',
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

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColor.textOnDark),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- sections ---

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.note,
    this.action,
  });

  final String title;
  final String? note;
  final String? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      text: title,
                      children: [
                        if (note != null)
                          TextSpan(
                            text: ' $note',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColor.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColor.textPrimary,
                    ),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    action!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColor.accentBlue,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _Card(child: child),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColor.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
      boxShadow: AppShadow.card,
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: child,
    ),
  );
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(order.carImage, height: 62, fit: BoxFit.contain),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(child: Divider(color: AppColor.divider)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                order.plate,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColor.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const Expanded(child: Divider(color: AppColor.divider)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(
              Icons.accessible_forward,
              size: 17,
              color: AppColor.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                order.carModel,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColor.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColor.subtle,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                order.carState,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColor.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: AppColor.subtle,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.location_on,
                size: 15,
                color: AppColor.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                order.station,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColor.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final line in order.charges) ...[
          _Line(
            label: line.label,
            value: line.value,
            highlight: line.expandable,
            trailing: line.expandable
                ? const Icon(
                    Icons.expand_more,
                    size: 17,
                    color: AppColor.accentBlue,
                  )
                : null,
          ),
          const SizedBox(height: 14),
        ],
        const Divider(height: 1, color: AppColor.divider),
        const SizedBox(height: 14),
        _Line(label: '訂單金額', value: order.total, bold: true),
      ],
    );
  }
}

class _CreditCard extends StatelessWidget {
  const _CreditCard({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Line(
          label: '完成訂單',
          value: order.creditDelta,
          valueColor: AppColor.successText,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text(
              '當前信用分數',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColor.textPrimary,
              ),
            ),
            if (order.tierBadge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: AppColor.brand,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  order.tierBadge!,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColor.brandSoft,
                  ),
                ),
              ),
            ],
            const Spacer(),
            Text(
              '${order.creditScore}',
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppColor.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.bold = false,
    this.highlight = false,
    this.valueColor,
    this.trailing,
  });

  final String label;
  final String value;
  final bool bold;

  /// The blue 計費時數 row, which is a link rather than a charge.
  final bool highlight;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColor.accentBlue : AppColor.textPrimary;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: bold ? 15 : 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 17 : 14,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: valueColor ?? color,
          ),
        ),
        ?trailing,
      ],
    );
  }
}

// ------------------------------------------------------------------ data ---

class ChargeLine {
  const ChargeLine(this.label, this.value, {this.expandable = false});

  final String label;
  final String value;

  /// 計費時數 carries a disclosure chevron on the board; it is a breakdown of
  /// the row above it rather than a charge of its own.
  final bool expandable;
}

/// One finished rental, as 訂單明細 renders it.
///
/// Values are the board's own (Figma 1010:6493). A real build fills this from
/// `GET /v1/orders/{id}`, which the backend already serves for 客服複核 — the
/// billing lines are the only fields it would have to grow.
class OrderSummary {
  const OrderSummary({
    required this.orderNo,
    required this.total,
    required this.window,
    required this.duration,
    required this.distance,
    required this.plate,
    required this.carModel,
    required this.carImage,
    required this.carState,
    required this.station,
    required this.plan,
    required this.charges,
    required this.creditDelta,
    required this.creditScore,
    this.tierBadge,
  });

  final String orderNo;
  final String total;
  final String window;
  final String duration;
  final String distance;
  final String plate;
  final String carModel;
  final String carImage;
  final String carState;
  final String station;
  final String plan;
  final List<ChargeLine> charges;
  final String creditDelta;
  final int creditScore;
  final String? tierBadge;

  static const demo = OrderSummary(
    orderNo: 'H44864911',
    total: r'$2,100',
    window: '10/11 10:40 – 10/11 16:41',
    duration: '0天6時0分',
    distance: '139.0km',
    plate: 'RDX-1073',
    carModel: 'TOYOTA Aqua',
    carImage: 'assets/images/car_corolla_cross.png',
    carState: '候租中',
    station: 'iRent信義取車停車場',
    plan: 'iRent同站專案',
    charges: [
      ChargeLine('車輛租金', r'$1,025'),
      ChargeLine('計費時數(不含逾時)', '0天5時0分', expandable: true),
      ChargeLine('里程費用', r'$445'),
      ChargeLine('安心服務', r'$330'),
      ChargeLine('逾時費用(0天1時0分)', r'$300'),
    ],
    creditDelta: '+1',
    creditScore: 235,
    tierBadge: 'PRO',
  );
}
