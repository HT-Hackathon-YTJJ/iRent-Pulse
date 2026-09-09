import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/return_inspection.dart';
import '../design/tokens.dart';
import '../l0/aim.dart';
import '../l0/capture_session.dart';
import '../l0/permissions.dart';
import '../services/return_session.dart';

/// The seven-slot viewfinder, and the place L0 actually runs.
///
/// Figma: 1019:1195 (拍照流程, the seven slots in order) and 1010:5678 /
/// 823:2794 / 813:2257 for 未對準 / 接近 / 已對準.
///
/// The alignment verdict is produced *while the frame is live*, which is the
/// whole point of 防亂拍: the badge, the centre pill and the silhouette all
/// read from one [AimVerdict] that [CaptureSession] computes off the camera's
/// image stream — car bbox from a COCO SSD MobileNet, sharpness from a
/// Laplacian, exposure from a luma histogram, and the torch from the same
/// histogram.
///
/// Two rules this screen must never break:
///
/// * **The shutter is never disabled, and it always exposes.** An off-target
///   frame is still taken; the screen freezes on it and raises the 判定未達標
///   panel, which offers 重拍 or 仍要送出 — and 仍要送出 files the frame that was
///   held, not a fresh one. A driver who cannot get a passing photo abandons
///   the return, and that costs more than a mediocre photo.
/// * **No camera is not a dead end.** On a desktop, on the web, or after a
///   denied permission the screen falls back to the scripted still and the
///   simulated verdict, so the flow can still be walked end to end.
class ReturnCaptureScreen extends StatefulWidget {
  const ReturnCaptureScreen({
    super.key,
    required this.spots,
    required this.taken,
    required this.pending,
    required this.onFinished,
    required this.onExit,
    this.frames = const {},
    this.onCaptured,
    this.session,
    this.expectedPlate = '',
    this.startMisaligned = false,
    this.onLongPressTitle,
    this.onNoCamera,
  });

  /// Every slot in the strip, in strip order.
  final List<CaptureSpot> spots;

  /// Slots that already hold a frame — they render as photos in the strip.
  final Set<CaptureSpot> taken;

  /// Slots this pass has to fill before the analysis runs.
  final Set<CaptureSpot> pending;

  /// Fires once the last pending slot has a frame.
  final VoidCallback onFinished;

  final VoidCallback onExit;

  /// Photos already taken this return, per slot. A retake remounts this screen,
  /// so the frames have to be handed back in or the filled tiles would drop to
  /// the no-camera stand-in halfway through the flow.
  final Map<CaptureSpot, File> frames;

  /// Reports each frame as it is taken, so the flow can keep [frames] current.
  final void Function(CaptureSpot spot, File file)? onCaptured;

  /// Live L1 screening. Null (or not [ReturnSession.live]) runs the scripted
  /// demo instead of calling the backend.
  final ReturnSession? session;

  /// The plate on the rental agreement, for the 車牌比對 on the four body
  /// corners. Empty switches the check off — a scripted run with no camera has
  /// nothing to read a plate from.
  final String expectedPlate;

  /// 情境⑥ opens with the frame off-target.
  final bool startMisaligned;

  /// Demo hook: long-pressing the header title opens the scenario picker.
  final VoidCallback? onLongPressTitle;

  /// Fires once if the camera could not be opened. Live screening has nothing
  /// to send in that case, so the flow drops back to the scripted board rather
  /// than reporting a verdict on photos that were never taken.
  final VoidCallback? onNoCamera;

  @override
  State<ReturnCaptureScreen> createState() => _ReturnCaptureScreenState();
}

// Offsets are the Figma frame's own (390 × 844, home indicator included), kept
// as distances from the bottom edge so the chrome stays put on taller phones.
const double _stripBottom = 175;
const double _stripSize = 72;
const double _stripGap = 8;

/// Decode width for a captured frame drawn into a 72pt strip tile — 512 covers
/// the square tile on a 3x screen whichever way round the photo is (a 16:9
/// landscape still lands 288 tall against the 225 the tile needs).
const int _tileDecodeWidth = 512;

/// Decode width for the held frame laid over the preview. Wider than any phone
/// this runs on, and a fifth of the full-size decode it replaces.
const int _heldDecodeWidth = 1440;
const double _tileRadius = 10.48;
const double _shutterSize = 77.255;

/// Clear space either side of the alignment silhouette, measured against the
/// visible camera frame rather than the screen.
const double _guideMargin = 14;

/// How far the ghosted 示意圖 carries.
///
/// This is the layer the driver actually aims with: at 0.42 the drawn bumper,
/// A-pillar and wheel arch are legible against a real car without hiding the
/// real one underneath. A flat silhouette can only say "car goes here"; the
/// render says "stand where this was drawn from".
const double _guideArtOpacity = 0.42;

/// The state colour is carried mostly by the outline. The fill is a whisper
/// under the render — enough to make 灰／黃／綠 readable at arm's length,
/// light enough to leave the frame underneath judgeable.
const double _guideFillOpacity = 0.14;

/// The outline is the part that has to survive a busy frame, so it is close to
/// solid where the fill is a wash.
const double _guideEdgeOpacity = 0.85;

/// Top and bottom of the band the silhouette is centred in, measured from the
/// safe-area top and the bottom edge. Keeps it clear of the 未對準 badge above
/// and the strip below at any screen height.
const double _guideBandTop = 76;
const double _guideBandBottom = _stripBottom + _stripSize + 28;

class _ReturnCaptureScreenState extends State<ReturnCaptureScreen>
    with TickerProviderStateMixin {
  late final Set<CaptureSpot> _taken = {...widget.taken};
  late final Set<CaptureSpot> _pending = {...widget.pending};
  late CaptureSpot _current = _firstPending;

  /// The photos behind the filled tiles, so the strip shows the driver's own
  /// frames rather than a stand-in. [ReturnSession] keeps the same files for
  /// the slots it screens; this map also covers the scripted runs, which have
  /// no session behind them but still have a camera.
  late final Map<CaptureSpot, File> _frames = {...widget.frames};

  late final CaptureSession _camera = CaptureSession(
    expectedPlate: widget.expectedPlate,
  );

  /// Only used when there is no camera to read.
  late final _AimSimulator _simulator = _AimSimulator(
    onChanged: (_) => setState(() {}),
    startMisaligned: widget.startMisaligned,
  );

  /// True while the 判定未達標 panel is up and the screen is frozen on [_held].
  bool _reviewing = false;

  /// The slot whose L1 verdict the driver has tapped open, if any.
  ///
  /// L1 answers while the driver is still walking round the car, so a photo
  /// they filed two slots ago can come back 需重拍 — and until now all that
  /// said so was an amber wash on a 72pt tile. The wash is a good alarm and a
  /// terrible explanation: it cannot say *why*, and tapping it simply switched
  /// slots, so the only way to find out was to shoot the frame again and hope.
  ///
  /// Tapping it now freezes the screen on the photo L1 is talking about and
  /// puts its own words over it, with the same two answers the shutter's own
  /// 判定未達標 panel offers — 重拍 or keep it. The driver reads the reason
  /// while looking at the frame it is about, which is the only place that
  /// sentence means anything.
  CaptureSpot? _inspecting;

  /// True while the live feed is standing still behind a panel — either the
  /// shutter's 判定未達標 or a slot the driver has tapped open.
  bool get _frozen => _reviewing || _inspecting != null;

  /// The photo laid over the preview, if the screen is holding one.
  File? get _frozenFrame {
    final held = _held;
    if (held != null) return held.file;
    final spot = _inspecting;
    if (spot == null) return null;
    return widget.session?.statusOf(spot).file ?? _frames[spot];
  }

  /// The photo taken when the shutter was pressed on a failing frame.
  ///
  /// 仍要送出 has to commit *this* — the frame the driver composed and chose —
  /// and not whatever the lens happens to be pointing at once they have read
  /// the panel and made up their mind. By then the phone is usually back at
  /// their side, so re-exposing on 仍要送出 filed a photo of the tarmac under a
  /// slot the driver believed held their bumper. The frame is taken on the
  /// press, every time; the verdict only decides whether it is filed straight
  /// away or held for a question.
  ///
  /// Null while reviewing means there was no camera to expose — the scripted
  /// fallback, whose viewfinder is a still to begin with.
  CapturedShot? _held;

  /// The verdict as it read at the moment of the press, so the badge, the
  /// silhouette and the panel's own hint stay on the held frame's result
  /// instead of tracking a stream the driver can no longer see.
  AimVerdict? _heldVerdict;

  /// Guards the shutter against a second press while a frame is being exposed,
  /// and against any press at all once the last slot is filled.
  bool _capturing = false;

  late final AnimationController _shutterFlash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// 收進格子 — the frame that was just taken, on its way to its tile.
  ///
  /// Between the shutter and the slot there was nothing: the photo simply was
  /// not on screen one frame and was a 72pt thumbnail the next, four slots
  /// along, while the strip also slid. Two things moved at once and neither
  /// explained the other. Flying the frame into the tile it landed in is the
  /// sentence "this photo went there", and it costs 420ms of a flow whose next
  /// step is the driver walking to the far corner of the car.
  CapturedShot? _flying;

  late final AnimationController _flight = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  CaptureSpot get _firstPending => widget.spots.firstWhere(
    _pending.contains,
    orElse: () => widget.spots.first,
  );

  /// The next slot with no photo in it, walking forward from [_current] and
  /// wrapping.
  ///
  /// Forward-and-wrapping rather than "the first empty one" because the driver
  /// is walking around a car and the strip is in the order of that walk. After
  /// re-shooting the 左前 corner, sending them back to a missed 加油卡 shot at
  /// the head of the strip means walking to the driver's door and back; the
  /// next corner is the one they are already facing. It still gets picked up —
  /// the wrap returns to it once the lap is done.
  CaptureSpot? get _nextEmpty {
    final spots = widget.spots;
    final start = spots.indexOf(_current);
    for (var step = 1; step <= spots.length; step++) {
      final spot = spots[(start + step) % spots.length];
      if (_pending.contains(spot)) return spot;
    }
    return null;
  }

  bool get _liveCamera => _camera.ready;

  AimVerdict get _verdict =>
      _heldVerdict ?? (_liveCamera ? _camera.verdict : _simulator.verdict);

  @override
  void initState() {
    super.initState();
    _camera.addListener(_onCameraTick);
    _simulator.start();
    unawaited(_camera.start());
  }

  @override
  void dispose() {
    _camera.removeListener(_onCameraTick);
    _camera.dispose();
    _simulator.dispose();
    _shutterFlash.dispose();
    _flight.dispose();
    super.dispose();
  }

  /// Guards [ReturnCaptureScreen.onNoCamera] against the per-frame tick.
  bool _reportedNoCamera = false;

  void _onCameraTick() {
    if (!mounted) return;
    setState(() {});
    if (_camera.failure != CaptureFailure.none && !_reportedNoCamera) {
      _reportedNoCamera = true;
      widget.onNoCamera?.call();
    }
  }

  /// The shutter is the driver's. L0 decides *whether it may fire*, never
  /// *when*.
  ///
  /// It used to fire itself the moment 連續確認 was met, and that is a worse
  /// deal than it looks: the frame the automation likes is rarely the frame
  /// the person was about to take, it goes off while they are still moving,
  /// and it takes away the one moment in the flow where they get to decide the
  /// photo is right. So the button is the only way a photo is taken.
  ///
  /// **The press always exposes a frame.** On green it goes straight into the
  /// slot; on amber or grey the screen freezes on it and raises 判定未達標,
  /// which still offers 仍要送出 — the shutter is gated, never locked. A driver
  /// who cannot get to green in a dark car park has to be able to finish the
  /// return; that costs one mediocre photo, and refusing costs the whole
  /// return. If that escape hatch is ever removed, it is this comment that has
  /// to change with it.
  ///
  /// Exposing on the press rather than on the answer matters more than it
  /// sounds. L0 can be wrong — a car perfectly inside the outline still reads
  /// 未對準 when the detector misses it in low light or against a dark wall —
  /// and that is precisely the case where the driver reaches for 仍要送出. If
  /// the photo were taken then, the frame they spent a minute lining up would
  /// be thrown away and replaced by whatever the phone saw as it came down.
  void _onShutter() {
    if (_frozen || _capturing) return;
    unawaited(_shutter());
  }

  /// Expose the frame, then decide what to do with it.
  Future<void> _shutter() async {
    final verdict = _verdict;
    setState(() => _capturing = true);

    // `manual: true` rides along on the photo as `capture_mode: manual` /
    // `bypassed`; L1 tightens its readability check on the strength of it. The
    // shutter is the only way a photo is taken here, so it is always set.
    CapturedShot? shot;
    if (_liveCamera) shot = await _camera.capture(manual: true);
    if (!mounted) return;

    _shutterFlash.forward(from: 0);

    if (verdict.isAcceptable) {
      // The shutter stays shut for the flight. It is a fifth of a second of a
      // press the driver has already made, and letting a second one through
      // mid-flight would file two photos into one slot.
      await _flyIntoSlot(shot);
      if (!mounted) return;
      _capturing = false;
      _commit(shot);
      return;
    }
    _capturing = false;

    // Held, not filed. The frame stays on screen under the panel so 重拍 and
    // 仍要送出 are answered about a photo the driver can actually see.
    setState(() {
      _reviewing = true;
      _held = shot;
      _heldVerdict = verdict;
    });
  }

  /// Play the frame into its tile. Returns once it has landed.
  ///
  /// Nothing to fly when there was no camera behind the press — the scripted
  /// fallback files a stand-in and the strip fills instantly, which is honest:
  /// no photo was taken, so none is shown travelling.
  Future<void> _flyIntoSlot(CapturedShot? shot) async {
    if (shot == null) return;
    setState(() => _flying = shot);
    await _flight.forward(from: 0);
  }

  /// Where the tile of the slot being shot sits, in screen coordinates.
  ///
  /// Computed rather than read off a `GlobalKey`: the strip always centres the
  /// active slot, and the slot being shot *is* the active one until [_commit]
  /// moves on. So the target is the middle of the rail, and it is known before
  /// the tile has been laid out — which is what lets the flight start on the
  /// same frame as the shutter flash instead of one after it.
  Rect _slotRect(Size screen) => Rect.fromLTWH(
    (screen.width - _stripSize) / 2,
    screen.height - _stripBottom - _stripSize,
    _stripSize,
    _stripSize,
  );

  /// File [shot] against the current slot and open the next one.
  void _commit(CapturedShot? shot) {
    final spot = _current;

    setState(() {
      _reviewing = false;
      _held = null;
      _heldVerdict = null;
      // Cleared in the same frame the tile is filled, so the flying copy is
      // replaced by the real one rather than blinking out before it.
      _flying = null;
      _pending.remove(spot);
      _taken.add(spot);
      if (shot != null) _frames[spot] = shot.file;
    });
    if (shot != null) widget.onCaptured?.call(spot, shot.file);

    final session = widget.session;
    if (shot != null && session != null && session.live) {
      // Not awaited: the next slot opens immediately and L1 reports back per
      // photo. That overlap is what makes a blocking screen bearable.
      unawaited(session.submit(spot, shot));
    }

    if (_pending.isEmpty) {
      // Nothing left to shoot, so the shutter stays shut while the page
      // changes under it. Let the flash land first.
      _capturing = true;
      Future<void>.delayed(const Duration(milliseconds: 260), () {
        if (mounted) widget.onFinished();
      });
      return;
    }

    final next = _nextEmpty;
    if (next == null) return;
    setState(() => _current = next);
    _camera.restartAim();
    _simulator.restart();
  }

  /// Move to [spot] because the driver tapped its tile.
  ///
  /// Any slot, at any time — including one that already holds a photo, which is
  /// how a retake works now. The strip used to be a read-out of a queue the
  /// driver could not steer: the only way back to a shot they were unhappy with
  /// was to finish all seven, wait for the analysis, and hope it flagged the one
  /// they already knew about. Tapping the tile is the obvious gesture and it now
  /// does the obvious thing.
  ///
  /// While a panel is up the tiles are inert. That panel is a question about a
  /// specific frame — and walking away from it would leave the photo it is
  /// about in limbo.
  ///
  /// A tile L1 has flagged is the exception to "tapping a tile switches slot":
  /// it opens [_inspecting] instead, because switching to it would throw away
  /// the one thing the driver tapped it to find out — *what was wrong with it*.
  /// The panel still gets them to the same place, with 重拍 doing the switch
  /// they would otherwise have got for free.
  void _selectSpot(CaptureSpot spot) {
    if (_frozen || _capturing) return;
    if (widget.session?.statusOf(spot).phase == SlotPhase.retake) {
      setState(() => _inspecting = spot);
      return;
    }
    if (spot == _current) return;
    setState(() => _current = spot);
    // A different slot is a different shot, so it gets the full strict window
    // rather than inheriting the relaxation clock the last one had earned.
    _camera.restartAim();
    _simulator.restart();
  }

  /// 重拍 on a flagged slot: back to the live feed, aimed at that slot.
  ///
  /// The rejected frame is dropped from the strip and from the session in the
  /// same breath, so the tile goes back to being an empty one. Leaving it
  /// filled would mean the driver walks away from a slot that still shows a
  /// photo and still shows an amber wash — and [_pending] would be the only
  /// thing that knew the difference.
  void _retakeInspected() {
    final spot = _inspecting;
    if (spot == null) return;
    setState(() {
      _inspecting = null;
      _current = spot;
      _pending.add(spot);
      _taken.remove(spot);
      _frames.remove(spot);
    });
    widget.session?.clear(spot);
    _camera.restartAim();
    _simulator.restart();
  }

  /// 保留 on a flagged slot: the photo stands, and the driver carries on.
  ///
  /// "Carries on" is the next slot with nothing in it, which is usually the one
  /// they were already pointed at — the flag arrived while they were lining up
  /// somewhere else, and answering it should not cost them that position. Only
  /// when the slot they are standing on is already filled does this move them
  /// forward, and then by the same walking order the strip is in.
  void _keepInspected() {
    setState(() => _inspecting = null);
    if (_pending.contains(_current)) return;
    final next = _nextEmpty;
    if (next == null) return;
    setState(() => _current = next);
    _camera.restartAim();
    _simulator.restart();
  }

  void _retake() {
    final rejected = _held;
    setState(() {
      _reviewing = false;
      _held = null;
      _heldVerdict = null;
    });
    if (rejected != null) {
      // A temp file nothing will ever read again — the slot it was taken for
      // is still pending and the next press writes a new one.
      unawaited(
        rejected.file.delete().catchError((Object _) => rejected.file),
      );
    }
    // Same slot, same attempt: the relaxation clock keeps running, so a
    // driver who has been fighting an unconvinced detector for ten seconds
    // does not get handed back the strict thresholds for pressing 重拍.
    _camera.restartAim(keepElapsed: true);
    _simulator.restart();
  }

  /// Where the live frame is drawn, in logical pixels.
  ///
  /// The preview used to be `BoxFit.cover`-ed across the whole screen, the way
  /// the Figma still is. On a 20:9 phone that throws away a third of a 4:3
  /// stream, and it throws it away *sideways* — which is the real reason the
  /// driver had to stand so far back, and the reason the alignment readout
  /// could not be trusted. L0 scores the car against the guide in **frame**
  /// coordinates; the driver aims against the guide in **screen** coordinates;
  /// and with a crop in between those two rectangles are not the same shape. A
  /// car sitting comfortably inside the outline on screen could be up against
  /// the edge of the frame the model saw.
  ///
  /// Drawing the frame whole removes the discrepancy instead of correcting for
  /// it: one rectangle, one coordinate space, and the driver sees exactly what
  /// the sensor — and therefore the detector — sees. The letterbox above and
  /// below is where the chrome already lived.
  Rect _previewRect(Size screen, double safeTop) {
    final aspect = _camera.previewAspect;
    if (!_liveCamera || aspect == null) return Offset.zero & screen;

    final width = screen.width;
    final height = width / aspect;
    if (height >= screen.height) {
      return Rect.fromLTWH(0, (screen.height - height) / 2, width, height);
    }
    // Centred on the band the driver is actually looking at rather than on the
    // screen, so the top bar and the strip sit in the letterbox.
    final bandTop = safeTop + _guideBandTop;
    final bandBottom = math.max(bandTop + 120, screen.height - _guideBandBottom);
    final top = ((bandTop + bandBottom) / 2 - height / 2).clamp(
      0.0,
      screen.height - height,
    );
    return Rect.fromLTWH(0, top, width, height);
  }

  /// Where the alignment silhouette is painted, in logical pixels.
  ///
  /// The shape keeps its own aspect and is centred in the visible frame. Slots
  /// that declare a [CaptureSpot.guideBleed] are laid out so the *visible* part
  /// still spans the frame's width and the remainder runs off the named edge —
  /// which is what makes the near corner of the car big enough to document.
  Rect _guideRect(Rect preview, CaptureSpot spot) {
    final bleed = spot.guideBleed.abs().clamp(0.0, 0.6);
    final span = math.max(40.0, preview.width - _guideMargin * 2);

    var width = span / (1 - bleed);
    var height = width / spot.guideAspect;

    final maxHeight = preview.height - 16;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * spot.guideAspect;
    }

    final visible = width * (1 - bleed);
    final left = spot.guideBleed < 0
        // Bleeding left: the right edge of the shape is the one that stays put.
        ? preview.right - _guideMargin - width
        : preview.left + _guideMargin + (span - visible) / 2;

    return Rect.fromLTWH(
      left,
      preview.top + (preview.height - height) / 2,
      width,
      height,
    );
  }

  /// The part of the guide the driver can see, in preview-normalised
  /// coordinates — the space [CaptureSession] scores boxes in.
  ///
  /// Clipping matters: a bleeding guide asks for a shape that is partly off
  /// screen, and the detector can only ever report the part that is on it. If
  /// the fill ratio were measured against the whole silhouette every bleeding
  /// slot would sit permanently on 再靠近一點.
  Rect? _guideInFrame(Rect preview, CaptureSpot spot) {
    if (preview.isEmpty) return null;
    final visible = _guideRect(preview, spot).intersect(preview);
    if (visible.width <= 0 || visible.height <= 0) return null;
    return Rect.fromLTRB(
      (visible.left - preview.left) / preview.width,
      (visible.top - preview.top) / preview.height,
      (visible.right - preview.left) / preview.width,
      (visible.bottom - preview.top) / preview.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final safeTop = media.padding.top;
    final verdict = _verdict;
    final spot = _current;
    final frozenFrame = _frozenFrame;
    final inspected = _inspecting;

    final preview = _previewRect(media.size, safeTop);

    if (_liveCamera) {
      _camera.configure(
        guideRect: _guideInFrame(preview, spot),
        requireGuide: spot.isCorner,
        guideAllowsEdge: spot.guideBleed != 0,
        slack: spot.aimSlack,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fromRect(
            rect: preview,
            child: _liveCamera
                ? _Preview(controller: _camera.controller!)
                : Image.asset(spot.viewfinderAsset, fit: BoxFit.cover),
          ),

          // The frame under the panel, laid over the still-running preview.
          //
          // Both panels are questions about a specific photo, so that photo is
          // what the driver reads them against — the one the shutter just took
          // for 判定未達標, the one L1 flagged for a tapped tile. Freezing here
          // rather than pausing the stream keeps the camera warm for the
          // retake that usually follows.
          if (frozenFrame != null)
            Positioned.fromRect(
              rect: preview,
              child: Image.file(
                frozenFrame,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: _heldDecodeWidth,
              ),
            ),

          // The alignment guide. It stays up in every state and changes colour
          // instead of disappearing — 灰 → 黃 → 綠 is the readout the driver is
          // steering by, and taking it away the moment it starts working leaves
          // them nothing to hold the frame against.
          //
          // The two cabin rows draw nothing at all: there is no repeatable
          // angle to ask for a hand's width from a seat back, so an outline
          // there is a shape nobody can match and the only thing it manages to
          // say is that they have failed to match it.
          // Not while a filed photo is up: the silhouette is a live aiming aid
          // and drawing it over a still asks the driver to line up a car that
          // has already been photographed.
          if (spot.guide != GuideStyle.none && inspected == null)
            Positioned.fromRect(
              rect: _guideRect(preview, spot),
              child: _AimGuide(spot: spot, state: verdict.state),
            ),

          const _Scrim(alignment: Alignment.topCenter, extent: 248),
          const _Scrim(alignment: Alignment.bottomCenter, extent: 272),

          Positioned(
            left: 0,
            right: 0,
            top: safeTop + 8,
            child: _TopBar(
              title: spot.screenTitle,
              subtitle: spot.instruction,
              onBack: widget.onExit,
              onLongPressTitle: widget.onLongPressTitle,
            ),
          ),

          // The badge reads the live stream, so it stands down over a filed
          // photo — 未對準 flickering above a still the driver took ten seconds
          // ago is a verdict about a frame nobody is looking at.
          if (inspected == null)
            Positioned(
              left: 16,
              top: safeTop + 97,
              child: _AimBadge(state: verdict.state),
            ),

          if (verdict.hint != null && !_frozen)
            Positioned(
              left: 0,
              right: 0,
              bottom: _stripBottom + _stripSize + 35,
              child: Center(child: _HintPill(text: verdict.hint!)),
            ),

          // In the bottom chrome, mirroring the flash button. The Figma board
          // floats it over the frame, which worked when the frame was
          // full-bleed; with the preview drawn whole it landed on top of the
          // guide and shoulder-to-shoulder with the hint pill.
          // Zoom and torch act on a stream the driver is no longer looking
          // at while the frame is held, so they stand down until 重拍 puts the
          // live feed back.
          if (!_frozen)
            Positioned(
              right: 24,
              bottom: 90,
              child: _ZoomCluster(
                zoom: _liveCamera ? _camera.zoom : 1,
                minZoom: _liveCamera ? _camera.minZoom : 1,
                maxZoom: _liveCamera ? _camera.maxZoom : 1,
                onChanged: (z) => unawaited(_camera.setZoom(z)),
              ),
            ),

          // One panel at a time, and the two that answer a gesture come first:
          // the driver pressed the shutter or tapped a tile, and an answer
          // about the camera being unavailable is not a reply to either.
          if (_reviewing)
            Positioned(
              left: 0,
              right: 0,
              bottom: _stripBottom + _stripSize + 140,
              child: Center(
                child: _BelowStandardPanel(
                  hint: verdict.hint,
                  wrongCar: verdict.state == AimState.wrongCar,
                  expectedPlate: widget.expectedPlate,
                  onSubmitAnyway: () => _commit(_held),
                  onRetake: _retake,
                ),
              ),
            )
          else if (inspected != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: _stripBottom + _stripSize + 140,
              child: Center(
                child: _FlaggedPhotoPanel(
                  spot: inspected,
                  status: widget.session?.statusOf(inspected),
                  onKeep: _keepInspected,
                  onRetake: _retakeInspected,
                ),
              ),
            )
          else if (_camera.failure != CaptureFailure.none)
            Positioned(
              left: 0,
              right: 0,
              bottom: _stripBottom + _stripSize + 140,
              child: Center(
                child: _CameraUnavailablePanel(
                  message: _camera.failureDetail ?? '相機無法使用。',
                  onOpenSettings: _camera.failure == CaptureFailure.permission
                      ? CapturePermissions.openSettings
                      : null,
                  onRetry: () => unawaited(_camera.start()),
                ),
              ),
            ),

          Positioned(
            left: 0,
            right: 0,
            bottom: _stripBottom,
            child: _ShotStrip(
              spots: widget.spots,
              taken: _taken,
              frames: _frames,
              current: _current,
              session: widget.session,
              onSelect: _frozen ? null : _selectSpot,
            ),
          ),

          if (!_frozen)
            Positioned(
              left: 54,
              bottom: 90,
              child: _FlashButton(
                on: _camera.torchOn,
                onTap: () => unawaited(_camera.toggleTorch()),
              ),
            ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 71.5,
            child: Center(
              // Kept in place rather than removed while the frame is held, so
              // the bottom of the screen does not rearrange itself under a
              // driver who is reading the panel — but faded and inert, because
              // the answer is now one of the panel's two buttons.
              child: IgnorePointer(
                ignoring: _frozen,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: _frozen ? 0.35 : 1,
                  child: _ShutterButton(
                    armed: verdict.isAcceptable,
                    onTap: _onShutter,
                  ),
                ),
              ),
            ),
          ),

          // 收進格子. Above the strip so it lands *on* the tile rather than
          // behind it, and below the flash so the two read as one action.
          if (_flying != null)
            AnimatedBuilder(
              animation: _flight,
              builder: (context, _) {
                final t = Curves.easeInOutCubic.transform(_flight.value);
                final rect = Rect.lerp(preview, _slotRect(media.size), t)!;
                return Positioned.fromRect(
                  rect: rect,
                  child: IgnorePointer(
                    child: Opacity(
                      // Fades only at the very end, where the tile underneath
                      // has already taken over the job of showing the photo.
                      opacity: 1 - (t * t * t) * 0.4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          lerpDouble(0, _tileRadius, t)!,
                        ),
                        child: Image.file(
                          _flying!.file,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          cacheWidth: _heldDecodeWidth,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

          // Shutter flash. Fully transparent at rest, so it is only ever
          // visible during the 260ms it is being played.
          AnimatedBuilder(
            animation: _shutterFlash,
            builder: (context, _) => IgnorePointer(
              child: Opacity(
                opacity: _shutterFlash.isDismissed
                    ? 0
                    : (1 - _shutterFlash.value) * 0.75,
                child: Container(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const String _assetRoot = 'assets/images/return/';

// ---------------------------------------------------------------------------

/// The live feed, drawn whole.
///
/// The caller has already sized the box to the stream's own aspect ratio (see
/// `_previewRect`), so filling it is a straight scale with no crop and no
/// distortion — every pixel the detector is looking at is a pixel the driver
/// can see, which is what makes the alignment readout mean anything.
class _Preview extends StatelessWidget {
  const _Preview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.value.previewSize;
    if (preview == null) return const ColoredBox(color: Colors.black);
    return FittedBox(
      fit: BoxFit.fill,
      child: SizedBox(
        // previewSize is reported in the sensor's own orientation, so the two
        // are swapped for the portrait viewfinder.
        width: preview.height,
        height: preview.width,
        child: CameraPreview(controller),
      ),
    );
  }
}

/// Stands in for the on-device check when there is no camera to read.
///
/// It walks 未對準 → 接近 → 已對準 and then holds, which is the sequence the
/// screens have to render on a desktop or on the web.
class _AimSimulator {
  _AimSimulator({required this.onChanged, this.startMisaligned = false});

  final ValueChanged<AimState> onChanged;
  final bool startMisaligned;

  AimState state = AimState.off;
  Timer? _timer;

  AimVerdict get verdict => AimVerdict(
    state: state,
    hint: state.hint,
    detectorAvailable: false,
  );

  void start() {
    state = AimState.off;
    if (startMisaligned) return; // 情境⑥ holds on 未對準 until the driver acts.
    _schedule();
  }

  void restart() {
    _timer?.cancel();
    start();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      state = state == AimState.off ? AimState.near : AimState.locked;
      onChanged(state);
      if (state != AimState.locked) _schedule();
    });
  }

  void dispose() => _timer?.cancel();
}

// ---------------------------------------------------------------------------

class _Scrim extends StatelessWidget {
  const _Scrim({required this.alignment, required this.extent});

  final Alignment alignment;
  final double extent;

  @override
  Widget build(BuildContext context) {
    final top = alignment == Alignment.topCenter;
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          height: extent,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: const [Color(0x4D000000), Color(0x00000000)],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.onLongPressTitle,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback? onLongPressTitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 24,
          child: Stack(
            children: [
              Positioned(
                left: 11.75,
                child: GestureDetector(
                  onTap: onBack,
                  behavior: HitTestBehavior.opaque,
                  child: const Icon(
                    Icons.arrow_back,
                    size: 24,
                    color: Colors.white,
                  ),
                ),
              ),
              Center(
                child: GestureDetector(
                  onLongPress: onLongPressTitle,
                  child: Text(title, style: ReturnText.cameraTitle),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Text(subtitle, style: ReturnText.cameraHint),
      ],
    );
  }
}

/// The car-shaped mask the driver lines the frame up with.
///
/// Two registered assets, both generated from the design repo's 72×72
/// `slot_paint_*.png` by `tool/gen_slot_assets.py`: a filled silhouette and its
/// outline. The blur baked into them is what stops a 19× enlargement arriving
/// as a staircase, and `srcIn` keeps that alpha while swapping the colour — so
/// one pair of assets covers all three states and the change between them can
/// be tweened.
///
/// The alignment guide: the 示意圖 ghosted over the live frame, a whisper of the
/// state colour behind it, and a solid outline on top.
///
/// The outline is not decoration. A flat wash vanishes against a bright wall,
/// which is the background 未對準 has to survive — and the render underneath,
/// being a grey car, needs something that is unambiguously *ours* around it.
class _AimGuide extends StatelessWidget {
  const _AimGuide({required this.spot, required this.state});

  final CaptureSpot spot;
  final AimState state;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: switch (spot.guide) {
        GuideStyle.none => const SizedBox.shrink(),
        GuideStyle.cardPouch => TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 240),
          tween: ColorTween(end: state.guideEdgeColor),
          builder: (context, color, _) => CustomPaint(
            painter: _CardPouchPainter(
              color: color ?? state.guideEdgeColor,
              textDirection: Directionality.of(context),
            ),
          ),
        ),
        GuideStyle.silhouette => Stack(
          fit: StackFit.expand,
          children: [
            _tinted(spot.guideAsset, state.guideColor, _guideFillOpacity),
            // Untinted: the whole point of the render is that its own shading
            // is what the driver matches the real car against.
            Opacity(
              opacity: _guideArtOpacity,
              child: Image.asset(spot.guideArtAsset, fit: BoxFit.fill),
            ),
            _tinted(
              spot.guideEdgeAsset,
              state.guideEdgeColor,
              _guideEdgeOpacity,
            ),
          ],
        ),
      },
    );
  }

  Widget _tinted(String asset, Color target, double opacity) {
    return TweenAnimationBuilder<Color?>(
      duration: const Duration(milliseconds: 240),
      tween: ColorTween(end: target),
      builder: (context, color, _) => Image.asset(
        asset,
        fit: BoxFit.fill,
        color: (color ?? target).withValues(alpha: opacity),
        colorBlendMode: BlendMode.srcIn,
      ),
    );
  }
}

/// 加油卡/停車卡 — the 遮陽板 card holder, drawn rather than photographed.
///
/// The other six slots aim at a *thing*, and a render of that thing is the
/// best instruction there is. This one aims at a **layout**: an iRent visor
/// pouch is a branded centre panel with a card pocket either side, and what
/// the driver has to get in frame is all three, the right way round. A render
/// of one particular pouch would say far more than that and be wrong about
/// most of it — the felt colour, the wear, which cards happen to be in it.
///
/// So it is three rounded rectangles and two labels. Vector code draws that
/// crisply at any size, needs no asset, and says exactly the thing that is
/// true of every car in the fleet.
class _CardPouchPainter extends CustomPainter {
  const _CardPouchPainter({required this.color, required this.textDirection});

  final Color color;
  final TextDirection textDirection;

  /// Where the two pocket seams fall across the pouch, as fractions of its
  /// width. Left pocket ~27%, branded centre ~45%, right pocket ~28% — the
  /// proportions of the real thing.
  static const double _leftSeam = 0.270;
  static const double _rightSeam = 0.722;

  static const double _dash = 7;
  static const double _gap = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4
      ..color = color.withValues(alpha: 0.92);

    final radius = Radius.circular(size.width * 0.035);
    final outer = RRect.fromRectAndRadius(Offset.zero & size, radius);
    _dashed(canvas, Path()..addRRect(outer), stroke);

    // The seams stop short of the frame's own corners so the two lines read as
    // dividers inside one pouch rather than as three separate boxes.
    final inset = size.height * 0.04;
    for (final x in [_leftSeam, _rightSeam]) {
      _dashed(
        canvas,
        Path()
          ..moveTo(size.width * x, inset)
          ..lineTo(size.width * x, size.height - inset),
        stroke,
      );
    }

    _label(canvas, '停車卡', Offset(size.width * _leftSeam / 2, size.height / 2));
    _label(
      canvas,
      '加油卡',
      Offset(size.width * (_rightSeam + 1) / 2, size.height / 2),
    );
  }

  /// Walk [path] and stroke only the on-segments.
  void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + _dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  void _label(Canvas canvas, String text, Offset centre) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 15,
          height: 1.2,
          color: color.withValues(alpha: 0.95),
          shadows: const [
            // The pouch is dark, the roof lining above it is not; without this
            // the labels vanish against whichever of the two they land on.
            Shadow(color: Color(0x99000000), blurRadius: 4),
          ],
        ),
      ),
      textDirection: textDirection,
    )..layout();
    painter.paint(
      canvas,
      centre - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_CardPouchPainter old) => old.color != color;
}

/// The shutter.
///
/// Dimmed until the frame is green, so the state of the check is legible from
/// the control the driver's thumb is already on rather than only from a badge
/// in the opposite corner. It is still tappable when dim — that raises
/// 判定未達標, which is the escape hatch. See `_onShutter`.
class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.armed, required this.onTap});

  final bool armed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: armed ? 1 : 0.45,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: armed
                ? [
                    BoxShadow(
                      color: AppColor.aimLocked.withValues(alpha: 0.55),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : const [],
          ),
          child: SvgPicture.asset(
            '${_assetRoot}icon_shutter.svg',
            width: _shutterSize,
            height: _shutterSize,
          ),
        ),
      ),
    );
  }
}

class _AimBadge extends StatelessWidget {
  const _AimBadge({required this.state});

  final AimState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      height: 38.178,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: state.color,
        borderRadius: BorderRadius.circular(8.81),
      ),
      child: Text(state.label, style: ReturnText.cameraBadge),
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: AppColor.glassPanel,
        borderRadius: BorderRadius.circular(17.965),
      ),
      child: Text(text, style: ReturnText.cameraPill),
    );
  }
}

/// The lens cluster on the right of the viewfinder.
///
/// Live, not decoration. It starts on 1×, which on a multi-lens Android phone
/// means the main camera at its own field of view — the fix for a viewfinder
/// that opened around 2× and sent the driver walking backwards across the car
/// park. Chips the device cannot reach are not drawn.
class _ZoomCluster extends StatelessWidget {
  const _ZoomCluster({
    required this.zoom,
    required this.minZoom,
    required this.maxZoom,
    required this.onChanged,
  });

  final double zoom;
  final double minZoom;
  final double maxZoom;
  final ValueChanged<double> onChanged;

  static const _steps = [0.5, 1.0, 2.0];

  @override
  Widget build(BuildContext context) {
    final available = _steps
        .where((z) => z >= minZoom - 0.01 && z <= maxZoom + 0.01)
        .toList();
    if (available.length < 2) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final step in available) ...[
          if (step != available.first) const SizedBox(width: 4),
          _chip(step, active: (zoom - step).abs() < 0.05),
        ],
      ],
    );
  }

  Widget _chip(double step, {required bool active}) {
    final label = step == step.roundToDouble()
        ? '${step.round()}'
        : '$step';
    return GestureDetector(
      onTap: () => onChanged(step),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: active ? 38.2 : 27,
        height: active ? 38.2 : 27,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // Translucent *white*, not black: these now sit in the letterbox
          // below the frame, where a 35%-black chip is invisible.
          color: Colors.white.withValues(alpha: active ? 0.22 : 0.14),
          shape: BoxShape.circle,
        ),
        child: Text(
          active ? '$label×' : label,
          style: TextStyle(
            fontSize: active ? 13 : 11,
            height: 1.4,
            letterSpacing: 0.5,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? AppColor.zoomActive : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _FlashButton extends StatelessWidget {
  const _FlashButton({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? Colors.white : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: on
            ? const Icon(Icons.bolt, size: 22, color: Colors.black)
            : SvgPicture.asset(
                '${_assetRoot}icon_flash.svg',
                width: 40,
                height: 40,
              ),
      ),
    );
  }
}

/// The 72pt frame strip: shot slots to the left of the active tile, still-empty
/// ones to the right.
///
/// Seven tiles are 552pt wide, so the strip is a rail rather than a row that
/// fits. The design pins the active tile to the centre line of the screen and
/// slides the rail under it, which means the driver's eye never has to hunt for
/// what they are shooting — it is always in the same place, with their own
/// finished photos trailing off one side.
class _ShotStrip extends StatelessWidget {
  const _ShotStrip({
    required this.spots,
    required this.taken,
    required this.frames,
    required this.current,
    this.session,
    this.onSelect,
  });

  final List<CaptureSpot> spots;
  final Set<CaptureSpot> taken;
  final Map<CaptureSpot, File> frames;
  final CaptureSpot current;
  final ReturnSession? session;

  /// Tapping a tile switches to that slot. Null while the 判定未達標 panel owns
  /// the screen.
  final void Function(CaptureSpot spot)? onSelect;

  @override
  Widget build(BuildContext context) {
    // OverflowBox centres the rail, so this is the distance from the rail's own
    // middle tile to the active one.
    final index = math.max(0, spots.indexOf(current));
    final shift =
        ((spots.length - 1) / 2 - index) * (_stripSize + _stripGap);

    final rail = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final spot in spots) ...[
          _Tile(
            spot: spot,
            captured: taken.contains(spot),
            active: spot == current,
            frame: session?.statusOf(spot).file ?? frames[spot],
            status: session?.statusOf(spot),
            onTap: onSelect == null ? null : () => onSelect!(spot),
          ),
          if (spot != spots.last) const SizedBox(width: _stripGap),
        ],
      ],
    );

    // The slide is applied *inside* the OverflowBox, to the rail itself.
    //
    // It used to wrap the OverflowBox instead, and that is what made 加油卡 and
    // 左後 — the two ends — untappable. A hit test entering a `Transform` is
    // pushed through the inverse transform before it reaches the child, so a
    // tap on a rail slid 240pt to the right arrived at the OverflowBox as a
    // tap 240pt to the *left* of where it landed — outside the OverflowBox's
    // own box, which is only ever screen-wide, so `RenderBox.hitTest`'s
    // `size.contains` rejected it before the tiles were ever asked. The centre
    // slots survived because their slide is small enough that the shifted
    // point still falls inside the screen; the neighbours of the ends were
    // half-tappable, which is the "有點 lag" — taps landing on the dead half of
    // a tile and doing nothing.
    //
    // Inside the OverflowBox the transform wraps the rail, whose own box is
    // the full 552pt of the seven tiles, so the shifted point stays within it
    // and every tile is hit-tested at the position it is actually drawn.
    final strip = ClipRect(
      child: SizedBox(
        height: _stripSize,
        child: OverflowBox(
          maxWidth: double.infinity,
          alignment: Alignment.center,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: shift),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            builder: (context, dx, child) =>
                Transform.translate(offset: Offset(dx, 0), child: child),
            child: rail,
          ),
        ),
      ),
    );

    // 逐張回報: the strip is where L1's per-photo answers land, so it has to
    // rebuild as they arrive rather than once at the end.
    final live = session;
    if (live == null) return strip;
    return AnimatedBuilder(animation: live, builder: (_, _) => strip);
  }
}

/// One slot in the strip, in one of the three states the design calls out:
///
/// * **shot** — the frame the driver actually took, full-bleed, no ring. Never
///   the `slot_real_*` composite from the design repo: those are mock-ups, and
///   showing one where a real photo belongs would misreport what was captured.
/// * **active** — the indicator artwork inside a white ring.
/// * **still to come** — the same indicator, no ring.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.spot,
    required this.captured,
    required this.active,
    this.frame,
    this.status,
    this.onTap,
  });

  final CaptureSpot spot;
  final bool captured;
  final bool active;

  /// Switch to this slot. Null while the tiles are inert.
  final VoidCallback? onTap;

  /// The photo taken for this slot, once there is one.
  final File? frame;

  final SlotStatus? status;

  @override
  Widget build(BuildContext context) {
    final file = frame;
    final tile = Container(
      width: _stripSize,
      height: _stripSize,
      decoration: BoxDecoration(
        color: captured && file != null ? null : const Color(0x807C7F84),
        borderRadius: BorderRadius.circular(_tileRadius),
      ),
      // The ring goes in **foreground**Decoration, over the photo.
      //
      // As part of `decoration` it was painted behind the child, and a
      // BoxDecoration with a border also insets the child by the stroke width
      // — so the photo sat in a 68pt square while the clip was still the 72pt
      // rounded rect. Along the straight edges that left the stroke showing;
      // at the four corners the photo's square edge ran out past the stroke's
      // curve and covered it. A ring with no corners reads as a rendering bug,
      // which is what it was.
      //
      // Painting it in front also stops the tile's contents resizing by 2pt
      // when it becomes the active one.
      foregroundDecoration: active
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(_tileRadius),
              border: Border.all(color: Colors.white, width: 2),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (file != null)
            // cacheWidth, or the tile decodes the camera's full-size JPEG —
            // ~4000x3000, 48 MB as ARGB — to fill 72pt. Seven of those do not
            // fit in the 100 MB image cache together, so every strip rebuild
            // evicted one and re-decoded another on the raster thread. That
            // was the other half of the "點擊有點 lag": the taps registered,
            // the frame they landed on took 200ms to draw.
            Image.file(file, fit: BoxFit.cover, cacheWidth: _tileDecodeWidth)
          else if (captured)
            // No camera behind this run, so there is no real frame to show.
            Image.asset(spot.shotAsset, fit: BoxFit.cover)
          else
            Image.asset(spot.slotIcon, fit: BoxFit.contain),
          // 需重拍 washes the whole tile amber rather than putting a button in
          // the corner of it.
          //
          // The corner used to hold a ↻ that looked like the control for
          // retaking — and was not one; the way back to a slot is tapping the
          // tile, which is true of all seven and needs no affordance of its
          // own. A button that is not a button in the one place the driver is
          // being asked to look is worse than no button. The wash is legible
          // from across the strip, marks the *photo* rather than a corner of
          // it, and leaves the whole 72pt tile as the one thing to press.
          if (status?.phase == SlotPhase.retake)
            Positioned.fill(
              child: ColoredBox(
                color: AppColor.aimNear.withValues(alpha: 0.42),
              ),
            ),
          if (status != null && status!.phase != SlotPhase.empty)
            Positioned(right: 3, bottom: 3, child: _SlotBadge(phase: status!.phase)),
        ],
      ),
    );

    if (onTap == null) return tile;
    // opaque so the whole 72pt tile is the target, including the transparent
    // parts of a slot indicator — at arm's length, on a phone the driver is
    // holding up, the icon's own ink is not a hit area anybody can find.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: tile,
    );
  }
}

/// ⏳ / ✓ / ! per slot — the whole point of reporting one photo at a time.
///
/// `failed` keeps its own grey ☁ and no amber wash. It does not mean the photo
/// is bad, it means nobody managed to look at it — there is nothing for the
/// driver to fix and marking it as if there were would send them back to
/// re-shoot a frame that was fine.
class _SlotBadge extends StatelessWidget {
  const _SlotBadge({required this.phase});

  final SlotPhase phase;

  @override
  Widget build(BuildContext context) {
    final (Color color, Widget child) = switch (phase) {
      SlotPhase.screening => (
        const Color(0xCC000000),
        const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.6, color: Colors.white),
        ),
      ),
      SlotPhase.passed => (
        AppColor.aimLocked,
        const Icon(Icons.check, size: 12, color: Colors.white),
      ),
      SlotPhase.retake => (
        AppColor.aimNear,
        const Icon(Icons.priority_high, size: 12, color: Colors.white),
      ),
      SlotPhase.failed => (
        AppColor.aimOff,
        const Icon(Icons.cloud_off, size: 11, color: Colors.white),
      ),
      SlotPhase.empty => (Colors.transparent, const SizedBox.shrink()),
    };

    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: child,
    );
  }
}

/// 判定未達標 — raised when the shutter fires on an off-target frame.
class _BelowStandardPanel extends StatelessWidget {
  const _BelowStandardPanel({
    required this.onSubmitAnyway,
    required this.onRetake,
    this.hint,
    this.wrongCar = false,
    this.expectedPlate = '',
  });

  final VoidCallback onSubmitAnyway;
  final VoidCallback onRetake;

  /// The plate read in frame is not this rental's. Gets its own headline
  /// because it is not a framing problem and 判定未達標 would send the driver
  /// looking for one.
  final bool wrongCar;

  final String expectedPlate;

  /// Whatever L0 was unhappy about at the moment of the press, so the panel
  /// says something useful instead of only "未達標" — and says it about the
  /// photo frozen behind it rather than about the live frame.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    if (wrongCar) {
      return _GlassPanel(
        title: '車輛不符',
        // The plate that *was* read is deliberately not quoted back. It has
        // been through the glyph folding in plate.dart, so `BCD` may read as
        // `8CD` — a mangled plate on screen next to a correct one reads as a
        // broken app, and argues with a driver who can see their own bumper.
        body: expectedPlate.isEmpty
            ? '畫面中的車牌與本次租借的車輛不符，請確認是否站在正確的車輛前。仍可直接送出，後續檢測會再確認一次。'
            : '畫面中的車牌與本次租借的 $expectedPlate 不符，請確認是否站在正確的車輛前。'
                  '仍可直接送出，後續檢測會再確認一次。',
        actions: [
          _PanelAction(label: '仍要送出', onTap: onSubmitAnyway, filled: false),
          _PanelAction(label: '重拍這張', onTap: onRetake, filled: true),
        ],
      );
    }
    return _GlassPanel(
      title: '判定未達標',
      body: hint == null
          ? '畫面為剛拍下的照片，仍可直接送出（不阻擋還車）。完成拍攝可獲得本次駕駛獎勵金。'
          : '$hint。畫面為剛拍下的照片，仍可直接送出（不阻擋還車）。',
      actions: [
        _PanelAction(label: '仍要送出', onTap: onSubmitAnyway, filled: false),
        _PanelAction(label: '重拍這張', onTap: onRetake, filled: true),
      ],
    );
  }
}

/// L1 flagged this photo — raised when the driver taps its amber tile.
///
/// The counterpart to [_BelowStandardPanel] and deliberately built out of the
/// same glass: both are "this frame has a problem, here are your two answers",
/// and the driver should not have to work out that they are different kinds of
/// question. What differs is who is asking. 判定未達標 is L0 talking about the
/// frame in the viewfinder a quarter of a second ago; this is L1 talking about
/// a photo that is already filed, so the choice is 保留 rather than 仍要送出 —
/// the photo has been submitted either way, and the only thing still open is
/// whether it gets replaced.
class _FlaggedPhotoPanel extends StatelessWidget {
  const _FlaggedPhotoPanel({
    required this.spot,
    required this.onKeep,
    required this.onRetake,
    this.status,
  });

  final CaptureSpot spot;
  final SlotStatus? status;
  final VoidCallback onKeep;
  final VoidCallback onRetake;

  /// L1's own words, and nothing invented on top of them.
  ///
  /// `assessable_reason` says what it could not see; `retake_hint` says what to
  /// do about it. Both are worth having and either can be missing, so they are
  /// joined rather than picked between — and when neither came back the panel
  /// still has to say something, because the tile is amber and the driver is
  /// standing there holding a phone.
  String get _body {
    final result = status?.result;
    final lines = <String>[
      if (result?.assessableReason != null) result!.assessableReason!
      else if (status?.message != null) status!.message!,
      if (result?.retakeHint != null) result!.retakeHint!,
    ];
    if (lines.isEmpty) return '這張照片可能無法判讀，建議重拍一張。保留也可以，不會擋下還車。';
    return '${lines.join('。')}。保留也可以，不會擋下還車。';
  }

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      title: '${spot.label}需要重拍',
      body: _body,
      actions: [
        _PanelAction(label: '保留', onTap: onKeep, filled: false),
        _PanelAction(label: '重拍', onTap: onRetake, filled: true),
      ],
    );
  }
}

/// Shown instead of the live feed when there is no camera to open.
class _CameraUnavailablePanel extends StatelessWidget {
  const _CameraUnavailablePanel({
    required this.message,
    required this.onRetry,
    this.onOpenSettings,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      title: '無法開啟相機',
      body: '$message\n仍可依畫面指示完成還車流程。',
      actions: [
        if (onOpenSettings != null)
          _PanelAction(label: '前往設定', onTap: onOpenSettings!, filled: false),
        _PanelAction(label: '重試', onTap: onRetry, filled: true),
      ],
    );
  }
}

class _PanelAction {
  const _PanelAction({
    required this.label,
    required this.onTap,
    required this.filled,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final String body;
  final List<_PanelAction> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 329.357,
      padding: const EdgeInsets.all(14.97),
      decoration: BoxDecoration(
        color: AppColor.glassPanel,
        border: Border.all(color: AppColor.glassPanelBorder, width: 1.497),
        borderRadius: BorderRadius.circular(16.468),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16.468,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            body,
            style: const TextStyle(
              fontSize: 14.971,
              height: 21.333 / 14.971,
              color: AppColor.glassBody,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              for (final action in actions) ...[
                Expanded(child: _panelButton(action)),
                if (action != actions.last) const SizedBox(width: 9),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _panelButton(_PanelAction action) {
    return GestureDetector(
      onTap: action.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44.912,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: action.filled ? Colors.white : Colors.transparent,
          border: action.filled
              ? null
              : Border.all(color: AppColor.glassGhostRing, width: 2.994),
          borderRadius: BorderRadius.circular(_tileRadius),
        ),
        child: Text(
          action.label,
          style: TextStyle(
            fontSize: 14.971,
            fontWeight: FontWeight.w700,
            color: action.filled
                ? AppColor.glassSolidLabel
                : AppColor.glassGhostLabel,
          ),
        ),
      ),
    );
  }
}
