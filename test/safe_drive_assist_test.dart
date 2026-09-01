import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irent_pulse/data/vehicle.dart';
import 'package:irent_pulse/screens/safe_drive_assist_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final vehicle = corollaCross;

  group('SafeDriveAssistScreen', () {
    testWidgets('diagram height adapts to different section aspect ratios',
        (tester) async {
      // Set a typical mobile screen size (390 x 844).
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: SafeDriveAssistScreen(
            vehicle: vehicle,
            initialSectionId: 'dashboard',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the diagram container for dashboard
      final dashboardFinder = find.byType(AnimatedContainer);
      expect(dashboardFinder, findsWidgets);

      // Find the AnimatedContainer wrapping the diagram (has height around 187 + 14 = 201)
      final containers = tester.widgetList<AnimatedContainer>(dashboardFinder);
      final diagramContainerDashboard = containers.firstWhere(
        (c) {
          final h = c.constraints?.maxHeight ?? 0;
          return h > 150 && h < 320;
        },
      );
      final dashboardHeight =
          diagramContainerDashboard.constraints!.maxHeight;

      // Dashboard should be ~201 (187 + 14), clearly less than 220
      expect(dashboardHeight, lessThan(220));
      expect(dashboardHeight, greaterThan(180));

      // Switch to shifter ('排檔桿')
      final shifterTab = find.text('排檔桿');
      expect(shifterTab, findsOneWidget);
      await tester.tap(shifterTab);
      await tester.pumpAndSettle();

      final containersAfterShifter =
          tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer));
      final diagramContainerShifter = containersAfterShifter.firstWhere(
        (c) {
          final h = c.constraints?.maxHeight ?? 0;
          return h > 150 && h < 320;
        },
      );
      final shifterHeight = diagramContainerShifter.constraints!.maxHeight;

      // Shifter diagram should be significantly taller than dashboard diagram (~281 vs ~201)
      expect(shifterHeight, greaterThan(dashboardHeight + 40));
    });

    testWidgets('clicking mark number scrolls description list to corresponding item',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: SafeDriveAssistScreen(
            vehicle: vehicle,
            initialSectionId: 'dashboard',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Item 10 text widget before scrolling
      final item10Text = find.text('引擎冷卻液溫度表');
      expect(item10Text, findsOneWidget);
      final boxBefore = tester.renderObject<RenderBox>(item10Text);
      final posBefore = boxBefore.localToGlobal(Offset.zero);
      // Item 10 is originally offscreen below the viewport
      expect(posBefore.dy, greaterThan(844));

      // Tap marker 10 on the diagram
      final mark10 = find.descendant(
        of: find.byType(AspectRatio),
        matching: find.text('10'),
      );
      expect(mark10, findsOneWidget);
      await tester.tap(mark10);

      // Advance frames to complete the 320ms animation
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final boxAfter = tester.renderObject<RenderBox>(item10Text);
      final posAfter = boxAfter.localToGlobal(Offset.zero);

      // Item 10 has scrolled into the visible screen area
      expect(posAfter.dy, lessThan(800));
      expect(posAfter.dy, greaterThan(250));
    });
  });
}
