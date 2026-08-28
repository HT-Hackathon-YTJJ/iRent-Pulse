import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/vehicle.dart';
import '../design/tokens.dart';
import '../widgets/pill_button.dart';
import 'booking_confirm_dialog.dart';

enum _BookingTab { history, spec, maintenance }

extension on _BookingTab {
  String get label => switch (this) {
    _BookingTab.history => '租用履歷',
    _BookingTab.spec => '規格配備',
    _BookingTab.maintenance => '保養紀錄',
  };
}

/// Everything the booking sheet shows below its dark vehicle card: the photo
/// strip, the 租用履歷 / 規格配備 / 保養紀錄 tabs and the pinned price footer.
///
/// The card itself comes in as [header] because the host owns it — on the pin
/// screen that same card is the swipeable deck, and pulling the deck up is
/// literally this body growing underneath it. That is why this is a body and
/// not a sheet: there is only ever one sheet on screen.
class VehicleBookingBody extends StatefulWidget {
  const VehicleBookingBody({
    super.key,
    required this.listing,
    required this.controller,
    required this.header,
    required this.onBooked,
    this.reveal = 1,
  });

  final VehicleListing listing;

  /// Scroll controller handed over by the host's [DraggableScrollableSheet].
  final ScrollController controller;

  /// The dark vehicle card that sits above the content.
  final Widget header;

  /// Called once the confirmation dialog has been accepted.
  final VoidCallback onBooked;

  /// 0 while the host is collapsed to just the header, 1 once it is open.
  /// Fades the content in and grows the footer out of the bottom edge.
  final double reveal;

  @override
  State<VehicleBookingBody> createState() => _VehicleBookingBodyState();
}

class _VehicleBookingBodyState extends State<VehicleBookingBody> {
  static const _startLabel = '8/18 (二) 15:30';
  static const _endLabels = ['16:30', '17:30', '18:30'];

  _BookingTab _tab = _BookingTab.history;
  bool _assurance = false;
  int _hours = 1;

  VehicleListing get _listing => widget.listing;

  int get _estimate => _listing.estimate(hours: _hours, assurance: _assurance);

  void _cycleDuration() =>
      setState(() => _hours = _hours % _endLabels.length + 1);

  Future<void> _book() async {
    final confirmed = await showBookingConfirmDialog(
      context,
      listing: _listing,
      hours: _hours,
      assurance: _assurance,
    );
    if (!mounted || confirmed != true) return;
    widget.onBooked();
  }

  void _showSubscription() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('訂閱制方案為 Demo 展示，暫未串接'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reveal = widget.reveal;

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            controller: widget.controller,
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: widget.header),
              SliverOpacity(
                opacity: reveal,
                sliver: SliverToBoxAdapter(child: _photoStrip()),
              ),
              SliverOpacity(
                opacity: reveal,
                sliver: SliverToBoxAdapter(child: _lastUsed()),
              ),
              SliverOpacity(
                opacity: reveal,
                sliver: SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarHeader(
                    tab: _tab,
                    onChanged: (t) => setState(() => _tab = t),
                  ),
                ),
              ),
              SliverOpacity(
                opacity: reveal,
                sliver: SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  sliver: _tabContent(),
                ),
              ),
            ],
          ),
        ),
        // The footer slides out of the bottom edge instead of appearing whole,
        // so the collapsed deck shows nothing but the card.
        if (reveal > 0)
          ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: reveal,
              child: Opacity(opacity: reveal, child: _footer()),
            ),
          ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Photos + last use
  // -------------------------------------------------------------------------

  Widget _photoStrip() {
    final photos = _listing.vehicle.photos;
    if (photos.isEmpty) return const SizedBox(height: 12);

    return SizedBox(
      height: 138,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) => _PhotoTile(photo: photos[i]),
      ),
    );
  }

  Widget _lastUsed() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          '上次使用時間：${_listing.lastUsedOn}',
          style: const TextStyle(
            fontSize: 12,
            color: AppColor.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tabs
  // -------------------------------------------------------------------------

  Widget _tabContent() {
    switch (_tab) {
      case _BookingTab.history:
        final reviews = _listing.vehicle.reviews;
        return SliverList.separated(
          itemCount: reviews.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _ReviewCard(review: reviews[i]),
        );
      case _BookingTab.spec:
        return SliverToBoxAdapter(
          child: _InfoTable(rows: _listing.vehicle.equipment),
        );
      case _BookingTab.maintenance:
        final records = _listing.vehicle.maintenance;
        return SliverList.separated(
          itemCount: records.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _MaintenanceCard(record: records[i]),
        );
    }
  }

  // -------------------------------------------------------------------------
  // Pinned footer
  // -------------------------------------------------------------------------

  Widget _footer() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: AppShadow.bottomBar,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _subscriptionBanner(),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              math.max(14.0, MediaQuery.paddingOf(context).bottom),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _assuranceRow(),
                const SizedBox(height: 12),
                _timeRow(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _priceBlock()),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PillButton(
                        label: _listing.mode.bookLabel,
                        maxWidth: 200,
                        textStyle: AppText.button.copyWith(fontSize: 16),
                        onPressed: _book,
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

  Widget _subscriptionBanner() {
    return Material(
      color: AppColor.warningSoft,
      child: InkWell(
        onTap: _showSubscription,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
          child: Row(
            children: [
              const Icon(
                Icons.local_offer_rounded,
                size: 16,
                color: AppColor.warning,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '訂閱制方案平假日用車都優惠，'),
                      TextSpan(
                        text: '開始免費試用！',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColor.warningText,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: AppColor.warningText,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColor.warningText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _assuranceRow() {
    return Row(
      children: [
        const Icon(
          Icons.verified_user_rounded,
          size: 17,
          color: AppColor.accentBlue,
        ),
        const SizedBox(width: 7),
        const Text(
          '選用安心服務',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColor.textPrimary,
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.info_outline, size: 14, color: AppColor.textSecondary),
        const Spacer(),
        Text(
          '＋\$${_listing.assuranceRate} / 趟',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: _assurance ? AppColor.textPrimary : AppColor.textSecondary,
          ),
        ),
        const SizedBox(width: 10),
        _Toggle(
          value: _assurance,
          onChanged: (v) => setState(() => _assurance = v),
        ),
      ],
    );
  }

  Widget _timeRow() {
    return Row(
      children: [
        Expanded(child: _TimeChip(label: _startLabel)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Icon(
            Icons.arrow_forward,
            size: 15,
            color: AppColor.textSecondary,
          ),
        ),
        Expanded(
          child: _TimeChip(
            label: '8/18 (二) ${_endLabels[_hours - 1]}',
            onTap: _cycleDuration,
          ),
        ),
      ],
    );
  }

  Widget _priceBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '還車時付款',
          style: TextStyle(fontSize: 11, color: AppColor.textSecondary),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 3),
              child: Text(
                '預估',
                style: TextStyle(fontSize: 12.5, color: AppColor.textSecondary),
              ),
            ),
            const SizedBox(width: 5),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                '\$$_estimate',
                key: ValueKey(_estimate),
                style: AppText.displayAmount.copyWith(
                  fontSize: 25,
                  color: AppColor.textInk,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Padding(
              padding: EdgeInsets.only(bottom: 3),
              child: Icon(
                Icons.info_outline,
                size: 13,
                color: AppColor.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo});

  final VehiclePhoto photo;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 124,
        color: AppColor.subtle,
        child: Column(
          children: [
            Expanded(
              child: Image.asset(
                photo.asset,
                width: double.infinity,
                fit: photo.fit,
                alignment: photo.alignment,
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: Colors.white,
              child: Text(
                photo.caption,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColor.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pinned tab row. Reuses the chip language of the 安心上路輔助 sheet.
class _TabBarHeader extends SliverPersistentHeaderDelegate {
  _TabBarHeader({required this.tab, required this.onChanged});

  final _BookingTab tab;
  final ValueChanged<_BookingTab> onChanged;

  static const _height = 54.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      height: _height,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          for (final t in _BookingTab.values) ...[
            if (t != _BookingTab.values.first) const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t == tab ? AppColor.brandSoft : Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                      color: t == tab
                          ? AppColor.brand.withValues(alpha: 0.35)
                          : const Color(0xFFE4E4E8),
                    ),
                  ),
                  child: Text(
                    t.label,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: t == tab ? FontWeight.w700 : FontWeight.w500,
                      color: t == tab ? AppColor.brand : AppColor.textPrimary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarHeader old) => old.tab != tab;
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final RentalReview review;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      decoration: BoxDecoration(
        color: AppColor.subtle,
        borderRadius: BorderRadius.circular(AppRadius.checklist),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.person, size: 14, color: AppColor.textSecondary),
              const SizedBox(width: 6),
              Text(
                review.date,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColor.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            review.text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppColor.textPrimary,
            ),
          ),
          if (review.reply != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColor.brandSoft,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.support_agent_rounded,
                    size: 15,
                    color: AppColor.brand,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      review.reply!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: AppColor.brand,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MaintenanceCard extends StatelessWidget {
  const _MaintenanceCard({required this.record});

  final MaintenanceRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      decoration: BoxDecoration(
        color: AppColor.subtle,
        borderRadius: BorderRadius.circular(AppRadius.checklist),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColor.successSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.build_rounded,
              size: 16,
              color: AppColor.successText,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      record.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColor.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      record.date,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColor.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  record.detail,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
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

/// Label / value table, matching the spec table of the 車輛規格 sheet.
class _InfoTable extends StatelessWidget {
  const _InfoTable({required this.rows});

  final List<SpecRow> rows;

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
          for (var i = 0; i < rows.length; i++)
            Container(
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : const Border(
                        top: BorderSide(color: Color(0xFFE8E8EC), width: 1),
                      ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 76,
                    child: Text(
                      rows[i].label,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: AppColor.textSecondary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      rows[i].value,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                        color: AppColor.textPrimary,
                        letterSpacing: 0.4,
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

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColor.subtle,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: AppColor.accentBlue,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.expand_more_rounded,
                  size: 15,
                  color: AppColor.accentBlue,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 46,
        height: 27,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? AppColor.brand : AppColor.track,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 21,
            height: 21,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
