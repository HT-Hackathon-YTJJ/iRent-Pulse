import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../design/tokens.dart';

/// Demo locations. Tainan matches the Figma flow, Taichung matches the
/// reference screenshots of the production app.
class DemoPlace {
  static const chengKung = LatLng(22.9986, 120.2194);
  static const taichung = LatLng(24.1548, 120.6640);
}

/// Light raster basemap.
///
/// Ships with keyless OpenStreetMap tiles, nudged toward the light-grey Google
/// Maps look the production iRent app uses via [_googleLikeFilter].
///
/// To switch to real Google Maps: add `google_maps_flutter`, replace the
/// [FlutterMap] below with `GoogleMap`, and feed it the same centre/zoom.
/// To use a styled vendor basemap instead, only [tileUrl] has to change
/// (e.g. Stadia "Alidade Smooth" or CARTO Positron — both key-gated).
class MapBackdrop extends StatelessWidget {
  const MapBackdrop({
    super.key,
    required this.center,
    this.zoom = 15.5,
    this.interactive = true,
    this.markers = const [],
    this.showUserDot = true,
    this.showAttribution = true,
  });

  final LatLng center;
  final double zoom;
  final bool interactive;
  final List<Marker> markers;
  final bool showUserDot;
  final bool showAttribution;

  static const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Halves OSM's saturation and lifts it, landing close to Google Maps' light
  /// basemap: grey roads, muted green parks, muted blue water.
  static const _googleLikeFilter = ColorFilter.matrix(<double>[
    0.607, 0.357, 0.036, 0, 18, //
    0.107, 0.857, 0.036, 0, 18,
    0.107, 0.357, 0.536, 0, 20,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        minZoom: 10,
        maxZoom: 18,
        backgroundColor: const Color(0xFFF0EFEA),
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        ColorFiltered(
          colorFilter: _googleLikeFilter,
          child: TileLayer(
            urlTemplate: tileUrl,
            userAgentPackageName: 'tw.irent.pulse.demo',
            maxNativeZoom: 19,
            tileDisplay: const TileDisplay.fadeIn(
              duration: Duration(milliseconds: 180),
            ),
          ),
        ),
        if (showUserDot)
          MarkerLayer(
            markers: [
              Marker(
                point: center,
                width: 26,
                height: 26,
                child: const _UserDot(),
              ),
            ],
          ),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
        if (showAttribution) const _Attribution(),
      ],
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Text(
              '© OpenStreetMap',
              style: TextStyle(
                fontSize: 8.5,
                color: Color(0xFF6B6B70),
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: const Color(0xFF3A7BFF),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}

/// The teardrop station pin from the production app.
///
/// [icon] null → solid coloured pin (同站租還 station); [icon] set → white pin
/// carrying a coloured glyph (路邊租還 vehicle).
class StationPin extends StatelessWidget {
  const StationPin({
    super.key,
    this.color = AppColor.brand,
    this.pro = false,
    this.icon,
  });

  final Color color;
  final bool pro;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final filled = icon == null;
    return SizedBox(
      width: 34,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _PinPainter(color: color, filled: filled),
            ),
          ),
          if (icon != null)
            Positioned(
              left: 0,
              right: 0,
              top: 7,
              child: Icon(icon, size: 19, color: color),
            ),
          if (pro)
            Positioned(
              top: -7,
              right: -8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColor.brandBright,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  const _PinPainter({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final r = w / 2;
    final cx = r;
    final tip = size.height;

    // Teardrop outline: circular head that necks down into a point.
    const neck = 0.62; // where the tail leaves the circle, in radians from +x
    final left = Offset(cx - r * math.cos(neck), r + r * math.sin(neck));
    final right = Offset(cx + r * math.cos(neck), r + r * math.sin(neck));

    final path = Path()
      ..moveTo(left.dx, left.dy)
      ..arcToPoint(
        right,
        radius: Radius.circular(r),
        clockwise: true,
        largeArc: true,
      )
      ..quadraticBezierTo(cx + r * 0.34, tip - r * 0.42, cx, tip)
      ..quadraticBezierTo(cx - r * 0.34, tip - r * 0.42, left.dx, left.dy)
      ..close();

    canvas.drawPath(
      path.shift(const Offset(0, 1.5)),
      Paint()
        ..color = const Color(0x38000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    canvas.drawPath(path, Paint()..color = filled ? color : Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = filled ? Colors.white : const Color(0xFFE4E4E8),
    );
  }

  @override
  bool shouldRepaint(covariant _PinPainter old) =>
      old.color != color || old.filled != filled;
}
