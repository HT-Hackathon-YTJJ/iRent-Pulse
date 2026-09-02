import 'package:flutter/foundation.dart';

import 'detection.dart';
import 'frame_analysis.dart';

/// The web build's stand-in for the TFLite detector.
///
/// `tflite_flutter` is `dart:ffi` all the way down, so it cannot be compiled
/// for the web at all — importing it anywhere reachable from `main.dart` fails
/// the whole dart2js run. L0 already has a no-model path (`tool/fetch_l0_model.sh`
/// is a manual step, so a fresh clone runs without weights), and this reuses it:
/// [load] returns null, the session sets `detectorAvailable: false`, and the
/// evaluator falls back to the four arithmetic checks — 畫面佔比, 完整性,
/// 清晰度, 曝光 — instead of blocking the return.
class CarDetector {
  CarDetector._();

  static const String modelAsset = 'assets/models/detect.tflite';
  static const String labelAsset = 'assets/models/labelmap.txt';

  static const Set<String> vehicleLabels = {'car', 'truck', 'bus'};

  static Future<CarDetector?> load() async {
    debugPrint('L0: Web 沒有 TFLite runtime，改用純運算檢查');
    return null;
  }

  bool get available => false;

  Detection? detect(FramePixels pixels, int rotationDegrees, double minScore) =>
      null;

  void dispose() {}
}
