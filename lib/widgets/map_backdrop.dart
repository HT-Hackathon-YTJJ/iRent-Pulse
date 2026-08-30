import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show kIsWeb;
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

/// Where the pin with [index] sits, so a screen can aim its camera at the pin
/// it just selected without reaching into [demoPinOffsets] itself.
LatLng demoPinLocation(int index) {
  final offset = demoPinOffsets[index % demoPinOffsets.length];
  return LatLng(
    DemoPlace.taichung.latitude + offset.$1,
    DemoPlace.taichung.longitude + offset.$2,
  );
}

/// The demo's pins for [mode]. [onTap] receives the pin's index; the pin at
/// [selected] is drawn in its focused style.
List<MapPin> demoMapPins({
  required bool station,
  required void Function(int index) onTap,
  int? selected,
}) => [
  for (var i = 0; i < demoPinOffsets.length; i++)
    MapPin(
      point: demoPinLocation(i),
      color: demoPinOffsets[i].$4,
      pro: demoPinOffsets[i].$3,
      icon: station ? Icons.location_on : Icons.directions_car,
      iconSize: station ? 21 : 17,
      selected: i == selected,
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
    this.selected = false,
    this.onTap,
  });

  /// How much bigger the selected pin is drawn than the rest of the field.
  static const selectedScale = 1.3;

  final LatLng point;
  final Color color;
  final bool pro;

  /// null → solid pin; set → white bubble with a glyph. 同站租還 uses a red
  /// [Icons.location_on] glyph, 路邊租還 a red car.
  final IconData? icon;

  /// Glyph size inside the bubble. The station pin's glyph is noticeably
  /// chunkier than the car glyph in the production app.
  final double iconSize;

  /// The pin the user just tapped. It inverts — solid brand bubble, white
  /// glyph — and grows, so the map says which card the deck is showing.
  final bool selected;

  final VoidCallback? onTap;

  double get scale => selected ? selectedScale : 1.0;

  /// The same pin in the other selection state. Used to keep both appearances
  /// rasterised ahead of the tap on the Google backend.
  MapPin withSelected(bool value) => MapPin(
    point: point,
    color: color,
    pro: pro,
    icon: icon,
    iconSize: iconSize,
    selected: value,
    onTap: onTap,
  );
}

/// A camera move a screen asks its basemap for — the Google Maps gesture of
/// pulling the tapped pin into the middle of the map and leaning in.
///
/// [minZoom] is a floor, not a target: a map already closer than that stays
/// where it is rather than zooming back out under the user.
@immutable
class MapFocus {
  const MapFocus({
    required this.target,
    required this.minZoom,
    required this.seq,
  });

  final LatLng target;
  final double minZoom;

  /// Bumped by the caller on every request, so tapping the same pin again
  /// after panning away still re-centres it.
  final int seq;

  @override
  bool operator ==(Object other) =>
      other is MapFocus &&
      other.seq == seq &&
      other.minZoom == minZoom &&
      other.target == target;

  @override
  int get hashCode => Object.hash(target, minZoom, seq);
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
/// [StationPin] is the same artwork on both backends, but each backend draws it
/// the way its own map wants: flutter_map takes the widget straight into its
/// marker layer, while Google Maps gets it rasterised into a real SDK marker.
/// Either way the pins live in the map's frame, so they pan and zoom locked to
/// the tiles instead of trailing a frame behind them.
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
    this.focus,
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
  ///
  /// It is also what [focus] centres against: the middle of the map the user
  /// can actually see is the middle of what is left above this.
  final double bottomPadding;

  /// Where to fly the camera. Set a new [MapFocus] to move it.
  final MapFocus? focus;

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
        focus: focus,
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
      focus: focus,
      onMapTap: onMapTap,
    );
  }
}

/// How long a focus move takes on either backend.
const _flyDuration = Duration(milliseconds: 420);

/// Latitude offset that lifts a point [pixels] logical pixels up the screen at
/// [zoom]. Used where the map cannot be told about the sheet covering its
/// bottom edge and the centring has to be faked in the coordinate itself.
double _latLift(double lat, double zoom, double pixels) {
  final metresPerPixel =
      156543.03392 * math.cos(lat * math.pi / 180) / math.pow(2, zoom);
  return pixels * metresPerPixel / 111320.0;
}

// ---------------------------------------------------------------------------
// OpenStreetMap backend (default — no API key needed)
// ---------------------------------------------------------------------------

class _OsmBackdrop extends StatefulWidget {
  const _OsmBackdrop({
    required this.center,
    required this.zoom,
    required this.interactive,
    required this.pins,
    required this.showUserDot,
    required this.showAttribution,
    required this.bottomPadding,
    required this.focus,
    required this.onMapTap,
  });

  final LatLng center;
  final double zoom;
  final bool interactive;
  final List<MapPin> pins;
  final bool showUserDot;
  final bool showAttribution;
  final double bottomPadding;
  final MapFocus? focus;
  final VoidCallback? onMapTap;

  static const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  @override
  State<_OsmBackdrop> createState() => _OsmBackdropState();
}

/// flutter_map moves its camera in one jump, so the focus fly is tweened here:
/// an [AnimationController] walks centre and zoom together and pushes each
/// frame through [fm.MapController.move].
class _OsmBackdropState extends State<_OsmBackdrop>
    with SingleTickerProviderStateMixin {
  final _map = fm.MapController();

  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: _flyDuration,
  )..addListener(_flyFrame);

  /// The map's controller throws until the map has laid itself out once.
  bool _ready = false;

  LatLng _from = DemoPlace.taichung;
  LatLng _to = DemoPlace.taichung;
  double _fromZoom = 0;
  double _toZoom = 0;

  @override
  void didUpdateWidget(covariant _OsmBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focus != null && widget.focus != oldWidget.focus) _startFly();
  }

  @override
  void dispose() {
    _fly.dispose();
    _map.dispose();
    super.dispose();
  }

  void _onMapReady() {
    _ready = true;
    if (widget.focus != null) _startFly();
  }

  void _startFly() {
    if (!_ready) return;
    final focus = widget.focus!;
    final camera = _map.camera;
    _from = camera.center;
    _fromZoom = camera.zoom;
    _toZoom = math.max(camera.zoom, focus.minZoom);

    // Both ends of the tween have to be plain map centres, so the lift that
    // holds the pin above the sheet is baked into the destination rather than
    // handed to `move`'s offset — otherwise every fly would start with a jump
    // of half the sheet's height as the offset was applied to a centre that
    // already had it.
    _to = LatLng(
      focus.target.latitude -
          _latLift(focus.target.latitude, _toZoom, widget.bottomPadding / 2),
      focus.target.longitude,
    );
    _fly.forward(from: 0);
  }

  void _flyFrame() {
    if (!_ready) return;
    final t = Curves.easeInOutCubic.transform(_fly.value);
    _map.move(
      LatLng(
        lerpDouble(_from.latitude, _to.latitude, t)!,
        lerpDouble(_from.longitude, _to.longitude, t)!,
      ),
      lerpDouble(_fromZoom, _toZoom, t)!,
    );
  }

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
      mapController: _map,
      options: fm.MapOptions(
        initialCenter: widget.center,
        initialZoom: widget.zoom,
        minZoom: 10,
        maxZoom: 18,
        onMapReady: _onMapReady,
        onTap: widget.onMapTap == null ? null : (_, _) => widget.onMapTap!(),
        backgroundColor: const Color(0xFFF0EFEA),
        interactionOptions: fm.InteractionOptions(
          flags: widget.interactive
              ? fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate
              : fm.InteractiveFlag.none,
        ),
      ),
      children: [
        ColorFiltered(
          colorFilter: _googleLikeFilter,
          child: fm.TileLayer(
            urlTemplate: _OsmBackdrop.tileUrl,
            userAgentPackageName: 'tw.irent.pulse.demo',
            maxNativeZoom: 19,
            tileDisplay: const fm.TileDisplay.fadeIn(
              duration: Duration(milliseconds: 180),
            ),
          ),
        ),
        if (widget.showUserDot)
          fm.MarkerLayer(
            markers: [
              fm.Marker(
                point: widget.center,
                width: 26,
                height: 26,
                child: const _UserDot(),
              ),
            ],
          ),
        if (widget.pins.isNotEmpty)
          fm.MarkerLayer(
            markers: [
              // The selected pin is drawn last so it grows over its
              // neighbours rather than under them.
              for (final pin in [
                ...widget.pins.where((p) => !p.selected),
                ...widget.pins.where((p) => p.selected),
              ])
                fm.Marker(
                  point: pin.point,
                  width: StationPin.width * pin.scale,
                  height: StationPin.height * pin.scale,
                  alignment: Alignment.topCenter,
                  child: StationPin(
                    color: pin.color,
                    pro: pin.pro,
                    icon: pin.icon,
                    iconSize: pin.iconSize,
                    selected: pin.selected,
                    onTap: pin.onTap,
                  ),
                ),
            ],
          ),
        if (widget.showAttribution)
          _Attribution(bottomPadding: widget.bottomPadding),
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
    required this.focus,
    required this.onMapTap,
  });

  final LatLng center;
  final double zoom;
  final bool interactive;
  final List<MapPin> pins;
  final bool showUserDot;
  final double bottomPadding;
  final MapFocus? focus;
  final VoidCallback? onMapTap;

  @override
  State<_GoogleBackdrop> createState() => _GoogleBackdropState();
}

/// The pins are handed to the Maps SDK as real markers, not as Flutter widgets
/// projected onto the viewport.
///
/// That is the whole point: a marker belongs to the map's own frame, so it
/// pans, zooms and settles in the *same* frame as the tiles under it. The
/// widget overlay this replaces had to mirror the camera through
/// `onCameraMove`, which arrives after the map has already drawn — the pins
/// visibly lagged the basemap and drifted while zooming, because a widget's
/// screen offset is recomputed per camera event rather than scaled with the
/// projection.
///
/// The price is that a marker is a bitmap, so [StationPin]'s artwork is
/// rasterised once per appearance by [_renderPinBitmap] and cached in
/// [_markerBitmaps] for the rest of the session.
class _GoogleBackdropState extends State<_GoogleBackdrop> {
  /// Trims POI clutter so the iRent pins stay the loudest thing on the map.
  static const _style =
      '[{"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},'
      '{"featureType":"transit","elementType":"labels","stylers":[{"visibility":"off"}]},'
      '{"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]}]';

  gmap.GoogleMapController? _controller;

  /// Last known camera zoom, kept here rather than asked for at the moment of
  /// the tap: `getZoomLevel()` is a platform round trip, and awaiting one
  /// before calling [gmap.GoogleMapController.animateCamera] left the map
  /// sitting still for a beat after the pin had already lit up. Refreshed
  /// whenever the camera settles, which covers the user pinching the map.
  late double _zoom = widget.zoom;

  @override
  void initState() {
    super.initState();
    _ensureBitmaps();
  }

  Future<void> _syncZoom() async {
    final zoom = await _controller?.getZoomLevel();
    if (zoom != null) _zoom = zoom;
  }

  @override
  void didUpdateWidget(covariant _GoogleBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureBitmaps();
    if (widget.focus != null && widget.focus != oldWidget.focus) _fly();
  }

  void _onMapCreated(gmap.GoogleMapController controller) {
    _controller = controller;
    _zoom = widget.zoom;
    if (widget.focus != null) _fly();
  }

  /// Pulls the focused point into the middle of the map and leans in, without
  /// ever backing out of a zoom the user has already dialled in.
  ///
  /// Deliberately synchronous up to the `animateCamera` call: the tap that
  /// gets us here also lights the pin up and slides the deck, and the camera
  /// has to leave in the same frame as those or the three come apart.
  void _fly() {
    final focus = widget.focus;
    final controller = _controller;
    if (focus == null || controller == null) return;

    final zoom = math.max(_zoom, focus.minZoom);
    _zoom = zoom;

    // Native honours GoogleMap.padding, so the camera already centres on the
    // strip above the sheet; google_maps_flutter_web drops it, so on web the
    // lift has to be baked into the target.
    final lift = kIsWeb
        ? _latLift(focus.target.latitude, zoom, widget.bottomPadding / 2)
        : 0.0;

    controller.animateCamera(
      gmap.CameraUpdate.newLatLngZoom(
        gmap.LatLng(focus.target.latitude - lift, focus.target.longitude),
        zoom,
      ),
      duration: _flyDuration,
    );
  }

  /// Rasterises whatever the current pins need and is not cached yet. Anything
  /// already cached is picked up synchronously by [build], so switching mode or
  /// screen never drops the markers for a frame.
  ///
  /// Both selection states are rendered up front: a pin tap has to swap the
  /// bubble on the same frame the sheet moves, and waiting on a rasterisation
  /// there would blink the marker out.
  ///
  /// In two passes, though. What is on screen now goes up as soon as it is
  /// ready; the appearance a tap would switch *to* is warmed afterwards, so
  /// stocking the cache never delays the pins the user is waiting for. The
  /// cache is keyed by appearance rather than by pin, so a field of eight pins
  /// costs a handful of renders, once per session.
  Future<void> _ensureBitmaps() async {
    await _render(widget.pins, withUserDot: widget.showUserDot);
    await _render([
      for (final pin in widget.pins) pin.withSelected(!pin.selected),
    ]);
  }

  Future<void> _render(List<MapPin> pins, {bool withUserDot = false}) async {
    var added = false;
    for (final pin in pins) {
      final key = _pinKey(pin);
      if (_markerBitmaps.containsKey(key)) continue;
      _markerBitmaps[key] = await _renderPinBitmap(pin);
      added = true;
    }
    if (withUserDot && !_markerBitmaps.containsKey(_userDotKey)) {
      _markerBitmaps[_userDotKey] = await _renderUserDotBitmap();
      added = true;
    }
    if (added && mounted) setState(() {});
  }

  Set<gmap.Marker> get _markers {
    final markers = <gmap.Marker>{};

    final dot = _markerBitmaps[_userDotKey];
    if (widget.showUserDot && dot != null) {
      markers.add(
        gmap.Marker(
          markerId: const gmap.MarkerId('user'),
          position: gmap.LatLng(
            widget.center.latitude,
            widget.center.longitude,
          ),
          icon: dot,
          anchor: const Offset(0.5, 0.5),
        ),
      );
    }

    for (var i = 0; i < widget.pins.length; i++) {
      final pin = widget.pins[i];
      final icon = _markerBitmaps[_pinKey(pin)];
      if (icon == null) continue;
      markers.add(
        gmap.Marker(
          markerId: gmap.MarkerId('pin_$i'),
          position: gmap.LatLng(pin.point.latitude, pin.point.longitude),
          icon: icon,
          anchor: _PinBitmap.anchor,
          // The selected pin is the tallest thing on the map, so it also has
          // to be the topmost — otherwise its neighbours clip into it.
          zIndexInt: pin.selected ? widget.pins.length + 1 : i + 1,
          // Otherwise a tap on a pin also reaches GoogleMap.onTap and the
          // screen closes the sheet the very tap just opened.
          consumeTapEvents: pin.onTap != null,
          onTap: pin.onTap,
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return gmap.GoogleMap(
      initialCameraPosition: gmap.CameraPosition(
        target: gmap.LatLng(widget.center.latitude, widget.center.longitude),
        zoom: widget.zoom,
      ),
      style: _style,
      mapType: gmap.MapType.normal,
      onMapCreated: _onMapCreated,
      // Cheaper than onCameraMove, which streams a message per frame: the
      // only thing we need back is the zoom the camera came to rest at.
      onCameraIdle: _syncZoom,
      markers: _markers,
      padding: EdgeInsets.only(bottom: widget.bottomPadding),
      compassEnabled: false,
      mapToolbarEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      scrollGesturesEnabled: widget.interactive,
      zoomGesturesEnabled: widget.interactive,
      onTap: widget.onMapTap == null ? null : (_) => widget.onMapTap!(),
    );
  }
}

// ---------------------------------------------------------------------------
// Marker bitmaps
// ---------------------------------------------------------------------------

/// Rendered marker images, keyed by appearance. Shared by every map in the
/// demo, so moving between screens never re-rasterises the same pin.
final _markerBitmaps = <String, gmap.BitmapDescriptor>{};

const _userDotKey = 'user-dot';

String _pinKey(MapPin pin) =>
    '${pin.color.toARGB32()}|${pin.pro}|${pin.icon?.codePoint}|'
    '${pin.iconSize}|${pin.selected}';

/// Geometry of a rasterised [StationPin].
///
/// The bitmap is the pin's 30×39 box plus the room its drop shadow and the PRO
/// badge need. The badge hangs off the top-right corner, so the artwork is not
/// centred in the bitmap — [anchor] points the Maps SDK at the teardrop's tip,
/// which is the pixel that has to sit on the coordinate.
class _PinBitmap {
  const _PinBitmap._();

  static const padTop = 10.0;
  static const padLeft = 8.0;
  static const padRight = 26.0;
  static const padBottom = 6.0;

  static const width = StationPin.width + padLeft + padRight;
  static const height = StationPin.height + padTop + padBottom;

  static const anchor = Offset(
    (padLeft + StationPin.width / 2) / width,
    (padTop + StationPin.height) / height,
  );

  /// Rasterisation factor. 3× covers every screen we demo on.
  static const scale = 3.0;
}

Future<gmap.BitmapDescriptor> _renderPinBitmap(MapPin pin) {
  // The whole bitmap scales with the pin, so [_PinBitmap.anchor] — a fraction
  // of it — still lands on the teardrop's tip.
  final scale = pin.scale;
  return _rasterise(
    size: Size(_PinBitmap.width * scale, _PinBitmap.height * scale),
    paint: (canvas) {
      canvas.scale(scale);
      canvas.translate(_PinBitmap.padLeft, _PinBitmap.padTop);
      _PinPainter(
        color: pin.color,
        filled: pin.icon == null || pin.selected,
      ).paint(canvas, const Size(StationPin.width, StationPin.height));
      if (pin.icon != null) _paintGlyph(canvas, pin);
      if (pin.pro) _paintProBadge(canvas);
    },
  );
}

Future<gmap.BitmapDescriptor> _renderUserDotBitmap() {
  return _rasterise(
    size: const Size(26, 26),
    paint: (canvas) {
      const centre = Offset(13, 13);
      canvas.drawCircle(
        centre.translate(0, 2),
        8,
        Paint()
          ..color = const Color(0x40000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(centre, 8, Paint()..color = Colors.white);
      canvas.drawCircle(centre, 5, Paint()..color = const Color(0xFF3A7BFF));
    },
  );
}

/// The glyph inside the white bubble — same metrics as the [Icon] the widget
/// pin uses: centred in the bubble's circular head.
void _paintGlyph(Canvas canvas, MapPin pin) {
  final icon = pin.icon!;
  final text = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: pin.iconSize,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        // Inverted on the selected pin: the bubble is now solid brand.
        color: pin.selected ? Colors.white : pin.color,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  text.paint(
    canvas,
    Offset(
      (StationPin.width - text.width) / 2,
      (StationPin.width - text.height) / 2,
    ),
  );
}

void _paintProBadge(Canvas canvas) {
  final text = TextPainter(
    text: const TextSpan(
      text: 'PRO',
      style: TextStyle(
        fontSize: 7.5,
        fontWeight: FontWeight.w800,
        color: Colors.white,
        height: 1.4,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  // Matches the widget badge: 4/1 padding, pushed 7 past the right edge and 6
  // above the top one.
  final rect = Rect.fromLTWH(
    StationPin.width + 7 - (text.width + 8),
    -6,
    text.width + 8,
    text.height + 2,
  );
  final badge = RRect.fromRectAndRadius(rect, const Radius.circular(3));

  canvas.drawRRect(
    badge.shift(const Offset(0, 1)),
    Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
  );
  canvas.drawRRect(badge, Paint()..color = AppColor.brandBright);
  text.paint(canvas, Offset(rect.left + 4, rect.top + 1));
}

Future<gmap.BitmapDescriptor> _rasterise({
  required Size size,
  required void Function(Canvas canvas) paint,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(_PinBitmap.scale);
  paint(canvas);

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (size.width * _PinBitmap.scale).ceil(),
    (size.height * _PinBitmap.scale).ceil(),
  );
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  return gmap.BitmapDescriptor.bytes(
    data!.buffer.asUint8List(),
    width: size.width,
    height: size.height,
    imagePixelRatio: _PinBitmap.scale,
  );
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
    this.selected = false,
    this.onTap,
  });

  static const width = 30.0;
  static const height = 39.0;

  final Color color;
  final bool pro;
  final IconData? icon;
  final double iconSize;

  /// Focused pin: the bubble inverts to a solid brand fill with a white glyph,
  /// and the whole teardrop grows.
  final bool selected;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final filled = icon == null || selected;
    final scale = selected ? MapPin.selectedScale : 1.0;
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
              child: Icon(
                icon,
                size: iconSize,
                color: selected ? Colors.white : color,
              ),
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

    // The marker slot is already sized for the grown pin, so the artwork is
    // scaled up inside it from the tip — the point the coordinate sits on.
    final sized = scale == 1
        ? pin
        : Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            // The marker hands down tight constraints for the grown box; the
            // artwork itself has to stay at its natural size or it would be
            // stretched and then scaled on top of that.
            child: OverflowBox(
              minWidth: 0,
              maxWidth: width,
              minHeight: 0,
              maxHeight: height,
              alignment: Alignment.bottomCenter,
              child: pin,
            ),
          );

    if (onTap == null) return sized;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: sized,
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
