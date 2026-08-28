import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// The back affordance used across the whole flow.
///
/// The chrome changes with the surface — a white disc floats over the map, a
/// bare glyph sits inside the dark vehicle header — but the metrics never do,
/// so the control keeps the same size and lands under the same thumb on every
/// screen.
class AppBackButton extends StatelessWidget {
  const AppBackButton({
    super.key,
    required this.onTap,
    this.filled = true,
    this.color = AppColor.textPrimary,
    this.tooltip,
  });

  /// Tap target. Also the height the host row has to reserve.
  static const double size = 44;

  /// Chevron glyph size.
  static const double iconSize = 28;

  final VoidCallback? onTap;

  /// White disc with a drop shadow (over the map) versus a bare glyph
  /// (inside a coloured header).
  final bool filled;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget button = Material(
      color: filled ? Colors.white : Colors.transparent,
      shape: const CircleBorder(),
      elevation: filled ? 3 : 0,
      shadowColor: const Color(0x33000000),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        splashColor: filled ? null : Colors.white.withValues(alpha: 0.18),
        highlightColor: filled ? null : Colors.white.withValues(alpha: 0.10),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(Icons.chevron_left, size: iconSize, color: color),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
