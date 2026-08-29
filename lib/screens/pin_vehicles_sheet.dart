import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../data/vehicle.dart';
import '../design/tokens.dart';
import '../widgets/dark_sheet.dart';
import 'trip_screen.dart';
import 'vehicle_booking_sheet.dart';

/// What a map pin opens: the cars that pin stands for, over the map that is
/// already on screen.
///
/// This is a sheet, not a screen — tapping a pin must not navigate anywhere.
/// The host ([HomeMapScreen]) keeps its map and its top chrome and swaps its
/// own bottom block out for this, so the basemap never rebuilds and the pins
/// never move under the user's finger.
///
/// The deck holds every pin's cards at once, in pin order — not just the
/// tapped pin's. Tapping a pin therefore *slides* the deck across to that
/// pin's card instead of swapping the card's contents out from underneath it,
/// and swiping the deck sideways selects the pin that card belongs to. Marker
/// and card stay on the same car in both directions, the way Google Maps pairs
/// its pin with its carousel.
///
/// 同站租還 gives each pin the fleet parked at that station, 路邊租還 one card
/// per car on the street. There is only ever **one** sheet on screen:
/// collapsed it is a deck of swipeable cards, and pulling it up grows the
/// booking content out from under the front card, which widens to fill the
/// sheet. The two states are one layout interpolated by [_reveal], not two
/// sheets stacked.
class PinVehiclesSheet extends StatefulWidget {
  const PinVehiclesSheet({
    super.key,
    required this.mode,
    required this.pinIndex,
    required this.onPinChanged,
    required this.onClose,
  });

  final RentMode mode;

  /// Which pin is selected. Kept as an index so the host's mode switch and its
  /// other pins stay live while the sheet is up.
  final int pinIndex;

  /// The deck was swiped onto a card belonging to another pin. The host takes
  /// the map with it — highlighting that pin and flying the camera over.
  final ValueChanged<int> onPinChanged;

  /// The sheet wants to go away: the map was tapped while the deck was already
  /// collapsed, or the back button was pressed.
  final VoidCallback onClose;

  /// How tall the sheet is at rest, so the host can hold its basemap's logo and
  /// attribution clear of it.
  static double collapsedHeight(double bottomInset) =>
      PinVehiclesSheetState._cardHeight(0, bottomInset);

  @override
  State<PinVehiclesSheet> createState() => PinVehiclesSheetState();
}

/// Public so the host can reach [handleMapTap] and [collapse] through a
/// `GlobalKey`: the map belongs to the host, but only the sheet knows whether a
/// tap on it should fold the deck down or dismiss it.
class PinVehiclesSheetState extends State<PinVehiclesSheet> {
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

  /// How long the deck takes to slide onto a freshly tapped pin's card. Short:
  /// it has to feel like the card came along with the map, not like a second
  /// transition after it.
  static const _slide = Duration(milliseconds: 260);

  final _sheet = DraggableScrollableController();

  late PinDeck _deck;
  late PageController _pages;

  /// Index into [PinDeck.cards], not into the selected pin's cars.
  late int _index;

  /// True while [_slideToPin] drives the deck. [PageView.onPageChanged] fires
  /// for pages crossed on the way, and reporting those back to the host would
  /// drag the map across every pin in between.
  bool _sliding = false;

  /// Collapsed sheet size as a fraction of the viewport. Set in [build] once
  /// the media query is known; [_reveal] reads it back.
  double _collapsedSize = 0.18;

  @override
  void initState() {
    super.initState();
    _deck = deckFor(widget.mode);
    _index = _deck.cardAt(widget.pinIndex);
    _pages = PageController(
      viewportFraction: _deckViewport,
      initialPage: _index,
    );
    _sheet.addListener(_onSheetMoved);
  }

  @override
  void didUpdateWidget(covariant PinVehiclesSheet oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.mode != widget.mode) {
      // A different deck entirely — there is no card to slide to.
      setState(() {
        _deck = deckFor(widget.mode);
        _index = _deck.cardAt(widget.pinIndex);
      });
      if (_pages.hasClients) _pages.jumpToPage(_index);
      collapse();
      return;
    }

    // Already showing one of that pin's cars: the host is only echoing a swipe
    // back at us, or the user re-tapped the pin they are looking at.
    if (_deck.pinAt(_index) == widget.pinIndex) return;
    _slideToPin(widget.pinIndex);
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

  VehicleListing get _current =>
      _deck.cards[_index.clamp(0, _deck.cards.length - 1)];

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

  static double _carWidth(double t) => lerpDouble(120, 148, t)!;

  /// The collapsed card sits on the screen edge, so its bottom padding has to
  /// clear the system bar rather than borrow from it: an Android gesture bar
  /// is only 24dp and the card's last line was landing underneath it.
  static double _cardPadBottom(double t, double inset) =>
      lerpDouble(math.max(14, inset), 16, t)!;

  static double _cardHeight(double t, double inset) =>
      _grabberBlock +
      _badgeRow +
      _badgeGap +
      _carWidth(t) * _carAspect +
      _cardPadBottom(t, inset);

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _open() => _sheet.animateTo(
    _openSize,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOut,
  );

  void collapse() {
    if (!_sheet.isAttached) return;
    _sheet.animateTo(
      _collapsedSize,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  /// A tap on the basemap folds the sheet down first; a second one dismisses
  /// it. Called by the host, which owns the map.
  void handleMapTap() {
    if (_reveal > 0.02) {
      collapse();
    } else {
      widget.onClose();
    }
  }

  /// A card that is not the front one comes to the front; the front one opens.
  void _onCardTap(int i) {
    if (i != _index) {
      _pages.animateToPage(i, duration: _slide, curve: Curves.easeOut);
    } else if (_reveal < 0.5) {
      _open();
    }
  }

  /// Runs the deck across to [pin]'s first card.
  ///
  /// A pin on the far side of the map can be twenty cards away, and scrubbing
  /// through all of them would read as a blur rather than as a move, so a long
  /// hop cuts to the neighbouring card first and only the last card's width is
  /// actually animated. What the user sees either way is one card sliding in.
  Future<void> _slideToPin(int pin) async {
    final target = _deck.cardAt(pin);
    if (!_pages.hasClients) {
      setState(() => _index = target);
      return;
    }

    _sliding = true;
    if ((target - _index).abs() > 1) {
      _pages.jumpToPage(target > _index ? target - 1 : target + 1);
    }
    await _pages.animateToPage(target, duration: _slide, curve: Curves.easeOut);
    if (mounted) _sliding = false;
  }

  /// The deck settled on a new card. Everything below the card — the plate,
  /// the address, the price — is already following [_index]; the map has to
  /// follow it too, or the pin and the card drift apart.
  void _onPageChanged(int i) {
    setState(() => _index = i);
    final pin = _deck.pinAt(i);
    if (!_sliding && pin != widget.pinIndex) widget.onPinChanged(pin);
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

    return DraggableScrollableSheet(
      controller: _sheet,
      initialChildSize: _collapsedSize,
      minChildSize: _collapsedSize,
      maxChildSize: _maxSize,
      snap: true,
      snapSizes: const [_openSize],
      builder: (context, controller) =>
          _sheetBody(controller, t, media.size.width, bottomInset),
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
          header: _cardDeck(t, width, bottomInset),
        ),
      ),
    );
  }

  Widget _cardDeck(double t, double width, double bottomInset) {
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
          onPageChanged: _onPageChanged,
          itemCount: _deck.cards.length,
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
                  listing: _deck.cards[i],
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
                              // The plate has to stay on one line: the block
                              // is exactly as tall as the car render beside
                              // it, so a wrapped plate pushed the address out
                              // through the bottom of the card.
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  listing.plate,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 27,
                                    height: 1.15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
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
