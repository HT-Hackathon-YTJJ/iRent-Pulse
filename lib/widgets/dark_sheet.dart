import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// The dark grab handle used at the top of every pull-up sheet in the flow.
class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key, this.color = AppColor.textSecondary});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 51,
    height: 5,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
    ),
  );
}

/// Dark header block (Figma: "上拉視窗" #4A4A4A) with a title and subtitle.
class DarkSheetHeader extends StatelessWidget {
  const DarkSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.titleStyle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(24, 0, 16, 20),
    this.centered = false,
  });

  final String title;
  final String? subtitle;
  final TextStyle? titleStyle;
  final Widget? trailing;
  final EdgeInsets padding;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final column = Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: (titleStyle ?? AppText.titleL).copyWith(
            color: AppColor.textInverse,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: AppText.bodyS.copyWith(color: AppColor.textOnDark),
          ),
        ],
      ],
    );

    return Padding(
      padding: padding,
      child: trailing == null
          ? column
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: column),
                trailing!,
              ],
            ),
    );
  }
}

/// Rounded dark panel that the sheets sit on.
class DarkSheetSurface extends StatelessWidget {
  const DarkSheetSurface({
    super.key,
    required this.child,
    this.topPadding = 12,
  });

  final Widget child;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColor.sheetDark,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(top: topPadding, bottom: 14),
            child: const SheetGrabber(),
          ),
          child,
        ],
      ),
    );
  }
}
