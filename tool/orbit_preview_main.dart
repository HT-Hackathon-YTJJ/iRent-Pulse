import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:irent_pulse/data/return_inspection.dart';
import 'package:irent_pulse/screens/return_capture_screen.dart';
import 'package:irent_pulse/services/demo_switches.dart';

/// Opens the viewfinder straight on the four body corners, so the orbit
/// outline can be worked on without walking the app — map, trip, 還車 — to
/// get there every time.
///
///     flutter build apk --profile --split-per-abi --target-platform android-arm64 \
///       -t tool/orbit_preview_main.dart --dart-define=ORBIT_LOG=true
///     adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk
///
/// Not `flutter run`: its APK's versionCode is below the release's, so it
/// uninstalls the app — and the rental in progress with it — to get on.
///
/// Not part of the app: nothing under lib/ imports this file.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await DemoSwitches.load();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      // Same pin as lib/main.dart, or a phone with an enlarged system font
      // shows a viewfinder the real app never draws.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 1.0,
        maxScaleFactor: 1.0,
        child: child!,
      ),
      home: const _Preview(),
    ),
  );
}

class _Preview extends StatefulWidget {
  const _Preview();

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  static const _cabin = {
    CaptureSpot.fuelCard,
    CaptureSpot.interiorFront,
    CaptureSpot.interiorRear,
  };
  int _run = 0;

  @override
  Widget build(BuildContext context) {
    return ReturnCaptureScreen(
      key: ValueKey(_run),
      spots: CaptureSpot.values,
      taken: _cabin,
      pending: CaptureSpot.values.toSet().difference(_cabin),
      expectedPlate: const String.fromEnvironment(
        'PLATE',
        defaultValue: 'REN-0000',
      ),
      onFinished: () => setState(() => _run++),
      onExit: () => setState(() => _run++),
    );
  }
}
