import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Sticky footer holding the primary action of a screen or sheet.
///
/// The gap under the button is `max(padding.bottom, home-indicator inset)`,
/// not `padding.bottom + inset`: the indicator strip already reads as empty
/// margin, so stacking our own padding on top of it pushed every primary
/// button visibly too high. Devices without an inset keep `padding.bottom`.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.child,
    this.background = Colors.white,
    this.shadow = true,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, minBottomGap),
  });

  /// Bottom gap used when the device has no home-indicator inset.
  static const double minBottomGap = 18;

  final Widget child;
  final Color background;
  final bool shadow;

  /// `padding.bottom` acts as the floor for the safe-area gap, not an addition
  /// to it.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: background,
        boxShadow: shadow ? AppShadow.bottomBar : null,
      ),
      padding: padding.copyWith(bottom: math.max(padding.bottom, inset)),
      child: child,
    );
  }
}
