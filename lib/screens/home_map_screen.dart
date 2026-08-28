import 'package:flutter/material.dart';

import '../data/vehicle.dart';
import '../design/tokens.dart';
import '../widgets/map_backdrop.dart';
import '../widgets/map_chrome.dart';
import 'pin_vehicles_screen.dart';
import 'side_menu.dart';
import 'trip_screen.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  RentMode _mode = RentMode.station;
  bool _car = true;

  /// 同站租還 shows a red map-pin glyph inside the white bubble, 路邊租還 a red
  /// car — exactly like the production app. The layout is shared with
  /// [PinVehiclesScreen] so the map does not shift when a pin is tapped.
  List<MapPin> get _pins =>
      demoMapPins(station: _mode == RentMode.station, onTap: _openPin);

  /// A pin does not open the booking sheet directly: it first shows the cars
  /// it stands for as a swipeable deck (同站租還 → the station's fleet,
  /// 路邊租還 → the closest road-side cars).
  void _openPin(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PinVehiclesScreen(mode: _mode, pinIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
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
                bottomPadding: 150 + bottomInset,
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
              child: MapToolRail(mode: _mode),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: _ActiveRentalCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TripScreen()),
                      ),
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
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const TripScreen(),
                            ),
                          ),
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
              ),
            ),
          ],
        ),
      ),
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
