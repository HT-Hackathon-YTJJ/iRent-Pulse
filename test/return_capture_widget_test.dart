import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irent_pulse/data/return_inspection.dart';
import 'package:irent_pulse/screens/return_capture_screen.dart';

/// There is no camera plugin behind a widget test, so every pump here exercises
/// the fallback the screen has to survive on a desktop, on the web, and after a
/// denied permission: the viewfinder still opens, the shutter still works, and
/// the return still completes.
void main() {
  Future<void> open(
    WidgetTester tester, {
    required VoidCallback onFinished,
    VoidCallback? onNoCamera,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReturnCaptureScreen(
          spots: CaptureSpot.values,
          taken: const {},
          pending: CaptureSpot.values.toSet(),
          onFinished: onFinished,
          onExit: () {},
          onNoCamera: onNoCamera,
        ),
      ),
    );
    // start() talks to two plugins, and platform-channel replies are only
    // delivered outside the fake clock — hence runAsync before the pump.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
  }

  testWidgets('opens on the first slot and says why the camera is missing', (
    tester,
  ) async {
    await open(tester, onFinished: () {});

    // The board opens on 加油卡/停車卡, not on the body shots.
    expect(find.text('加油卡/停車卡'), findsOneWidget);
    expect(find.text('於駕駛座上方的遮陽板'), findsOneWidget);
    expect(find.text('無法開啟相機'), findsOneWidget);
    // The shutter is still there: nothing about a missing camera blocks the UI.
    expect(find.text('未對準'), findsOneWidget);
  });

  testWidgets('tells the flow to drop out of live mode', (tester) async {
    var told = 0;
    await open(tester, onFinished: () {}, onNoCamera: () => told++);
    expect(told, 1);

    // Fires once, not once per frame.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(told, 1);
  });

  testWidgets('the shutter walks the whole shot list and then finishes', (
    tester,
  ) async {
    var finished = 0;
    await open(tester, onFinished: () => finished++);

    for (final spot in CaptureSpot.values) {
      // The stand-in check settles after ~3s, the same sequence the real
      // detector produces.
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('已對準'), findsOneWidget, reason: '${spot.label} 未達已對準');

      await tester.tap(find.byType(GestureDetector).last);
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(finished, 1);
    await tester.pump(const Duration(seconds: 1));
  });

  /// The empty-slot indicator for [spot]. Once a slot holds a photo the tile
  /// shows the photo instead, so this finder disappearing *is* the "已拍攝"
  /// state.
  Finder slotIcon(CaptureSpot spot) => find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName == spot.slotIcon,
  );

  testWidgets('a slot tile can be tapped to switch to it', (tester) async {
    await open(tester, onFinished: () {});
    expect(find.text('加油卡/停車卡'), findsOneWidget);

    // 後座 is two tiles along, so it is on screen without scrolling the rail.
    await tester.tap(
      find
          .ancestor(
            of: slotIcon(CaptureSpot.interiorRear),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('車內裝(後座)'), findsOneWidget);
    expect(find.text('加油卡/停車卡'), findsNothing);
  });

  testWidgets('a shot marks its slot and advances to the next empty one', (
    tester,
  ) async {
    await open(tester, onFinished: () {});

    await tester.tap(
      find
          .ancestor(
            of: slotIcon(CaptureSpot.interiorRear),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('已對準'), findsOneWidget);
    await tester.tap(find.byType(GestureDetector).last);
    await tester.pump(const Duration(milliseconds: 400));

    // 已拍攝: the indicator is gone, replaced by the frame.
    expect(slotIcon(CaptureSpot.interiorRear), findsNothing);
    // Advanced forward from 後座 to 左前 rather than back to the untouched
    // 加油卡 at the head of the strip.
    expect(find.text('車身拍照'), findsOneWidget);

    // And it is still reachable: tapping a filled tile is how a retake starts.
    await tester.tap(
      find
          .ancestor(
            of: slotIcon(CaptureSpot.fuelCard),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('加油卡/停車卡'), findsOneWidget);
  });

  testWidgets('an off-target shutter offers 仍要送出 rather than blocking', (
    tester,
  ) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ReturnCaptureScreen(
          spots: CaptureSpot.values,
          taken: CaptureSpot.values.where((s) => s.isCorner).toSet(),
          pending: const {CaptureSpot.interiorRear},
          startMisaligned: true, // never settles, like 情境⑥
          onFinished: () => finished++,
          onExit: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    expect(find.text('已對準'), findsNothing);

    await tester.tap(find.byType(GestureDetector).last);
    await tester.pump();

    expect(find.text('仍要送出'), findsOneWidget);
    expect(find.text('重拍這張'), findsOneWidget);

    await tester.tap(find.text('仍要送出'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(finished, 1);
    await tester.pump(const Duration(seconds: 1));
  });
}
