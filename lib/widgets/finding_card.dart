import 'dart:io' show File;

import 'package:flutter/material.dart';

import '../data/return_inspection.dart';
import '../design/tokens.dart';

/// One problem, with the photo it is about.
///
/// Full width, stacked vertically, one card per problem. The content is
/// inherently horizontal — a thumbnail and a sentence — and at 346dp a
/// two-column grid leaves about 160pt per card, which holds neither a
/// recognisable photo nor a readable sentence. Stacking also degrades
/// properly: three or four problems is a longer scroll and nothing else, where
/// a grid would need a second card design at the point the driver is having
/// the worst day.
class FindingCard extends StatelessWidget {
  const FindingCard({super.key, required this.finding});

  final ReturnFinding finding;

  static const double _thumb = 66;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColor.divider, width: 1.497),
        borderRadius: BorderRadius.circular(17.965),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 5.988,
            offset: Offset(0, 2.994),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: _thumb,
              height: _thumb,
              child: _thumbnail(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 15,
                      height: 15,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColor.aimNear,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.priority_high,
                        size: 11,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        finding.title,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: AppColor.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  finding.reason,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 19 / 13,
                    color: AppColor.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The driver's own frame. A scripted run has none, so the slot's 示意圖
  /// stands in — it says which shot the card is about, which is the thumbnail's
  /// whole job, without pretending to be a photograph that was never taken.
  Widget _thumbnail() {
    final File? photo = finding.photo;
    if (photo != null) {
      return Image.file(
        photo,
        fit: BoxFit.cover,
        // 66pt on a 3x screen; the full-size decode is what made the strip
        // stutter and there is no reason to repeat it here.
        cacheWidth: 256,
      );
    }
    final spot = finding.spot;
    if (spot == null) return const ColoredBox(color: AppColor.track);
    return ColoredBox(
      color: AppColor.track,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Image.asset(spot.slotIcon, fit: BoxFit.contain),
      ),
    );
  }
}
