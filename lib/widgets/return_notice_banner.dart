import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../data/return_inspection.dart';

/// The follow-up push, delivered in-app (Figma 831:5789, 831:6645, 831:6684).
///
/// The boards show these on a lock screen, hours after the car was handed
/// back. What matters for the demo is the timing, not the surface: the release
/// page says nothing about damage, and the verdict arrives later — so the
/// banner is dropped into the root overlay once the flow is back on the map,
/// after the delay carried on the [ReturnNotice].
///
/// A real build swaps this for a scheduled local notification; the copy and
/// the timing model stay as they are.
abstract final class ReturnNoticeBanner {
  /// Queues every notice of a scenario onto [overlay].
  ///
  /// The caller resolves the overlay *before* it navigates away, because the
  /// route that finishes the return is gone by the time the first banner is
  /// due — and a Navigator's own context has no Overlay above it to find.
  static List<Timer> schedule(
    OverlayState overlay,
    List<ReturnNotice> notices,
  ) {
    return [
      for (final notice in notices)
        Timer(notice.delay, () {
          if (overlay.mounted) _present(overlay, notice);
        }),
    ];
  }

  static void _present(OverlayState overlay, ReturnNotice notice) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) =>
          _Banner(notice: notice, onDismissed: () => entry.remove()),
    );
    overlay.insert(entry);
  }
}

class _Banner extends StatefulWidget {
  const _Banner({required this.notice, required this.onDismissed});

  final ReturnNotice notice;
  final VoidCallback onDismissed;

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 260),
  );
  Timer? _autoHide;

  @override
  void initState() {
    super.initState();
    _slide.forward();
    _autoHide = Timer(const Duration(seconds: 7), _dismiss);
  }

  @override
  void dispose() {
    _autoHide?.cancel();
    _slide.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    _autoHide?.cancel();
    if (!mounted) return;
    await _slide.reverse();
    widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _slide, curve: Curves.easeOutCubic);

    return Positioned(
      left: 8,
      right: 8,
      top: MediaQuery.paddingOf(context).top + 6,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, -1.4),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(
          opacity: curve,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) < 0) _dismiss();
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1F000000),
                          blurRadius: 20,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: Image.asset(
                                'assets/images/irent_logo.png',
                                width: 20,
                                height: 20,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 7),
                            const Text(
                              'IRENT',
                              style: TextStyle(
                                fontSize: 13,
                                letterSpacing: 0.2,
                                color: Color(0xFF54545C),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              widget.notice.age,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF7C7C84),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.notice.body,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.42,
                            color: Color(0xFF14141A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
