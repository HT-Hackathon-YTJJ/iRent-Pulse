import 'package:flutter/material.dart';

import '../data/vehicle.dart';
import '../design/tokens.dart';

/// The floating controls that sit on top of the basemap.
///
/// They live here rather than inside the map screen because the pin screen
/// shows the very same chrome over the very same map, so both surfaces stay in
/// sync.

/// Segmented control switching between 同站租還 and 路邊租還.
class MapModeSwitch extends StatelessWidget {
  const MapModeSwitch({super.key, required this.mode, required this.onChanged});

  final RentMode mode;
  final ValueChanged<RentMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
                    m.label,
                    style: TextStyle(
                      fontSize: 14,
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

/// Car / scooter selector on the top right.
class MapVehicleTypeSwitch extends StatelessWidget {
  const MapVehicleTypeSwitch({
    super.key,
    required this.car,
    required this.onChanged,
  });

  final bool car;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
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
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: selected ? AppColor.brand : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 21,
          color: selected ? Colors.white : const Color(0xFFBFC6CC),
        ),
      ),
    );
  }
}

/// Vertical stack of map tools under the vehicle-type switch.
class MapToolRail extends StatelessWidget {
  const MapToolRail({super.key, required this.mode});

  final RentMode mode;

  @override
  Widget build(BuildContext context) {
    final icons = mode == RentMode.station
        ? [Icons.search, Icons.local_parking, Icons.favorite_border]
        : [Icons.search, Icons.local_parking, Icons.filter_alt_outlined];

    return Container(
      width: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
                indent: 8,
                endIndent: 8,
                color: AppColor.divider,
              ),
            SizedBox(
              width: 42,
              height: 42,
              child: IconButton(
                onPressed: () {},
                padding: EdgeInsets.zero,
                icon: Icon(icons[i], size: 19, color: AppColor.textPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// White disc holding a single glyph (menu, re-centre…).
class MapCircleButton extends StatelessWidget {
  const MapCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 42,
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
