import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Shadow the 還車 result pages put under their footer — a wide, soft lift
/// (0 1 50 / 25%) rather than the tighter [AppShadow.bottomBar] used elsewhere.
const List<BoxShadow> _returnFooterShadow = [
  BoxShadow(color: Color(0x40000000), blurRadius: 50, offset: Offset(0, 1)),
];

/// White footer slab carrying the primary (and optional secondary) action.
///
/// Figma draws it 89pt tall for a single button and 24pt-padded for a stacked
/// pair; both collapse to the same thing here, with the home-indicator inset
/// acting as the floor for the bottom gap rather than adding to it.
class ReturnFooter extends StatelessWidget {
  const ReturnFooter({
    super.key,
    required this.children,
    this.verticalPadding = 22,
  });

  final List<Widget> children;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: _returnFooterShadow,
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        verticalPadding,
        16,
        math.max(verticalPadding, inset),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final child in children) ...[
            child,
            if (child != children.last) const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

/// The 236 × 45 pill used by every 還車 result page (Figma "紅色按鍵").
///
/// It is a separate control from [PillButton] because this flow's pill is
/// shorter, bolder and has a grey-ringed secondary variant that no other
/// screen uses.
class ReturnButton extends StatelessWidget {
  const ReturnButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.secondary = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// 仍要還車 — white fill, 2pt #D9D9D9 ring, grey label.
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 236),
        child: Material(
          color: secondary ? Colors.white : AppColor.brand,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
            side: secondary
                ? const BorderSide(color: AppColor.outlineRing, width: 2)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              height: 45,
              width: double.infinity,
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ReturnText.button.copyWith(
                    color: secondary
                        ? AppColor.textSecondary
                        : AppColor.textInverse,
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
