import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// The pill button used across the whole flow (Figma: "紅色按鍵").
/// Fixed 236x45 in the design; here it stretches but is capped so it stays
/// centred and balanced on wider screens.
class PillButton extends StatefulWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColor.brand,
    this.pressedColor,
    this.foreground = AppColor.textInverse,
    this.outlined = false,
    this.maxWidth = 236,
    this.height = 46,
    this.textStyle,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color? pressedColor;
  final Color foreground;
  final bool outlined;
  final double maxWidth;
  final double height;
  final TextStyle? textStyle;
  final IconData? icon;

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final base = widget.outlined ? Colors.transparent : widget.color;
    final pressed = widget.outlined
        ? widget.color.withValues(alpha: 0.08)
        : (widget.pressedColor ??
              Color.lerp(widget.color, Colors.black, 0.18)!);
    final fg = widget.outlined ? widget.color : widget.foreground;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: enabled ? () => setState(() => _down = false) : null,
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _down ? 0.97 : 1,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 110),
              height: widget.height,
              width: double.infinity,
              decoration: BoxDecoration(
                color: enabled ? (_down ? pressed : base) : AppColor.track,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: widget.outlined
                    ? Border.all(
                        color: enabled ? widget.color : AppColor.track,
                        width: 1.8,
                      )
                    : null,
                boxShadow: widget.outlined || !enabled
                    ? null
                    : [
                        BoxShadow(
                          color: widget.color.withValues(
                            alpha: _down ? 0.16 : 0.30,
                          ),
                          blurRadius: _down ? 8 : 16,
                          offset: Offset(0, _down ? 2 : 6),
                        ),
                      ],
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 20, color: fg),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (widget.textStyle ?? AppText.button).copyWith(
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
