import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:irent_pulse/data/return_inspection.dart';

/// The shot list, the artwork behind it, and the bleed rules.
///
/// Worth pinning because all three were wrong at once and in a way no
/// screenshot review catches: the four body renders shipped under mirrored
/// names, so the 右後 slot drew the left-rear of the car. Two drivers in a row
/// reported "the last two are swapped", which was the only symptom the bug had.
void main() {
  const body = [
    CaptureSpot.frontRight,
    CaptureSpot.frontLeft,
    CaptureSpot.rearRight,
    CaptureSpot.rearLeft,
  ];

  test('the shot list is the two cards, the cabin, then the body clockwise', () {
    expect(CaptureSpot.values.map((s) => s.label).toList(), [
      '加油卡/停車卡',
      '前座',
      '後座',
      '右前',
      '左前',
      '右後',
      '左後',
    ]);
  });

  test('the rear pair is shot right before left', () {
    // 順時針繞車一圈: the rear-right corner comes before the rear-left one, so
    // the driver never has to cross back over the car they just photographed.
    expect(
      CaptureSpot.values.indexOf(CaptureSpot.rearRight),
      lessThan(CaptureSpot.values.indexOf(CaptureSpot.rearLeft)),
    );
  });

  test('each slot names its own angle in its artwork', () {
    // The mapping from these names to the design repo's mirrored file names
    // lives in tool/gen_slot_assets.py, on purpose: by the time the assets are
    // in assets/images/return/ the file called right_back really is the
    // rear-right view, and nothing in Dart has to remember otherwise.
    expect(CaptureSpot.frontRight.art, 'right_front');
    expect(CaptureSpot.frontLeft.art, 'left_front');
    expect(CaptureSpot.rearRight.art, 'right_back');
    expect(CaptureSpot.rearLeft.art, 'left_back');
  });

  test('only the two front shots bleed, and they bleed opposite ways', () {
    expect(CaptureSpot.frontRight.guideBleed, lessThan(0));
    expect(CaptureSpot.frontLeft.guideBleed, greaterThan(0));
    expect(
      CaptureSpot.frontRight.guideBleed,
      -CaptureSpot.frontLeft.guideBleed,
      reason: '兩張車頭照必須是彼此的鏡像',
    );
    for (final spot in [CaptureSpot.rearRight, CaptureSpot.rearLeft]) {
      expect(spot.guideBleed, 0, reason: '${spot.label} 要看得到車牌');
    }
  });

  test('every slot has all three guide layers on disk', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final spot in CaptureSpot.values) {
      for (final asset in [
        spot.slotIcon,
        spot.guideAsset,
        spot.guideArtAsset,
        spot.guideEdgeAsset,
      ]) {
        expect(
          await rootBundle.load(asset).then((d) => d.lengthInBytes),
          greaterThan(0),
          reason: '$asset 不在 bundle 裡（跑 tool/gen_slot_assets.py）',
        );
      }
    }
  });

  test('the guide aspect matches the artwork it is laid over', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final spot in body) {
      final bytes = await rootBundle.load(spot.guideAsset);
      // PNG header: width and height are big-endian 32-bit at offsets 16 and 20.
      final width = bytes.getUint32(16);
      final height = bytes.getUint32(20);
      expect(
        width / height,
        closeTo(spot.guideAspect, 0.01),
        reason:
            '${spot.label} 的 guideAspect 與圖檔不符 — '
            '重跑 tool/gen_slot_assets.py 並貼回 aspect 欄',
      );
    }
  });
}
