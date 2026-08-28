import 'package:flutter/material.dart';

import '../data/vehicle.dart';
import '../design/tokens.dart';
import '../widgets/dark_sheet.dart';
import '../widgets/map_backdrop.dart';
import '../widgets/pill_button.dart';
import 'vehicle_status_screen.dart';

/// 安心上路輔助 — interactive walkthrough of the car's controls.
///
/// Tapping a numbered marker on the diagram scrolls the list to that control
/// and vice-versa, so the picture and the explanation always stay in sync.
class SafeDriveAssistScreen extends StatefulWidget {
  const SafeDriveAssistScreen({
    super.key,
    required this.vehicle,
    this.initialSectionId,
  });

  final VehicleProfile vehicle;
  final String? initialSectionId;

  @override
  State<SafeDriveAssistScreen> createState() => _SafeDriveAssistScreenState();
}

class _SafeDriveAssistScreenState extends State<SafeDriveAssistScreen> {
  late String _sectionId =
      widget.initialSectionId ?? widget.vehicle.assistSections.first.id;
  int? _selected;
  final _listController = ScrollController();

  AssistSection get _section => widget.vehicle.sectionById(_sectionId);

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  void _selectSection(String id) {
    if (id == _sectionId) return;
    setState(() {
      _sectionId = id;
      _selected = null;
    });
    if (_listController.hasClients) _listController.jumpTo(0);
  }

  void _selectItem(int number) {
    setState(() => _selected = _selected == number ? null : number);
    if (_selected == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _rowKey(number).currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.15,
      );
    });
  }

  GlobalObjectKey _rowKey(int number) => GlobalObjectKey('$_sectionId-$number');

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: MapBackdrop(
                center: DemoPlace.chengKung,
                zoom: 15.4,
                interactive: false,
                showUserDot: false,
              ),
            ),
            Positioned.fill(
              top: topInset + 96,
              child: Column(
                children: [
                  _header(),
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      child: Column(
                        children: [
                          _chipRow(),
                          Expanded(child: _body()),
                          _footer(),
                        ],
                      ),
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

  Widget _header() {
    return DarkSheetSurface(
      topPadding: 10,
      child: DarkSheetHeader(
        title: '安心上路輔助',
        subtitle: '自由點選想了解的車內設備',
        padding: const EdgeInsets.fromLTRB(24, 0, 16, 20),
        trailing: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(
            Icons.close_rounded,
            color: Colors.white70,
            size: 24,
          ),
          tooltip: '關閉',
        ),
      ),
    );
  }

  Widget _chipRow() {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        itemCount: widget.vehicle.assistSections.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = widget.vehicle.assistSections[i];
          final active = s.id == _sectionId;
          return GestureDetector(
            onTap: () => _selectSection(s.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColor.brandSoft : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: active
                      ? AppColor.brand.withValues(alpha: 0.35)
                      : const Color(0xFFE4E4E8),
                ),
                boxShadow: active ? null : AppShadow.floating,
              ),
              child: Text(
                s.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? AppColor.brand : AppColor.textPrimary,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body() {
    final section = _section;
    return LayoutBuilder(
      builder: (context, c) {
        // Keep the diagram pinned above the list so the picture and the
        // explanation stay on screen together, and cap it on short displays.
        final diagramMax = (c.maxHeight * 0.46).clamp(150.0, 300.0);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 4, 15, 12),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: diagramMax),
                child: _DiagramCard(
                  section: section,
                  selected: _selected,
                  onSelectItem: _selectItem,
                  onSelectSection: _selectSection,
                ),
              ),
            ),
            Expanded(
              child: section.isOverview
                  ? SingleChildScrollView(child: _overviewHint())
                  : ListView.separated(
                      controller: _listController,
                      padding: const EdgeInsets.fromLTRB(15, 0, 15, 18),
                      itemCount: section.items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final item = section.items[i];
                        return _ItemRow(
                          key: _rowKey(item.number),
                          item: item,
                          selected: _selected == item.number,
                          onTap: () => _selectItem(item.number),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _overviewHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 4, 15, 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColor.subtle,
          borderRadius: BorderRadius.circular(AppRadius.card),
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
                Icons.touch_app_rounded,
                size: 19,
                color: AppColor.brand,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '點選圖上的標籤，查看該區域的完整操作說明。',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: AppColor.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: AppShadow.bottomBar,
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        14 + MediaQuery.paddingOf(context).bottom,
      ),
      child: PillButton(
        label: '關閉安心上路輔助',
        outlined: true,
        textStyle: AppText.bodyM.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        onPressed: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => VehicleStatusScreen(vehicle: widget.vehicle),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Diagram
// ---------------------------------------------------------------------------

class _DiagramCard extends StatelessWidget {
  const _DiagramCard({
    required this.section,
    required this.selected,
    required this.onSelectItem,
    required this.onSelectSection,
  });

  final AssistSection section;
  final int? selected;
  final ValueChanged<int> onSelectItem;
  final ValueChanged<String> onSelectSection;

  /// The card the marker positions were authored against in Figma.
  static const _authoredCard = Size(372, 243);

  /// Where the artwork actually lands inside [_authoredCard].
  Rect get _drawnRect {
    final rect = section.layout.imageRect;
    if (rect != null || section.layout.boxWidthFactor != 1) {
      final w = _authoredCard.width * section.layout.boxWidthFactor;
      return Rect.fromLTWH(
        (_authoredCard.width - w) / 2,
        0,
        w,
        _authoredCard.height,
      );
    }
    final aspect = section.contentAspect;
    if (aspect == null) return Offset.zero & _authoredCard;

    final cardAspect = _authoredCard.width / _authoredCard.height;
    if (aspect >= cardAspect) {
      final h = _authoredCard.width / aspect;
      return Rect.fromLTWH(
        0,
        (_authoredCard.height - h) / 2,
        _authoredCard.width,
        h,
      );
    }
    final w = _authoredCard.height * aspect;
    return Rect.fromLTWH(
      (_authoredCard.width - w) / 2,
      0,
      w,
      _authoredCard.height,
    );
  }

  /// Card-space fraction → artwork-space fraction.
  Offset _remap(Offset p) {
    final r = _drawnRect;
    return Offset(
      (p.dx * _authoredCard.width - r.left) / r.width,
      (p.dy * _authoredCard.height - r.top) / r.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final drawn = _drawnRect;
    final aspect = section.isOverview
        ? _authoredCard.width / _authoredCard.height
        : drawn.width / drawn.height;

    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadow.cardStrong,
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: aspect,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final h = c.maxHeight;
              return Stack(
                children: [
                  Positioned.fill(child: _image()),
                  if (section.isOverview)
                    for (final hs in section.hotspots)
                      Positioned(
                        left: hs.position.dx * w,
                        top: hs.position.dy * h,
                        child: FractionalTranslation(
                          // Anchor to the pill's edge near the card border so it
                          // never gets clipped.
                          translation: Offset(
                            hs.position.dx < 0.16
                                ? -0.04
                                : (hs.position.dx > 0.84 ? -0.96 : -0.5),
                            -0.5,
                          ),
                          child: _HotspotPill(
                            label: hs.label,
                            onTap: () => onSelectSection(hs.sectionId),
                          ),
                        ),
                      )
                  else
                    for (final item in section.items)
                      for (final mark in item.marks)
                        Builder(
                          builder: (context) {
                            final p = _remap(mark);
                            return Positioned(
                              left: p.dx * w,
                              top: p.dy * h,
                              child: FractionalTranslation(
                                translation: const Offset(-0.5, -0.5),
                                child: _NumberMarker(
                                  number: item.number,
                                  active: selected == item.number,
                                  dimmed:
                                      selected != null &&
                                      selected != item.number,
                                  onTap: () => onSelectItem(item.number),
                                ),
                              ),
                            );
                          },
                        ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _image() {
    final rect = section.layout.imageRect;
    if (rect == null) {
      return Image.asset(section.image, fit: BoxFit.cover);
    }
    // Reproduce the crop authored in Figma.
    return LayoutBuilder(
      builder: (context, c) => ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: rect.left * c.maxWidth,
              top: rect.top * c.maxHeight,
              width: rect.width * c.maxWidth,
              height: rect.height * c.maxHeight,
              child: Image.asset(section.image, fit: BoxFit.fill),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberMarker extends StatelessWidget {
  const _NumberMarker({
    required this.number,
    required this.active,
    required this.dimmed,
    required this.onTap,
  });

  final int number;
  final bool active;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (active) const _Halo(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                width: active ? 25 : 19,
                height: active ? 25 : 19,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? AppColor.brand
                      : AppColor.brandBright.withValues(
                          alpha: dimmed ? 0.42 : 1,
                        ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: active ? 2.4 : 1.6,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Text(
                      '$number',
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Halo extends StatefulWidget {
  const _Halo();

  @override
  State<_Halo> createState() => _HaloState();
}

class _HaloState extends State<_Halo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Container(
          width: 24 + 20 * t,
          height: 24 + 20 * t,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColor.brand.withValues(alpha: (1 - t) * 0.55),
              width: 2,
            ),
          ),
        );
      },
    );
  }
}

class _HotspotPill extends StatelessWidget {
  const _HotspotPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColor.brandBright,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.chevron_right, size: 13, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AssistItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: selected ? AppColor.brandSoft : AppColor.subtle,
          borderRadius: BorderRadius.circular(AppRadius.checklist),
          border: Border.all(
            color: selected
                ? AppColor.brand.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: selected ? AppColor.brand : AppColor.brandBright,
                shape: BoxShape.circle,
              ),
              child: FittedBox(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Text(
                    '${item.number}',
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: AppColor.textInk,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.55,
                      color: AppColor.textMuted,
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
