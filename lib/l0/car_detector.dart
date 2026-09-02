/// The 車體存在 check from spec §L0, picked per platform at compile time.
///
/// Mobile gets [car_detector_tflite.dart] — COCO SSD MobileNet through
/// `tflite_flutter`. That package is `dart:ffi` only, and dart2js refuses to
/// compile anything that can reach it, so the web build gets
/// [car_detector_stub.dart] instead: a detector that never loads, which drops
/// L0 to its arithmetic-only path. Both expose the same surface, so every
/// caller keeps importing this file and nothing else changes.
library;

export 'detection.dart';
export 'car_detector_stub.dart'
    if (dart.library.ffi) 'car_detector_tflite.dart';
