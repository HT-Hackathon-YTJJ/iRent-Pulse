import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../data/vehicle.dart';
import '../design/tokens.dart';
import '../widgets/map_backdrop.dart';
import 'side_menu.dart';
import 'trip_screen.dart';

enum RentMode { station, roadside }

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  RentMode _mode = RentMode.station;
  bool _car = true;

  static const _stationOffsets = <(double, double, bool, Color)>[
    (0.0042, 0.0031, false, AppColor.brand),
    (-0.0051, 0.0012, false, AppColor.brand),
    (0.0018, -0.0044, true, AppColor.brand),
    (-0.0032, -0.0036, false, AppColor.warning),
    (0.0064, -0.0009, false, AppColor.textPrimary),
    (-0.0015, 0.0055, false, AppColor.brand),
    (0.0035, 0.0062, false, AppColor.brand),
    (-0.0068, 0.0048, true, AppColor.brand),
  ];

  List<Marker> get _markers {
    final base = DemoPlace.taichung;
    return [
      for (final (dLat, dLng, pro, color) in _stationOffsets)
        Marker(
          point: LatLng(base.latitude + dLat, base.longitude + dLng),
          width: 34,
          height: 44,
          alignment: Alignment.topCenter,
          child: StationPin(
            color: color,
            pro: pro,
            icon: _mode == RentMode.roadside ? Icons.directions_car : null,
          ),
        ),
    ];
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
                markers: _markers,
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CircleButton(
                      icon: Icons.menu,
                      size: 50,
                      onTap: () => _scaffoldKey.currentState?.openDrawer(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ModeSwitch(
                        mode: _mode,
                        onChanged: (m) => setState(() => _mode = m),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _VehicleTypeSwitch(
                      car: _car,
                      onChanged: (v) => setState(() => _car = v),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 14,
              top: MediaQuery.paddingOf(context).top + 190,
              child: _ToolRail(mode: _mode),
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
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
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
                        _CircleButton(
                          icon: Icons.my_location,
                          size: 54,
                          iconColor: AppColor.textPrimary,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                  _AnnouncementBar(bottomInset: bottomInset),
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

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final RentMode mode;
  final ValueChanged<RentMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadow.floating,
      ),
      child: Row(
        children: [
          for (final m in RentMode.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: mode == m
                        ? const Color(0xFF3B3B3B)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    m == RentMode.station ? '同站租還' : '路邊租還',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: mode == m ? Colors.white : const Color(0xFF9A9A9E),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VehicleTypeSwitch extends StatelessWidget {
  const _VehicleTypeSwitch({required this.car, required this.onChanged});

  final bool car;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: AppShadow.floating,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _typeButton(Icons.directions_car, true),
          _typeButton(Icons.two_wheeler, false),
        ],
      ),
    );
  }

  Widget _typeButton(IconData icon, bool isCar) {
    final selected = car == isCar;
    return GestureDetector(
      onTap: () => onChanged(isCar),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: selected ? AppColor.brand : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 26,
          color: selected ? Colors.white : const Color(0xFFBFC6CC),
        ),
      ),
    );
  }
}

class _ToolRail extends StatelessWidget {
  const _ToolRail({required this.mode});

  final RentMode mode;

  @override
  Widget build(BuildContext context) {
    final icons = mode == RentMode.station
        ? [Icons.search, Icons.local_parking, Icons.favorite_border]
        : [Icons.search, Icons.local_parking, Icons.filter_alt_outlined];

    return Container(
      width: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadow.floating,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < icons.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 10,
                endIndent: 10,
                color: AppColor.divider,
              ),
            SizedBox(
              width: 50,
              height: 50,
              child: IconButton(
                onPressed: () {},
                icon: Icon(icons[i], size: 23, color: AppColor.textPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.size = 50,
    this.iconColor = AppColor.textPrimary,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: const Color(0x33000000),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.46, color: iconColor),
        ),
      ),
    );
  }
}

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
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 62,
          height: 54,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: AppColor.accentBlue),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
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
      elevation: 6,
      shadowColor: AppColor.brand.withValues(alpha: 0.45),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () {},
        child: SizedBox(
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                station ? Icons.add_circle : Icons.search,
                size: 24,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Text(
                station ? '立即預約' : '一鍵尋車',
                style: const TextStyle(
                  fontSize: 20,
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
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
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
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColor.successBright,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: const Text(
                            '取車中',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          corollaCross.plate,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '8/18 15:30 → 17:30 ・ 成大站',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColor.textOnDark,
                      ),
                    ),
                  ],
                ),
              ),
              Image.asset(
                corollaCross.heroImage,
                width: 92,
                fit: BoxFit.contain,
              ),
              const Icon(Icons.chevron_right, color: Colors.white54, size: 26),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementBar extends StatelessWidget {
  const _AnnouncementBar({required this.bottomInset});

  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: AppShadow.bottomBar,
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColor.track,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.campaign_outlined,
                  size: 24,
                  color: AppColor.textSecondary,
                ),
                const SizedBox(width: 10),
                const Text(
                  '情報分享',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColor.textPrimary,
                  ),
                ),
                const SizedBox(width: 10),
                Container(width: 1, height: 18, color: AppColor.divider),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'iRent 夏季狂歡季 — 狂賀 8 週年',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColor.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFDBE3D),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.keyboard_arrow_up,
                    color: Colors.white,
                    size: 24,
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
