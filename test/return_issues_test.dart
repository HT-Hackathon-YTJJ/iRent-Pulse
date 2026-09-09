import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irent_pulse/data/return_inspection.dart';
import 'package:irent_pulse/screens/return_issues_screen.dart';

/// The 需處理 page is the one place a driver is asked to go back and do
/// something, so what it can and cannot lose is worth pinning down: it lists
/// **every** problem, and its 重拍 button re-opens **every** flagged slot in one
/// pass. Dropping either is how the flow silently goes back to one problem per
/// lap of the car.
void main() {
  const glare = ReturnFinding(
    title: '右後不通過',
    reason: '照片有不明亮點（局部反光），影響判讀。',
    kind: FindingKind.unreadable,
    spot: CaptureSpot.rearRight,
  );
  const trash = ReturnFinding(
    title: '後座有垃圾',
    reason: '腳踏墊處有飲料杯與紙袋。',
    kind: FindingKind.trash,
    spot: CaptureSpot.interiorRear,
  );

  Future<Set<CaptureSpot>?> open(
    WidgetTester tester,
    List<ReturnFinding> findings, {
    VoidCallback? onContinue,
  }) async {
    Set<CaptureSpot>? asked;
    // The handset the demo runs on, not the 800x600 default: three cards and a
    // footer is the case where this page has to scroll rather than overflow.
    tester.view.physicalSize = const Size(1080, 2410);
    tester.view.devicePixelRatio = 3.125;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ReturnIssuesScreen(
          findings: findings,
          onRetake: (spots) => asked = spots,
          onContinue: onContinue ?? () {},
        ),
      ),
    );
    await tester.pump();
    return asked;
  }

  testWidgets('lists every problem, not the worst one', (tester) async {
    await open(tester, const [trash, glare]);

    expect(find.text('後座有垃圾'), findsOneWidget);
    expect(find.text('右後不通過'), findsOneWidget);
    // Counted rather than named, because no single headline is true of both.
    expect(find.text('有 2 項需要處理'), findsOneWidget);
  });

  testWidgets('one 重拍 re-opens every flagged slot', (tester) async {
    Set<CaptureSpot>? asked;
    await tester.pumpWidget(
      MaterialApp(
        home: ReturnIssuesScreen(
          findings: const [trash, glare],
          onRetake: (spots) => asked = spots,
          onContinue: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('重拍這 2 張照片'));
    await tester.pump();

    expect(asked, {CaptureSpot.interiorRear, CaptureSpot.rearRight});
  });

  testWidgets('a lone rubbish finding keeps the board copy', (tester) async {
    await open(tester, const [trash]);

    // Named, not counted — 「車內偵測到垃圾」 says what happened before the
    // driver has read a word of the card.
    expect(find.text('後座有垃圾'), findsWidgets);
    expect(find.text('我已清理，重拍車內照'), findsOneWidget);
  });

  testWidgets('仍要還車 never stops being an answer', (tester) async {
    var continued = 0;
    await open(tester, const [trash, glare], onContinue: () => continued++);

    await tester.tap(find.text('仍要還車'));
    await tester.pump();
    expect(continued, 1);
  });
}
