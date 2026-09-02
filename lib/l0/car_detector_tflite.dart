import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'detection.dart';
import 'frame_analysis.dart';

/// COCO SSD MobileNet v1 (quantised) — the 車體存在 check from spec §L0.
///
/// An off-the-shelf model with `car` in its label set is the whole point: it
/// needs no training data, and the four checks around it (畫面佔比, 完整性,
/// 清晰度, 曝光) are arithmetic. Swapping in a YOLOv8n or a fine-tuned angle
/// classifier later means replacing this class and nothing else.
///
/// The weights are **not in version control** (`.gitignore` excludes `*.tflite`).
/// Run `tool/fetch_l0_model.sh` once after cloning. If the asset is missing the
/// detector reports [available] == false and L0 falls back to the pure
/// arithmetic checks rather than blocking the return.
class CarDetector {
  CarDetector._(this._interpreter, this._labels, this._inputSize, this._maxDetections)
    : _boxes = [
        List.generate(_maxDetections, (_) => List<double>.filled(4, 0)),
      ],
      _classes = [List<double>.filled(_maxDetections, 0)],
      _scores = [List<double>.filled(_maxDetections, 0)];

  final Interpreter _interpreter;
  final List<String> _labels;
  final int _inputSize;

  /// `max_detections` baked into the model's TFLite_Detection_PostProcess op.
  /// Read from the output tensor rather than assumed, because tflite_flutter
  /// rejects an output buffer whose shape does not match exactly.
  final int _maxDetections;

  static const String modelAsset = 'assets/models/detect.tflite';
  static const String labelAsset = 'assets/models/labelmap.txt';

  /// COCO has no "rental car" class; anything a saloon, van or minibus could be
  /// mistaken for counts, because the alternative is refusing to fire the
  /// shutter for a driver holding a legitimate vehicle.
  static const Set<String> vehicleLabels = {'car', 'truck', 'bus'};

  bool _busy = false;
  bool _disposed = false;

  // Reused between frames: allocating four nested lists 5 times a second is
  // enough garbage to show up in a frame budget.
  final List<List<List<double>>> _boxes;
  final List<List<double>> _classes;
  final List<List<double>> _scores;
  final List<double> _count = List<double>.filled(1, 0);

  static Future<CarDetector?> load() async {
    try {
      final interpreter = await Interpreter.fromAsset(
        modelAsset,
        options: InterpreterOptions()..threads = 4,
      );
      final input = interpreter.getInputTensor(0).shape; // [1, size, size, 3]
      // Outputs, in the order TFLite_Detection_PostProcess emits them:
      // 0 boxes [1, N, 4] · 1 classes [1, N] · 2 scores [1, N] · 3 count [1]
      final boxes = interpreter.getOutputTensor(0).shape;
      final labels = (await rootBundle.loadString(labelAsset))
          .split('\n')
          .map((l) => l.trim())
          .toList();
      return CarDetector._(interpreter, labels, input[1], boxes[1]);
    } catch (error, stack) {
      debugPrint('L0: 車體偵測模型載入失敗，改用純運算檢查 — $error');
      debugPrintStack(stackTrace: stack);
      return null;
    }
  }

  bool get available => !_disposed;

  /// Returns the highest-scoring vehicle, or null.
  ///
  /// Frames that arrive while an inference is in flight are dropped rather than
  /// queued: a stale verdict is worse than a missed one when the user is
  /// actively moving the phone to satisfy it.
  Detection? detect(FramePixels pixels, int rotationDegrees, double minScore) {
    if (_disposed || _busy) return null;
    _busy = true;
    try {
      final input = sampleRotatedRgb(pixels, rotationDegrees, _inputSize);
      _interpreter.runForMultipleInputs(
        <Object>[input],
        <int, Object>{0: _boxes, 1: _classes, 2: _scores, 3: _count},
      );

      Detection? best;
      final found = _count[0].round().clamp(0, _maxDetections);
      for (var i = 0; i < found; i++) {
        final score = _scores[0][i];
        if (score < minScore) continue;
        final label = _labelAt(_classes[0][i]);
        if (!vehicleLabels.contains(label)) continue;
        if (best != null && score <= best.score) continue;
        final b = _boxes[0][i]; // ymin, xmin, ymax, xmax, already normalised
        best = Detection(
          box: Rect.fromLTRB(
            b[1].clamp(0.0, 1.0),
            b[0].clamp(0.0, 1.0),
            b[3].clamp(0.0, 1.0),
            b[2].clamp(0.0, 1.0),
          ),
          score: score,
          label: label,
        );
      }
      return best;
    } catch (error) {
      debugPrint('L0: 偵測失敗 — $error');
      return null;
    } finally {
      _busy = false;
    }
  }

  /// The post-process op emits an index into the 90 real classes, while the
  /// shipped labelmap keeps a `???` placeholder at line 0.
  String _labelAt(double raw) {
    final index = raw.round() + 1;
    return index >= 0 && index < _labels.length ? _labels[index] : '';
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _interpreter.close();
  }
}
