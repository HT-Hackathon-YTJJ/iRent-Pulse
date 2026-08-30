import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;

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
/// * **The shutter is never disabled.** An off-target frame raises the 判定未達標
///   panel, which still offers 仍要送出. A driver who cannot get a passing photo
///   abandons the return, and that costs more than a mediocre photo.
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
const double _tileRadius = 10.48;
const double _shutterSize = 77.255;

/// Clear space either side of the alignment silhouette.
///
/// Figma lets the silhouette run off the edge of the frame, which reads as
/// "put the car half out of shot". The guide is what the driver is being asked
/// to fill, so it has to be a shape they can actually fill — entirely on
/// screen, with room to spare.
const double _guideMargin = 24;

/// How far the silhouette's tint carries. Enough to read over a bright white
/// car in daylight, light enough to leave the frame underneath judgeable.
const double _guideOpacity = 0.3;

/// The outline is the part that has to survive a busy frame, so it is close to
/// solid where the fill is a wash.
const double _guideEdgeOpacity = 0.8;

/// Top and bottom of the band the silhouette is centred in, measured from the
/// safe-area top and the bottom edge. Keeps it clear of the 未對準 badge above
/// and the hint pill below at any screen height.
const double _guideBandTop = 145;
const double _guideBandBottom = _stripBottom + _stripSize + 60;

class _ReturnCaptureScreenState extends State<ReturnCaptureScreen>
    with SingleTickerProviderStateMixin {
  late final Set<CaptureSpot> _taken = {...widget.taken};
  late final Set<CaptureSpot> _pending = {...widget.pending};
  late CaptureSpot _current = _firstPending;

  /// The photos behind the filled tiles, so the strip shows the driver's own
  /// frames rather than a stand-in. [ReturnSession] keeps the same files for
  /// the slots it screens; this map also covers the scripted runs, which have
  /// no session behind them but still have a camera.
  late final Map<CaptureSpot, File> _frames = {...widget.frames};

  final CaptureSession _camera = CaptureSession();

  /// Only used when there is no camera to read.
  late final _AimSimulator _simulator = _AimSimulator(
    onChanged: (_) => setState(() {}),
    startMisaligned: widget.startMisaligned,
  );

  /// Non-null while the 判定未達標 panel is up.
  bool _reviewing = false;

  /// Guards against the auto-shutter firing twice on consecutive good frames.
  bool _capturing = false;

  late final AnimationController _shutterFlash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  CaptureSpot get _firstPending => widget.spots.firstWhere(
    _pending.contains,
    orElse: () => widget.spots.first,
  );

  bool get _liveCamera => _camera.ready;

  AimVerdict get _verdict =>
      _liveCamera ? _camera.verdict : _simulator.verdict;

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
    // 連續確認 has been met — this is the automatic shutter the spec asks for.
    // 情境⑥ deliberately never reaches it, because its frame never settles.
    if (_liveCamera && !_reviewing && !_capturing && _camera.verdict.isAcceptable) {
      unawaited(_capture(manual: false));
    }
  }

  void _onShutter() {
    if (_reviewing || _capturing) return;
    if (_verdict.isAcceptable) {
      unawaited(_capture(manual: false));
    } else {
      setState(() => _reviewing = true);
    }
  }

  /// [manual] is true when the driver overrode a failing check. It rides along
  /// on the photo as `capture_mode: manual` / `bypassed`, and L1 tightens its
  /// readability check on the strength of it.
  Future<void> _capture({required bool manual}) async {
    if (_capturing) return;
    _capturing = true;
    final spot = _current;

    CapturedShot? shot;
    if (_liveCamera) shot = await _camera.capture(manual: manual);
    if (!mounted) {
      _capturing = false;
      return;
    }

    _shutterFlash.forward(from: 0);
    setState(() {
      _reviewing = false;
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
      // Let the shutter flash land before the page changes under it.
      Future<void>.delayed(const Duration(milliseconds: 260), () {
        if (mounted) widget.onFinished();
      });
      return;
    }

    setState(() => _current = _firstPending);
    _camera.restartAim();
    _simulator.restart();
    _capturing = false;
  }

  void _retake() {
    setState(() => _reviewing = false);
    _camera.restartAim();
    _simulator.restart();
  }

  /// Where the alignment silhouette is painted, in logical pixels.
  ///
  /// The shape keeps its own aspect, is inset by [_guideMargin] on both sides,
  /// and is centred in the band between the badge and the hint pill. On a short
  /// screen the height runs out first and the width follows it down, so the
  /// guide never grows into the chrome at either end.
  Rect _guideRect(Size screen, double safeTop, CaptureSpot spot) {
    final top = safeTop + _guideBandTop;
    final bottom = math.max(top + 80, screen.height - _guideBandBottom);

    var width = screen.width - _guideMargin * 2;
    var height = width / spot.guideAspect;
    if (height > bottom - top) {
      height = bottom - top;
      width = height * spot.guideAspect;
    }
    return Rect.fromLTWH(
      (screen.width - width) / 2,
      top + (bottom - top - height) / 2,
      width,
      height,
    );
  }

  /// The same rect in screen-normalised coordinates, which is what the IoU
  /// check needs. One source of truth: the overlap L0 scores is measured
  /// against exactly the shape the driver is looking at.
  Rect _guideOnScreen(Size screen, double safeTop, CaptureSpot spot) {
    final rect = _guideRect(screen, safeTop, spot);
    return Rect.fromLTRB(
      rect.left / screen.width,
      rect.top / screen.height,
      rect.right / screen.width,
      rect.bottom / screen.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final safeTop = media.padding.top;
    final verdict = _verdict;
    final spot = _current;

    if (_liveCamera) {
      _camera.configure(
        guideRect: _camera.frameRectFor(
          _guideOnScreen(media.size, safeTop, spot),
          media.size,
        ),
        requireGuide: spot.isCorner,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_liveCamera)
            _Preview(controller: _camera.controller!)
          else
            Image.asset(spot.viewfinderAsset, fit: BoxFit.cover),

          // The alignment silhouette. It stays up in every state and changes
          // colour instead of disappearing — 灰 → 黃 → 綠 is the readout the
          // driver is steering by, and taking it away the moment it starts
          // working leaves them nothing to hold the frame against.
          Positioned.fromRect(
            rect: _guideRect(media.size, safeTop, spot),
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

          Positioned(
            left: 16,
            top: safeTop + 97,
            child: _AimBadge(state: verdict.state),
          ),

          if (verdict.hint != null && !_reviewing)
            Positioned(
              left: 0,
              right: 0,
              bottom: _stripBottom + _stripSize + 35,
              child: Center(child: _HintPill(text: verdict.hint!)),
            ),

          const Positioned(right: 16, bottom: 290, child: _ZoomCluster()),

          if (_camera.failure != CaptureFailure.none)
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
              )
            )
          else if (_reviewing)
            Positioned(
              left: 0,
              right: 0,
              bottom: _stripBottom + _stripSize + 140,
              child: Center(
                child: _BelowStandardPanel(
                  hint: verdict.hint,
                  onSubmitAnyway: () => unawaited(_capture(manual: true)),
                  onRetake: _retake,
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
            ),
          ),

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
              child: GestureDetector(
                onTap: _onShutter,
                behavior: HitTestBehavior.opaque,
                child: SvgPicture.asset(
                  '${_assetRoot}icon_shutter.svg',
                  width: _shutterSize,
                  height: _shutterSize,
                ),
              ),
            ),
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

/// The live feed, cropped to fill the way the Figma still does.
class _Preview extends StatelessWidget {
  const _Preview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.value.previewSize;
    if (preview == null) return const ColoredBox(color: Colors.black);
    return FittedBox(
      fit: BoxFit.cover,
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
/// The outline is not decoration. A flat wash at [_guideOpacity] vanishes
/// against a bright wall, which is the background 未對準 has to survive.
class _AimGuide extends StatelessWidget {
  const _AimGuide({required this.spot, required this.state});

  final CaptureSpot spot;
  final AimState state;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _tinted(spot.guideAsset, state.guideColor, _guideOpacity),
          _tinted(spot.guideEdgeAsset, state.guideEdgeColor, _guideEdgeOpacity),
        ],
      ),
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

/// The 0.5× / 1× cluster on the right of the viewfinder.
class _ZoomCluster extends StatelessWidget {
  const _ZoomCluster();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _chip(
          size: 23.8,
          label: '0.5',
          style: const TextStyle(
            fontSize: 10,
            height: 1.4,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 4),
        _chip(
          size: 38.2,
          label: '1',
          style: const TextStyle(
            fontSize: 16,
            height: 1.4,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            color: AppColor.zoomActive,
          ),
        ),
      ],
    );
  }

  Widget _chip({
    required double size,
    required String label,
    required TextStyle style,
  }) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0x59000000),
        shape: BoxShape.circle,
      ),
      child: Text(label, style: style),
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
  });

  final List<CaptureSpot> spots;
  final Set<CaptureSpot> taken;
  final Map<CaptureSpot, File> frames;
  final CaptureSpot current;
  final ReturnSession? session;

  @override
  Widget build(BuildContext context) {
    // OverflowBox centres the rail, so this is the distance from the rail's own
    // middle tile to the active one.
    final index = math.max(0, spots.indexOf(current));
    final shift =
        ((spots.length - 1) / 2 - index) * (_stripSize + _stripGap);

    final strip = ClipRect(
      child: SizedBox(
        height: _stripSize,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: shift),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, dx, child) =>
              Transform.translate(offset: Offset(dx, 0), child: child),
          child: OverflowBox(
            maxWidth: double.infinity,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final spot in spots) ...[
                  _Tile(
                    spot: spot,
                    captured: taken.contains(spot),
                    active: spot == current,
                    frame: session?.statusOf(spot).file ?? frames[spot],
                    status: session?.statusOf(spot),
                  ),
                  if (spot != spots.last) const SizedBox(width: _stripGap),
                ],
              ],
            ),
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
  });

  final CaptureSpot spot;
  final bool captured;
  final bool active;

  /// The photo taken for this slot, once there is one.
  final File? frame;

  final SlotStatus? status;

  @override
  Widget build(BuildContext context) {
    final file = frame;
    return Container(
      width: _stripSize,
      height: _stripSize,
      decoration: BoxDecoration(
        color: captured && file != null ? null : const Color(0x807C7F84),
        borderRadius: BorderRadius.circular(_tileRadius),
        border: active ? Border.all(color: Colors.white, width: 2) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (file != null)
            Image.file(file, fit: BoxFit.cover)
          else if (captured)
            // No camera behind this run, so there is no real frame to show.
            Image.asset(spot.shotAsset, fit: BoxFit.cover)
          else
            Image.asset(spot.slotIcon, fit: BoxFit.contain),
          if (status != null && status!.phase != SlotPhase.empty)
            Positioned(right: 3, bottom: 3, child: _SlotBadge(phase: status!.phase)),
        ],
      ),
    );
  }
}

/// ⏳ / ✓ / ✗ per slot — the whole point of reporting one photo at a time.
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
        const Icon(Icons.refresh, size: 12, color: Colors.white),
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
  });

  final VoidCallback onSubmitAnyway;
  final VoidCallback onRetake;

  /// Whatever L0 is actually unhappy about, so the panel says something useful
  /// instead of only "未達標".
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      title: '判定未達標',
      body: hint == null
          ? '照片已保留，仍可送出（不阻擋還車）。完成拍攝可獲得本次駕駛獎勵金。'
          : '$hint。照片已保留，仍可送出（不阻擋還車）。',
      actions: [
        _PanelAction(label: '仍要送出', onTap: onSubmitAnyway, filled: false),
        _PanelAction(label: '重拍這張', onTap: onRetake, filled: true),
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
