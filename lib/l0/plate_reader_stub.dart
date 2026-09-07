import 'dart:typed_data';

/// The web build's plate reader: one that never loads.
///
/// `google_mlkit_text_recognition` is a method-channel plugin with no web
/// implementation, so dart2js must not see it. [PlateReader.load] returning
/// null is the same contract [CarDetector.load] uses, and every caller already
/// handles it by leaving the check silent.
class PlateReader {
  PlateReader._();

  static const int maxEdge = 720;

  static Future<PlateReader?> load() async => null;

  bool get busy => true;

  Future<String?> read(Uint8List luma, int width, int height) async => null;

  void dispose() {}
}
