import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irent_pulse/data/vehicle.dart';
import 'package:irent_pulse/screens/safe_drive_assist_screen.dart';
import 'package:irent_pulse/screens/trip_screen.dart';
import 'package:irent_pulse/screens/vehicle_status_screen.dart';
import 'package:irent_pulse/widgets/dark_sheet.dart';

/// Where the pull-up sheets stop, and which screens are allowed a grab handle.
///
/// Pinned because the failure mode is invisible in a widget test that does not
/// look for it and obvious on a phone: a sheet whose maximum is a hard-coded
/// fraction ends up *under* the status bar on one handset and short of it on
/// the next, and the fraction that looks right on the machine it was tuned on
/// is the one that ships.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const size = Size(390, 844);
  const statusBar = 47.0;

  Widget wrap(Widget child) => MediaQuery(
    data: const MediaQueryData(
      size: size,
      padding: EdgeInsets.only(top: statusBar, bottom: 34),
    ),
    child: MaterialApp(home: child),
  );

  Future<void> pumpAt(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(screen));
    await tester.pumpAndSettle();
  }

  double sheetTop(WidgetTester tester) => tester
      .getTopLeft(
        find
            .descendant(
              of: find.byType(DraggableScrollableSheet),
              matching: find.byType(DecoratedBox),
            )
            .first,
      )
      .dy;

  testWidgets('安心上路輔助 opens flush under the notification bar', (tester) async {
    await pumpAt(tester, SafeDriveAssistScreen(vehicle: corollaCross));
    expect(sheetTop(tester), closeTo(statusBar, 1));
  });

  testWidgets('車輛資訊 opens full and collapses straight to the shallow stop', (
    tester,
  ) async {
    await pumpAt(tester, VehicleStatusScreen(vehicle: corollaCross));
    expect(sheetTop(tester), closeTo(statusBar, 1));

    // One flick down lands on 40% — there is no stop in between to catch it.
    await tester.fling(
      find.byType(DraggableScrollableSheet),
      const Offset(0, 600),
      900,
    );
    await tester.pumpAndSettle();
    expect(sheetTop(tester), closeTo(size.height * 0.6, 2));
  });

  testWidgets('the 開鎖 screen offers no grab handle', (tester) async {
    // Its panel is pinned to the bottom of the page and cannot be dragged, so
    // a handle would be promising a gesture that does not exist.
    await pumpAt(tester, const TripScreen());
    expect(find.byType(SheetGrabber), findsNothing);
  });
}
