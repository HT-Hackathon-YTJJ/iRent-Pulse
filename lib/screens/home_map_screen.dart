import 'package:flutter/material.dart';

import '../data/vehicle.dart';
import '../design/tokens.dart';
import '../widgets/back_button.dart';
import '../widgets/map_backdrop.dart';
import '../widgets/map_chrome.dart';
import 'pin_vehicles_sheet.dart';
import 'side_menu.dart';
import 'trip_screen.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen>
    with SingleTickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _sheetKey = GlobalKey<PinVehiclesSheetState>();

  /// Drives the swap between the home block (租約卡 + 訂單/立即預約/定位) and the
  /// pin sheet. One controller runs both halves so they cross over together
  /// instead of one popping in over the other.
  late final AnimationController _swap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  RentMode _mode = RentMode.station;
  bool _car = true;

  /// The pin whose cars are showing, or null while the home block is up.
  /// A pin tap stays on this screen — it must not push a route, or the map
  /// would rebuild underneath and the pins would jump.
  int? _pin;

  @override
  void dispose() {
    _swap.dispose();
    super.dispose();
  }

  /// 同站租還 shows a red map-pin glyph inside the white bubble, 路邊租還 a red
  /// car — exactly like the production app.
  List<MapPin> get _pins =>
      demoMapPins(station: _mode == RentMode.station, onTap: _selectPin);

  /// A pin does not open the booking sheet directly: it first shows the cars
  /// it stands for as a swipeable deck (同站租還 → the station's fleet,
  /// 路邊租還 → the closest road-side cars).
  void _selectPin(int index) {
    if (_pin != index) setState(() => _pin = index);
    _swap.forward();
  }

  void _closePin() {
    _swap.reverse().whenComplete(() {
      // Another pin may have been tapped while we were folding away.
      if (mounted && _swap.isDismissed) setState(() => _pin = null);
    });
  }

  /// The map is ours, but whether a tap on it folds the deck down or dismisses
  /// it is the sheet's call.
  void _onMapTap() {
    if (_pin == null) return;
    final sheet = _sheetKey.currentState;
    if (sheet == null) {
      _closePin();
    } else {
      sheet.handleMapTap();
    }
  }

  /// Fades and slides [child] out of the way as the pin sheet comes up.
  Widget _swapsOut({required Widget child}) {
    return AnimatedBuilder(
      animation: _swap,
      builder: (context, child) {
        final t = _swap.value;
        if (t >= 1) return const SizedBox.shrink();
        return IgnorePointer(
          ignoring: t > 0,
          child: Opacity(
            opacity: 1 - t,
            child: FractionalTranslation(
              translation: Offset(0, t),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final showingPin = _pin != null;

    return PopScope(
      // The pin sheet is a state of this screen, not a route, so the system
      // back gesture has to be caught here or it would leave the app.
      canPop: !showingPin,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closePin();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: const SideMenu(),
        drawerEdgeDragWidth: 32,
        body: SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(
                child: MapBackdrop(
                  center: DemoPlace.taichung,
                  zoom: 14.6,
                  pins: _pins,
                  bottomPadding: showingPin
                      ? PinVehiclesSheet.collapsedHeight(bottomInset)
                      : 150 + bottomInset,
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
                      _leadingButton(),
                      const SizedBox(width: 10),
                      Expanded(
                        child: MapModeSwitch(
                          mode: _mode,
                          onChanged: (m) => setState(() => _mode = m),
                        ),
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
              Positioned(
                right: 14,
                top: MediaQuery.paddingOf(context).top + 140,
                child: _swapsOut(child: MapToolRail(mode: _mode)),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _swapsOut(child: _homeBlock(bottomInset)),
              ),
              if (showingPin)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _swap,
                    builder: (context, child) => FractionalTranslation(
                      // Rides up from below the bottom edge, so the sheet takes
                      // the home block's place rather than appearing over it.
                      translation: Offset(0, 1 - _swap.value),
                      child: child,
                    ),
                    child: PinVehiclesSheet(
                      key: _sheetKey,
                      mode: _mode,
                      pinIndex: _pin!,
                      onClose: _closePin,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Hamburger on the home block, the app's standard back chevron once the pin
  /// sheet is up — the sheet is a step forward even though it is not a route.
  Widget _leadingButton() {
    return SizedBox(
      // Sized to the larger of the two so the chrome row does not twitch as
      // they cross-fade.
      width: AppBackButton.size,
      height: AppBackButton.size,
      child: AnimatedBuilder(
        animation: _swap,
        builder: (context, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: _swap.value > 0.5
              ? AppBackButton(key: const ValueKey('back'), onTap: _closePin)
              : Center(
                  key: const ValueKey('menu'),
                  child: MapCircleButton(
                    icon: Icons.menu,
                    size: 42,
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _homeBlock(double bottomInset) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: _ActiveRentalCard(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const TripScreen())),
          ),
        ),
        Padding(
          // 28 keeps the action row clear of the basemap's logo/attribution:
          // google_maps_flutter_web ignores GoogleMap.padding,
          // so the gap has to come from our side on web.
          padding: EdgeInsets.fromLTRB(14, 0, 14, 28 + bottomInset),
          child: Row(
            children: [
              _SquareButton(
                icon: Icons.assignment_outlined,
                label: '訂單',
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const TripScreen())),
              ),
              const SizedBox(width: 12),
              Expanded(child: _PrimaryAction(mode: _mode)),
              const SizedBox(width: 12),
              MapCircleButton(
                icon: Icons.my_location,
                size: 46,
                iconColor: AppColor.textPrimary,
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: SizedBox(
          width: 54,
          height: 46,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: AppColor.accentBlue),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: AppColor.accentBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.mode});

  final RentMode mode;

  @override
  Widget build(BuildContext context) {
    final station = mode == RentMode.station;
    return Material(
      color: AppColor.brand,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () {},
        child: SizedBox(
          height: 46,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                station ? Icons.add_circle : Icons.search,
                size: 20,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                station ? '立即預約' : '一鍵尋車',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveRentalCard extends StatelessWidget {
  const _ActiveRentalCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF3B3B3B),
      borderRadius: BorderRadius.circular(AppRadius.card),
      elevation: 8,
      shadowColor: const Color(0x40000000),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColor.successBright,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: const Text(
                            '取車中',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          corollaCross.plate,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      '8/18 15:30 → 17:30 ・ 成大站',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColor.textOnDark,
                      ),
                    ),
                  ],
                ),
              ),
              Image.asset(
                corollaCross.heroImage,
                width: 88,
                fit: BoxFit.contain,
              ),
              const Icon(Icons.chevron_right, color: Colors.white54, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
