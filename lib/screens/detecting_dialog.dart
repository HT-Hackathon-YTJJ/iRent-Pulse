import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/vehicle.dart';
import '../design/tokens.dart';

Future<void> showDetectingDialog(BuildContext context, VehicleProfile vehicle) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '偵測車款',
    barrierColor: const Color(0x66000000),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => _DetectingDialog(vehicle: vehicle),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.9, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _DetectingDialog extends StatefulWidget {
  const _DetectingDialog({required this.vehicle});

  final VehicleProfile vehicle;

  @override
  State<_DetectingDialog> createState() => _DetectingDialogState();
}

class _DetectingDialogState extends State<_DetectingDialog>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..forward();

  bool _done = false;

  @override
  void initState() {
    super.initState();
    _progress.addStatusListener((status) async {
      if (status != AnimationStatus.completed) return;
      setState(() => _done = true);
      _spin.stop();
      await Future<void>.delayed(const Duration(milliseconds: 950));
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _spin.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.dialog),
          clipBehavior: Clip.antiAlias,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 330),
            padding: const EdgeInsets.fromLTRB(24, 34, 24, 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 168,
                  height: 168,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_spin, _progress]),
                    builder: (context, _) => CustomPaint(
                      painter: _RingPainter(
                        spin: _spin.value,
                        progress: Curves.easeInOut.transform(_progress.value),
                        done: _done,
                      ),
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          child: _done
                              ? const Icon(
                                  Icons.check_rounded,
                                  key: ValueKey('ok'),
                                  size: 56,
                                  color: AppColor.success,
                                )
                              : Image.asset(
                                  'assets/images/irent_wordmark.png',
                                  key: const ValueKey('logo'),
                                  width: 108,
                                  fit: BoxFit.contain,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: _done
                      ? Column(
                          key: const ValueKey('result'),
                          children: [
                            const Text(
                              '已辨識車款',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                                color: AppColor.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.vehicle.fullName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 1.2,
                                color: AppColor.brand,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          '正在偵測本次駕駛車款',
                          key: ValueKey('detecting'),
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: AppColor.textPrimary,
                          ),
                        ),
                ),
                const SizedBox(height: 22),
                _StatusLine(
                  text: _done ? '車型與配備資料讀取完成' : '讀取車型與配備資料…',
                  color: _done ? AppColor.successText : AppColor.brandPressed,
                  pulsing: !_done,
                ),
                const SizedBox(height: 10),
                const _StatusLine(text: '車輛已開鎖', color: Color(0xFF1AA659)),
                const SizedBox(height: 24),
                const Text(
                  '系統將依車輛配備提供專屬操作說明',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: AppColor.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.text,
    required this.color,
    this.pulsing = false,
  });

  final String text;
  final Color color;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pulsing ? _Pulse(child: dot) : dot,
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.3, end: 1.0).animate(_c),
    child: widget.child,
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.spin,
    required this.progress,
    required this.done,
  });

  final double spin;
  final double progress;
  final bool done;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = AppColor.brandSoft,
    );

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = done ? AppColor.success : AppColor.brand;

    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, arc);

    if (!done) {
      // Leading scanner head.
      final sweep = spin * 2 * math.pi;
      canvas.drawArc(
        rect.deflate(14),
        sweep,
        math.pi / 3,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = AppColor.brand.withValues(alpha: 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.spin != spin || old.progress != progress || old.done != done;
}
