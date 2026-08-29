import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/return_inspection.dart';
import '../design/tokens.dart';

/// 車身拍照 / 車內裝 viewfinder (Figma 823:2794, 813:2257, 843:694).
///
/// The alignment verdict is produced *while the frame is live* — that is the
/// whole point of the 防亂拍 design — so the badge, the centre pill and the
/// ghost outline all read from one [AimState] that a detector owns. Until a
/// real on-device model exists, [_AimSimulator] walks that state so the rest of
/// the screen can be built and demoed against its final shape.
///
/// The shutter is never disabled. An off-target frame raises the 判定未達標
/// panel, which still offers 仍要送出 — returning the car is never blocked.
class ReturnCaptureScreen extends StatefulWidget {
  const ReturnCaptureScreen({
    super.key,
    required this.spots,
    required this.taken,
    required this.pending,
    required this.onFinished,
    required this.onExit,
    this.startMisaligned = false,
    this.onLongPressTitle,
  });

  /// Every slot in the strip, in strip order.
  final List<CaptureSpot> spots;

  /// Slots that already hold a frame — they render as photos in the strip.
  final Set<CaptureSpot> taken;

  /// Slots this pass has to fill before the analysis runs.
  final Set<CaptureSpot> pending;

  /// Fires once the last pending slot has a frame, or when 完成 is tapped.
  final VoidCallback onFinished;

  final VoidCallback onExit;

  /// 情境⑥ opens with the frame off-target.
  final bool startMisaligned;

  /// Demo hook: long-pressing the header title opens the scenario picker.
  final VoidCallback? onLongPressTitle;

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

class _ReturnCaptureScreenState extends State<ReturnCaptureScreen>
    with SingleTickerProviderStateMixin {
  late final Set<CaptureSpot> _taken = {...widget.taken};
  late final Set<CaptureSpot> _pending = {...widget.pending};
  late CaptureSpot _current = _firstPending;
  late final _AimSimulator _aim = _AimSimulator(
    onChanged: (_) => setState(() {}),
    startMisaligned: widget.startMisaligned,
  );

  /// Non-null while the 判定未達標 panel is up.
  bool _reviewing = false;
  bool _flashOn = false;

  late final AnimationController _shutterFlash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  CaptureSpot get _firstPending => widget.spots.firstWhere(
    _pending.contains,
    orElse: () => widget.spots.first,
  );

  int get _takenCorners => _taken.where((s) => s.isCorner).length;

  @override
  void initState() {
    super.initState();
    _aim.start();
  }

  @override
  void dispose() {
    _aim.dispose();
    _shutterFlash.dispose();
    super.dispose();
  }

  void _onShutter() {
    if (_reviewing) return;
    if (_aim.state.isAcceptable) {
      _capture();
    } else {
      setState(() => _reviewing = true);
    }
  }

  void _capture() {
    _shutterFlash.forward(from: 0);
    setState(() {
      _reviewing = false;
      _pending.remove(_current);
      _taken.add(_current);
      if (_pending.isEmpty) return;
      _current = _firstPending;
      _aim.restart();
    });
    if (_pending.isEmpty) {
      // Let the shutter flash land before the page changes under it.
      Future<void>.delayed(const Duration(milliseconds: 260), () {
        if (mounted) widget.onFinished();
      });
    }
  }

  void _retake() {
    setState(() => _reviewing = false);
    _aim.restart();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final safeTop = media.padding.top;
    final aim = _aim.state;
    final spot = _current;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(spot.viewfinderAsset, fit: BoxFit.cover),

          // 對齊灰色輪廓線 — the guide only helps while the car is not yet
          // framed, so it goes away as soon as the check reaches 接近. Figma
          // hangs it at 198.78 of the 844pt frame, full-bleed.
          if (aim == AimState.off && spot.isCorner)
            Positioned(
              left: 0,
              right: 0,
              top: media.size.height * (198.78 / 844),
              child: Opacity(
                // Figma composites a grey-on-grey still at 43%. The exported
                // asset here is keyed to transparency instead, so the same
                // contrast lands at a higher alpha — 43% on top of that would
                // wash the guide out entirely.
                opacity: 0.85,
                child: Image.asset(
                  '${_assetRoot}camera_ghost.png',
                  fit: BoxFit.fitWidth,
                ),
              ),
            ),

          const _Scrim(alignment: Alignment.topCenter, extent: 248),
          const _Scrim(alignment: Alignment.bottomCenter, extent: 272),

          Positioned(
            left: 0,
            right: 0,
            top: safeTop + 8,
            child: _TopBar(
              title: spot.screenTitle,
              subtitle: _takenCorners == 0 || !spot.isCorner
                  ? spot.instruction
                  : '請拍攝其他照片（$_takenCorners/4）',
              onBack: widget.onExit,
              onDone: widget.onFinished,
              onLongPressTitle: widget.onLongPressTitle,
            ),
          ),

          Positioned(
            left: 16,
            top: safeTop + 97,
            child: _AimBadge(state: aim),
          ),

          if (aim.hint != null && !_reviewing)
            Positioned(
              left: 0,
              right: 0,
              bottom: _stripBottom + _stripSize + 35,
              child: Center(child: _HintPill(text: aim.hint!)),
            ),

          const Positioned(right: 16, bottom: 290, child: _ZoomCluster()),

          if (_reviewing)
            Positioned(
              left: 0,
              right: 0,
              bottom: _stripBottom + _stripSize + 140,
              child: Center(
                child: _BelowStandardPanel(
                  onSubmitAnyway: _capture,
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
              current: _current,
            ),
          ),

          Positioned(
            left: 54,
            bottom: 90,
            child: _FlashButton(
              on: _flashOn,
              onTap: () => setState(() => _flashOn = !_flashOn),
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

/// Stands in for the on-device alignment check.
///
/// It walks 未對準 → 接近 → 已對準 and then holds, which is the sequence the
/// screens have to render; a real detector replaces [start]/[restart] without
/// touching the widget tree.
class _AimSimulator {
  _AimSimulator({required this.onChanged, this.startMisaligned = false});

  final ValueChanged<AimState> onChanged;
  final bool startMisaligned;

  AimState state = AimState.off;
  Timer? _timer;

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
    required this.onDone,
    this.onLongPressTitle,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback onDone;
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
              Positioned(
                right: 17,
                top: 3,
                child: GestureDetector(
                  onTap: onDone,
                  behavior: HitTestBehavior.opaque,
                  child: const Text('完成', style: ReturnText.cameraAction),
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

/// The 72pt frame strip. It runs 392pt wide at five slots, which is why the
/// design lets it bleed past the screen edges rather than shrinking the tiles.
class _ShotStrip extends StatelessWidget {
  const _ShotStrip({
    required this.spots,
    required this.taken,
    required this.current,
  });

  final List<CaptureSpot> spots;
  final Set<CaptureSpot> taken;
  final CaptureSpot current;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        height: _stripSize,
        child: OverflowBox(
          maxWidth: double.infinity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final spot in spots) ...[
                _Tile(
                  spot: spot,
                  captured: taken.contains(spot),
                  active: spot == current,
                ),
                if (spot != spots.last) const SizedBox(width: _stripGap),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.spot,
    required this.captured,
    required this.active,
  });

  final CaptureSpot spot;
  final bool captured;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _stripSize,
      height: _stripSize,
      decoration: BoxDecoration(
        color: captured ? null : const Color(0x807C7F84),
        borderRadius: BorderRadius.circular(_tileRadius),
        border: active ? Border.all(color: Colors.white, width: 2) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: captured
          ? Image.asset(spot.shotAsset, fit: BoxFit.cover)
          : Center(
              child: SizedBox(
                width: 55,
                height: 37,
                child: Image.asset(spot.placeholderAsset, fit: BoxFit.contain),
              ),
            ),
    );
  }
}

/// 判定未達標 — raised when the shutter fires on an off-target frame.
class _BelowStandardPanel extends StatelessWidget {
  const _BelowStandardPanel({
    required this.onSubmitAnyway,
    required this.onRetake,
  });

  final VoidCallback onSubmitAnyway;
  final VoidCallback onRetake;

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
          const Text(
            '判定未達標',
            style: TextStyle(
              fontSize: 16.468,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            '照片已保留，仍可送出（不阻擋還車）。完成拍攝可獲得本次駕駛獎勵金。',
            style: TextStyle(
              fontSize: 14.971,
              height: 21.333 / 14.971,
              color: AppColor.glassBody,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _panelButton(
                  label: '仍要送出',
                  onTap: onSubmitAnyway,
                  filled: false,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _panelButton(
                  label: '重拍這張',
                  onTap: onRetake,
                  filled: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panelButton({
    required String label,
    required VoidCallback onTap,
    required bool filled,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44.912,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? Colors.white : Colors.transparent,
          border: filled
              ? null
              : Border.all(color: AppColor.glassGhostRing, width: 2.994),
          borderRadius: BorderRadius.circular(_tileRadius),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14.971,
            fontWeight: FontWeight.w700,
            color: filled ? AppColor.glassSolidLabel : AppColor.glassGhostLabel,
          ),
        ),
      ),
    );
  }
}
