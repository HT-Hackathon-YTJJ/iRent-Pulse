import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/vehicle.dart';
import '../design/tokens.dart';
import '../widgets/dark_sheet.dart';
import '../widgets/map_backdrop.dart';
import 'vehicle_status_screen.dart';

/// 安心上路輔助 — interactive walkthrough of the car's controls.
///
/// Presented as a Material draggable sheet over the map: it can be pulled
/// between 40% and 94% of the screen, snaps to three stops, and can never be
/// flung away — closing is deliberate, through the ✕ in the header.
class SafeDriveAssistScreen extends StatefulWidget {
  const SafeDriveAssistScreen({
    super.key,
    required this.vehicle,
    this.initialSectionId,
    this.replaceWithStatus = false,
  });

  final VehicleProfile vehicle;
  final String? initialSectionId;

  /// True when the sheet is the last step of the unlock flow: closing it moves
  /// on to 車輛資訊 instead of popping back.
  final bool replaceWithStatus;

  @override
  State<SafeDriveAssistScreen> createState() => _SafeDriveAssistScreenState();
}

class _SafeDriveAssistScreenState extends State<SafeDriveAssistScreen> {
  static const _minSheet = 0.40;
  static const _midSheet = 0.72;
  static const _maxSheet = 0.94;
  static const _snapSizes = <double>[_minSheet, _midSheet, _maxSheet];

  /// Fixed chrome above the diagram, so the column can never overflow.
  static const _headerHeight = 74.0;
  static const _chipsHeight = 48.0;
  static const _minListHeight = 92.0;
  static const _minDiagramHeight = 130.0;

  final _sheet = DraggableScrollableController();
  ScrollController? _scroll;

  late String _sectionId =
      widget.initialSectionId ?? widget.vehicle.assistSections.first.id;
  int? _selected;

  AssistSection get _section => widget.vehicle.sectionById(_sectionId);

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  void _close() {
    if (widget.replaceWithStatus) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VehicleStatusScreen(vehicle: widget.vehicle),
        ),
      );
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _selectSection(String id) {
    if (id == _sectionId) return;
    setState(() {
      _sectionId = id;
      _selected = null;
    });
    if (_scroll?.hasClients ?? false) _scroll!.jumpTo(0);
    _expandAtLeast(_midSheet);
  }

  void _selectItem(int number) {
    setState(() => _selected = _selected == number ? null : number);
    if (_selected == null) return;
    _expandAtLeast(_midSheet);
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

  // --- sheet dragging -------------------------------------------------------

  void _expandAtLeast(double size) {
    if (!_sheet.isAttached || _sheet.size >= size - 0.01) return;
    _sheet.animateTo(
      size,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// Lets the whole header act as a drag handle, not just the grabber.
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
    _sheet.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  // --- build ----------------------------------------------------------------

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
                zoom: 15.4,
                interactive: false,
                // Keep the basemap attribution clear of the collapsed sheet.
                bottomPadding: MediaQuery.sizeOf(context).height * _minSheet,
              ),
            ),
            DraggableScrollableSheet(
              controller: _sheet,
              initialChildSize: _midSheet,
              minChildSize: _minSheet,
              maxChildSize: _maxSheet,
              snap: true,
              snapSizes: _snapSizes,
              builder: (context, scrollController) {
                _scroll = scrollController;
                return _sheetBody(scrollController);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetBody(ScrollController scrollController) {
    final section = _section;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        boxShadow: AppShadow.bottomBar,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            // The diagram absorbs whatever height is left once the header, the
            // chips and one list row are accounted for. Collapsed all the way
            // down there is no room for it, so it steps aside and the sheet
            // reads as title + tabs + text.
            final free = c.maxHeight - _headerHeight - _chipsHeight;
            final diagramHeight = (free - _minListHeight).clamp(
              0.0,
              math.min(c.maxHeight * 0.44, 268.0),
            );
            final showDiagram = diagramHeight >= _minDiagramHeight;

            return Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (d) => _dragSheet(d.primaryDelta ?? 0),
                  onVerticalDragEnd: (d) =>
                      _settleSheet(d.velocity.pixelsPerSecond.dy),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _header(),
                      ColoredBox(
                        color: Colors.white,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _chipRow(),
                            if (showDiagram)
                              SizedBox(
                                height: diagramHeight + 14,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    15,
                                    0,
                                    15,
                                    14,
                                  ),
                                  child: _DiagramCard(
                                    section: section,
                                    selected: _selected,
                                    onSelectItem: _selectItem,
                                    onSelectSection: _selectSection,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ColoredBox(
                    color: Colors.white,
                    child: section.isOverview
                        ? ListView(
                            controller: scrollController,
                            padding: EdgeInsets.fromLTRB(
                              15,
                              showDiagram ? 0 : 6,
                              15,
                              20 + bottomInset,
                            ),
                            children: [_overviewHint()],
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: EdgeInsets.fromLTRB(
                              15,
                              showDiagram ? 0 : 6,
                              15,
                              20 + bottomInset,
                            ),
                            itemCount: section.items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
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
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      height: _headerHeight,
      decoration: const BoxDecoration(
        color: AppColor.sheetDark,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 10, bottom: 12),
            child: SheetGrabber(),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 10, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '安心上路輔助',
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: IconButton(
                      onPressed: _close,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      splashRadius: 20,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                      tooltip: '關閉安心上路輔助',
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

  Widget _chipRow() {
    return SizedBox(
      height: _chipsHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
        itemCount: widget.vehicle.assistSections.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, i) {
          final s = widget.vehicle.assistSections[i];
          final active = s.id == _sectionId;
          return GestureDetector(
            onTap: () => _selectSection(s.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? AppColor.brand : AppColor.textPrimary,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _overviewHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColor.subtle,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColor.brandSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.touch_app_rounded,
              size: 17,
              color: AppColor.brand,
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Text(
              '點選圖上的標籤，查看該區域的完整操作說明。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColor.textMuted,
              ),
            ),
          ),
        ],
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
        width: 32,
        height: 32,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (active) const _Halo(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                width: active ? 24 : 18,
                height: active ? 24 : 18,
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
                    width: active ? 2.2 : 1.5,
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
          width: 23 + 19 * t,
          height: 23 + 19 * t,
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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
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
                fontSize: 10.5,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, size: 12, color: Colors.white),
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
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
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
              width: 20,
              height: 20,
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
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: AppColor.textInk,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.description,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
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
