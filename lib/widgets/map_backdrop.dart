import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:latlong2/latlong.dart' show LatLng;

import '../design/tokens.dart';
import '../config/map_config.dart';

/// Demo locations. Tainan matches the Figma flow, Taichung matches the
/// reference screenshots of the production app.
class DemoPlace {
  static const chengKung = LatLng(22.9986, 120.2194);
  static const taichung = LatLng(24.1548, 120.6640);
}

/// Where the demo scatters its pins around [DemoPlace.taichung]:
/// (Δlat, Δlng, PRO badge, bubble colour).
///
/// Shared so the map screen and the pin screen draw exactly the same map —
/// tapping a pin must not shuffle the other pins around.
const demoPinOffsets = <(double, double, bool, Color)>[
  (0.0042, 0.0031, false, AppColor.brand),
  (-0.0051, 0.0012, false, AppColor.brand),
  (0.0018, -0.0044, true, AppColor.brand),
  (-0.0032, -0.0036, false, AppColor.warning),
  (0.0064, -0.0009, false, AppColor.textPrimary),
  (-0.0015, 0.0055, false, AppColor.brand),
  (0.0035, 0.0062, false, AppColor.brand),
  (-0.0068, 0.0048, true, AppColor.brand),
];

/// The demo's pins for [mode]. [onTap] receives the pin's index.
List<MapPin> demoMapPins({
  required bool station,
  required void Function(int index) onTap,
}) => [
  for (var i = 0; i < demoPinOffsets.length; i++)
    MapPin(
      point: LatLng(
        DemoPlace.taichung.latitude + demoPinOffsets[i].$1,
        DemoPlace.taichung.longitude + demoPinOffsets[i].$2,
      ),
      color: demoPinOffsets[i].$4,
      pro: demoPinOffsets[i].$3,
      icon: station ? Icons.location_on : Icons.directions_car,
      iconSize: station ? 21 : 17,
      onTap: () => onTap(i),
    ),
];

/// A station / vehicle marker, independent of which basemap is rendering it.
class MapPin {
  const MapPin({
    required this.point,
    this.color = AppColor.brand,
    this.pro = false,
    this.icon,
    this.iconSize = 17,
    this.onTap,
  });

  final LatLng point;
  final Color color;
  final bool pro;

  /// null → solid pin; set → white bubble with a glyph. 同站租還 uses a red
  /// [Icons.location_on] glyph, 路邊租還 a red car.
  final IconData? icon;

  /// Glyph size inside the bubble. The station pin's glyph is noticeably
  /// chunkier than the car glyph in the production app.
  final double iconSize;

  final VoidCallback? onTap;
}

/// Light basemap for every screen in the demo.
///
/// Two interchangeable backends, selected by [useGoogleMaps] in
/// `lib/config/map_config.dart` — i.e. by whether `.env` carries a key:
///
/// * **OpenStreetMap** (default, keyless) — raster tiles pushed toward Google's
///   light basemap by [_googleLikeFilter].
/// * **Google Maps** — the real thing, once an API key is configured.
///
/// Pins are plain Flutter widgets in both cases: they are projected onto the
/// viewport with Web Mercator maths, so [StationPin] renders identically
/// whichever backend is live.
class MapBackdrop extends StatelessWidget {
  const MapBackdrop({
    super.key,
    required this.center,
    this.zoom = 15.5,
    this.interactive = true,
    this.pins = const [],
    this.showUserDot = true,
    this.showAttribution = true,
    this.bottomPadding = 0,
    this.onMapTap,
  });

  final LatLng center;
  final double zoom;
  final bool interactive;
  final List<MapPin> pins;
  final bool showUserDot;
  final bool showAttribution;

  /// Tap on the basemap itself, i.e. not on a pin. Screens use it to dismiss
  /// whatever the last pin tap opened.
  final VoidCallback? onMapTap;

  /// How much of the bottom edge the screen's own chrome covers. Keeps the
  /// basemap's logo and attribution visible above it — required by Google's
  /// terms, and it stops the © line from colliding with our buttons.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    if (useGoogleMaps) {
      return _GoogleBackdrop(
        center: center,
        zoom: zoom,
        interactive: interactive,
        pins: pins,
        showUserDot: showUserDot,
        bottomPadding: bottomPadding,
        onMapTap: onMapTap,
      );
    }
    return _OsmBackdrop(
      center: center,
      zoom: zoom,
      interactive: interactive,
      pins: pins,
      showUserDot: showUserDot,
      showAttribution: showAttribution,
      bottomPadding: bottomPadding,
      onMapTap: onMapTap,
    );
  }
}

// ---------------------------------------------------------------------------
// OpenStreetMap backend (default — no API key needed)
// ---------------------------------------------------------------------------

class _OsmBackdrop extends StatelessWidget {
  const _OsmBackdrop({
    required this.center,
    required this.zoom,
    required this.interactive,
    required this.pins,
    required this.showUserDot,
    required this.showAttribution,
    required this.bottomPadding,
    required this.onMapTap,
  });

  final LatLng center;
  final double zoom;
  final bool interactive;
  final List<MapPin> pins;
  final bool showUserDot;
  final bool showAttribution;
  final double bottomPadding;
  final VoidCallback? onMapTap;

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
    return fm.FlutterMap(
      options: fm.MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        minZoom: 10,
        maxZoom: 18,
        onTap: onMapTap == null ? null : (_, _) => onMapTap!(),
        backgroundColor: const Color(0xFFF0EFEA),
        interactionOptions: fm.InteractionOptions(
          flags: interactive
              ? fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate
              : fm.InteractiveFlag.none,
        ),
      ),
      children: [
        ColorFiltered(
          colorFilter: _googleLikeFilter,
          child: fm.TileLayer(
            urlTemplate: tileUrl,
            userAgentPackageName: 'tw.irent.pulse.demo',
            maxNativeZoom: 19,
            tileDisplay: const fm.TileDisplay.fadeIn(
              duration: Duration(milliseconds: 180),
            ),
          ),
        ),
        if (showUserDot)
          fm.MarkerLayer(
            markers: [
              fm.Marker(
                point: center,
                width: 26,
                height: 26,
                child: const _UserDot(),
              ),
            ],
          ),
        if (pins.isNotEmpty)
          fm.MarkerLayer(
            markers: [
              for (final pin in pins)
                fm.Marker(
                  point: pin.point,
                  width: StationPin.width,
                  height: StationPin.height,
                  alignment: Alignment.topCenter,
                  child: StationPin(
                    color: pin.color,
                    pro: pin.pro,
                    icon: pin.icon,
                    iconSize: pin.iconSize,
                    onTap: pin.onTap,
                  ),
                ),
            ],
          ),
        if (showAttribution) _Attribution(bottomPadding: bottomPadding),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Google Maps backend (needs an API key — see lib/map_config.dart)
// ---------------------------------------------------------------------------

class _GoogleBackdrop extends StatefulWidget {
  const _GoogleBackdrop({
    required this.center,
    required this.zoom,
    required this.interactive,
    required this.pins,
    required this.showUserDot,
    required this.bottomPadding,
    required this.onMapTap,
  });

  final LatLng center;
  final double zoom;
  final bool interactive;
  final List<MapPin> pins;
  final bool showUserDot;
  final double bottomPadding;
  final VoidCallback? onMapTap;

  @override
  State<_GoogleBackdrop> createState() => _GoogleBackdropState();
}

class _GoogleBackdropState extends State<_GoogleBackdrop> {
  /// Trims POI clutter so the iRent pins stay the loudest thing on the map.
  static const _style =
      '[{"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},'
      '{"featureType":"transit","elementType":"labels","stylers":[{"visibility":"off"}]},'
      '{"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]}]';

  late LatLng _center = widget.center;
  late double _zoom = widget.zoom;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final viewport = Size(c.maxWidth, c.maxHeight);
        return Stack(
          children: [
            Positioned.fill(
              child: gmap.GoogleMap(
                initialCameraPosition: gmap.CameraPosition(
                  target: gmap.LatLng(
                    widget.center.latitude,
                    widget.center.longitude,
                  ),
                  zoom: widget.zoom,
                ),
                style: _style,
                mapType: gmap.MapType.normal,
                padding: EdgeInsets.only(bottom: widget.bottomPadding),
                compassEnabled: false,
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                scrollGesturesEnabled: widget.interactive,
                zoomGesturesEnabled: widget.interactive,
                onTap: widget.onMapTap == null
                    ? null
                    : (_) => widget.onMapTap!(),
                onCameraMove: (position) => setState(() {
                  _center = LatLng(
                    position.target.latitude,
                    position.target.longitude,
                  );
                  _zoom = position.zoom;
                }),
              ),
            ),
            if (widget.showUserDot)
              _place(
                viewport: viewport,
                point: widget.center,
                size: const Size(26, 26),
                anchor: const Alignment(0, 0),
                child: const _UserDot(),
              ),
            for (final pin in widget.pins)
              _place(
                viewport: viewport,
                point: pin.point,
                size: const Size(StationPin.width, StationPin.height),
                anchor: Alignment.bottomCenter,
                child: StationPin(
                  color: pin.color,
                  pro: pin.pro,
                  icon: pin.icon,
                  iconSize: pin.iconSize,
                  onTap: pin.onTap,
                ),
              ),
          ],
        );
      },
    );
  }

  /// Projects [point] onto the viewport and anchors [child] there.
  Widget _place({
    required Size viewport,
    required LatLng point,
    required Size size,
    required Alignment anchor,
    required Widget child,
  }) {
    final scale = math.pow(2, _zoom).toDouble() * 256;
    double worldX(double lng) => (lng + 180) / 360 * scale;
    double worldY(double lat) {
      final s = math.sin(lat * math.pi / 180).clamp(-0.9999, 0.9999);
      return (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * scale;
    }

    final dx =
        worldX(point.longitude) -
        worldX(_center.longitude) +
        viewport.width / 2;
    final dy =
        worldY(point.latitude) - worldY(_center.latitude) + viewport.height / 2;

    return Positioned(
      left: dx - size.width * (anchor.x + 1) / 2,
      top: dy - size.height * (anchor.y + 1) / 2,
      width: size.width,
      height: size.height,
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------

class _Attribution extends StatelessWidget {
  const _Attribution({required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.only(left: 4, bottom: bottomPadding + 2),
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
/// Both map modes share the white bubble; only the glyph inside differs —
/// 同站租還 shows a red map pin, 路邊租還 a red car.
class StationPin extends StatelessWidget {
  const StationPin({
    super.key,
    this.color = AppColor.brand,
    this.pro = false,
    this.icon,
    this.iconSize = 17,
    this.onTap,
  });

  static const width = 30.0;
  static const height = 39.0;

  final Color color;
  final bool pro;
  final IconData? icon;
  final double iconSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final filled = icon == null;
    final pin = SizedBox(
      width: width,
      height: height,
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
              top: (width - iconSize) / 2,
              child: Icon(icon, size: iconSize, color: color),
            ),
          if (pro)
            Positioned(
              top: -6,
              right: -7,
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
                    fontSize: 7.5,
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

    if (onTap == null) return pin;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: pin,
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
