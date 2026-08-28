import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../data/vehicle.dart';
import '../design/tokens.dart';
import '../widgets/dark_sheet.dart';
import '../widgets/map_backdrop.dart';
import '../widgets/map_chrome.dart';
import 'side_menu.dart';
import 'trip_screen.dart';
import 'vehicle_booking_sheet.dart';

/// The step a map pin opens: the cars that pin stands for, over the same map.
///
/// 同站租還 shows the fleet parked at that station, 路邊租還 the closest cars on
/// the street. There is only ever **one** sheet on screen: collapsed it is a
/// deck of swipeable cards, and pulling it up grows the booking content out
/// from under the front card, which widens to fill the sheet. The two states
/// are one layout interpolated by [_reveal], not two sheets stacked.
class PinVehiclesScreen extends StatefulWidget {
  const PinVehiclesScreen({
    super.key,
    required this.mode,
    required this.pinIndex,
  });

  final RentMode mode;

  /// Which pin was tapped. Kept as an index so the mode switch and the other
  /// pins stay live on this screen.
  final int pinIndex;

  @override
  State<PinVehiclesScreen> createState() => _PinVehiclesScreenState();
}

class _PinVehiclesScreenState extends State<PinVehiclesScreen> {
  // Card geometry. The deck is deliberately narrower than the sheet: the
  // margins either side and the gap to the next card are what tell the user
  // the deck swipes.
  static const _deckViewport = 0.82;

  /// Half the gap between two cards, taken off each side of a page slot.
  static const _deckGap = 6.0;

  static const _grabberBlock = 27.0; // grabber + the padding around it
  static const _badgeRow = 24.0; // iRent logo / region row
  static const _badgeGap = 6.0;
  static const _carAspect = 299 / 533; // car render's intrinsic ratio

  /// Where the sheet rests when opened, and how far it may be pushed while
  /// the content underneath scrolls.
  static const _openSize = 0.88;
  static const _maxSize = 0.94;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _sheet = DraggableScrollableController();
  final _pages = PageController(viewportFraction: _deckViewport);

  late RentMode _mode = widget.mode;
  late int _pin = widget.pinIndex;
  late List<VehicleListing> _cards = _cardsFor(_mode, _pin);
  int _index = 0;
  bool _car = true;

  /// Collapsed sheet size as a fraction of the viewport. Set in [build] once
  /// the media query is known; [_reveal] reads it back.
  double _collapsedSize = 0.18;

  @override
  void initState() {
    super.initState();
    _sheet.addListener(_onSheetMoved);
  }

  @override
  void dispose() {
    _sheet.removeListener(_onSheetMoved);
    _sheet.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _onSheetMoved() {
    if (mounted) setState(() {});
  }

  List<VehicleListing> _cardsFor(RentMode mode, int pin) {
    final pins = listingsFor(mode);
    return listingsAtPin(pins[pin % pins.length]);
  }

  VehicleListing get _current => _cards[_index.clamp(0, _cards.length - 1)];

  /// 0 while the sheet is a deck of cards, 1 once it is fully open.
  double get _reveal {
    if (!_sheet.isAttached) return 0;
    final span = _openSize - _collapsedSize;
    if (span <= 0) return 0;
    return ((_sheet.size - _collapsedSize) / span).clamp(0.0, 1.0);
  }

  // ---------------------------------------------------------------------------
  // Card metrics — the deck's height is derived from the same numbers that lay
  // the card out, so the collapsed sheet ends exactly where the card does and
  // no dead space is left under it.
  // ---------------------------------------------------------------------------

  double _carWidth(double t) => lerpDouble(120, 148, t)!;

  /// The home-indicator strip already reads as margin, so the collapsed card
  /// borrows most of it instead of stacking its own padding on top.
  double _cardPadBottom(double t, double inset) =>
      lerpDouble(math.max(14, inset - 12), 16, t)!;

  double _cardHeight(double t, double inset) =>
      _grabberBlock +
      _badgeRow +
      _badgeGap +
      _carWidth(t) * _carAspect +
      _cardPadBottom(t, inset);

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _setMode(RentMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _cards = _cardsFor(mode, _pin);
      _index = 0;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
    _collapse();
  }

  void _selectPin(int index) {
    if (index == _pin) return;
    setState(() {
      _pin = index;
      _cards = _cardsFor(_mode, index);
      _index = 0;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
    _collapse();
  }

  void _open() => _sheet.animateTo(
    _openSize,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOut,
  );

  void _collapse() {
    if (!_sheet.isAttached) return;
    _sheet.animateTo(
      _collapsedSize,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  /// A card that is not the front one comes to the front; the front one opens.
  void _onCardTap(int i) {
    if (i != _index) {
      _pages.animateToPage(
        i,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    } else if (_reveal < 0.5) {
      _open();
    }
  }

  /// A tap on the basemap folds the sheet away first, then leaves the screen.
  void _onMapTap() {
    if (_reveal > 0.02) {
      _collapse();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _booked() async {
    final listing = _current;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TripScreen(vehicle: listing.vehicle)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.padding.bottom;
    final t = _reveal;
    _collapsedSize = (_cardHeight(0, bottomInset) / media.size.height).clamp(
      0.10,
      _openSize,
    );

    return Scaffold(
      key: _scaffoldKey,
      drawer: const SideMenu(),
      drawerEdgeDragWidth: 32,
      // Without this the Stack shrinks to the chrome row — its only
      // non-positioned child — and the sheet lands under the top bar.
      body: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: MapBackdrop(
                center: DemoPlace.taichung,
                zoom: 14.6,
                pins: demoMapPins(
                  station: _mode == RentMode.station,
                  onTap: _selectPin,
                ),
                bottomPadding: _cardHeight(0, bottomInset),
                onMapTap: _onMapTap,
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MapCircleButton(
                      icon: Icons.menu,
                      size: 42,
                      onTap: () => _scaffoldKey.currentState?.openDrawer(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MapModeSwitch(mode: _mode, onChanged: _setMode),
                    ),
                    const SizedBox(width: 10),
                    MapVehicleTypeSwitch(
                      car: _car,
                      onChanged: (v) => setState(() => _car = v),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: DraggableScrollableSheet(
                controller: _sheet,
                initialChildSize: _collapsedSize,
                minChildSize: _collapsedSize,
                maxChildSize: _maxSize,
                snap: true,
                snapSizes: const [_openSize],
                builder: (context, controller) =>
                    _sheetBody(controller, t, media.size.width, bottomInset),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Sheet
  // -------------------------------------------------------------------------

  Widget _sheetBody(
    ScrollController controller,
    double t,
    double width,
    double bottomInset,
  ) {
    // The sheet's own rounding grows in with it. Rounding the full-width sheet
    // while the deck is collapsed would slice the top corners off the cards
    // sitting near the screen edges — the front card already carries the
    // rounding the sheet needs, and at rest the two arcs coincide exactly.
    final radius = BorderRadius.vertical(
      top: Radius.circular(AppRadius.sheet * t),
    );

    return DecoratedBox(
      // Transparent while collapsed so the map shows through the gaps between
      // the cards; solid once there is content under the front card.
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: t),
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        // Deliberately unkeyed: a key that tracks the selected car would tear
        // this subtree down on every swipe, taking the deck's PageView with it
        // and snapping the controller back to its initial page while [_index]
        // stayed put — the front slot then rendered empty white with the real
        // card parked one slot to the right.
        child: VehicleBookingBody(
          listing: _current,
          controller: controller,
          reveal: t,
          onBooked: _booked,
          header: _deck(t, width, bottomInset),
        ),
      ),
    );
  }

  Widget _deck(double t, double width, double bottomInset) {
    final slot = width * _deckViewport;
    final cardWidth = lerpDouble(slot - _deckGap * 2, width, t)!;

    return SizedBox(
      height: _cardHeight(t, bottomInset),
      // Swiping is off once the sheet is open, but the deck keeps its scroll
      // physics: swapping in NeverScrollableScrollPhysics rebuilds the scroll
      // position, which can strand the deck between two pages if the swap
      // lands mid-fling.
      child: IgnorePointer(
        ignoring: t > 0.5,
        child: PageView.builder(
          controller: _pages,
          // The front card grows wider than its page slot on the way up.
          clipBehavior: Clip.none,
          physics: const PageScrollPhysics(),
          onPageChanged: (i) => setState(() => _index = i),
          itemCount: _cards.length,
          itemBuilder: (context, i) => Opacity(
            // The neighbours are gone before the front card has widened far
            // enough to reach into their slots.
            opacity: i == _index ? 1 : (1 - t * 2).clamp(0.0, 1.0),
            child: OverflowBox(
              // minWidth has to be released too: the page slot hands down
              // tight constraints, which would otherwise stretch the card back
              // to the full slot and close the gap between the cards.
              minWidth: 0,
              maxWidth: width,
              alignment: Alignment.center,
              child: SizedBox(
                width: cardWidth,
                child: _VehicleCard(
                  listing: _cards[i],
                  carWidth: _carWidth(t),
                  padBottom: _cardPadBottom(t, bottomInset),
                  onTap: () => _onCardTap(i),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// One card of the deck. The front card is also the booking sheet's header, so
/// this is the only dark vehicle block on the screen in either state.
class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.listing,
    required this.carWidth,
    required this.padBottom,
    required this.onTap,
  });

  final VehicleListing listing;
  final double carWidth;
  final double padBottom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, padBottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 24,
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/images/irent_logo.png',
                          width: 30,
                          height: 24,
                          fit: BoxFit.contain,
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            listing.region,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: carWidth * 299 / 533,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                listing.plate,
                                style: const TextStyle(
                                  fontSize: 27,
                                  height: 1.15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      listing.address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.35,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Image.asset(
                          listing.vehicle.heroImage,
                          width: carWidth,
                          fit: BoxFit.contain,
                        ),
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
