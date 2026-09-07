import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// 車牌辨識 on mobile — ML Kit's on-device Latin recogniser.
///
/// The reasoning for ML Kit over a dedicated ALPR network is in
/// [plate_reader.dart]. What this file owns is the byte layout, and the reason
/// it takes **already-sampled luma** rather than a [FramePixels] is worth
/// stating: a `CameraImage`'s planes are recycled the moment the stream
/// callback returns, so anything read out of them has to be read *synchronously*
/// on that callback. Recognition is a method-channel round trip and cannot be.
/// The caller therefore samples the crop while the frame is still alive and
/// hands the copy over; see [CaptureSession._onFrame].
class PlateReader {
  PlateReader._(this._recogniser);

  final TextRecognizer _recogniser;

  bool _busy = false;
  bool _disposed = false;

  /// Long edge the caller should sample the crop at.
  ///
  /// A plate is roughly a twelfth of a car's height, so 720px across the car
  /// puts about 40px on the plate's characters — comfortably inside what the
  /// recogniser resolves, and about a megabyte over the method channel. Wider
  /// buys accuracy that the 1.5 Hz cadence and the three-frame agreement in
  /// [PlateWatcher] already buy more cheaply.
  static const int maxEdge = 720;

  /// True while a recognition is in flight. The caller checks this before doing
  /// the sampling work, because dropping the frame is free and sampling it is
  /// not.
  bool get busy => _busy || _disposed;

  static Future<PlateReader?> load() async {
    try {
      return PlateReader._(TextRecognizer(script: TextRecognitionScript.latin));
    } catch (error) {
      // A desktop build has dart:io and therefore compiles this file, but no
      // ML Kit plugin behind the channel. Same contract as CarDetector.load:
      // null means the check stays silent rather than the viewfinder breaking.
      debugPrint('L0: 車牌辨識載入失敗，略過車牌比對 — $error');
      return null;
    }
  }

  /// Read whatever text is in a [width] × [height] buffer of 8-bit luma.
  ///
  /// Returns null when the reader is busy, disposed, or the call failed — none
  /// of which is evidence about the plate, and [PlateWatcher.observe] treats
  /// them all as "say nothing".
  Future<String?> read(Uint8List luma, int width, int height) async {
    if (_disposed || _busy) return null;
    if (luma.length < width * height) return null;
    _busy = true;
    try {
      final recognised = await _recogniser.processImage(
        InputImage.fromBytes(
          bytes: Platform.isAndroid ? _nv21(luma) : _bgra(luma),
          metadata: InputImageMetadata(
            size: Size(width.toDouble(), height.toDouble()),
            // The crop was sampled upright, so there is nothing left to rotate.
            rotation: InputImageRotation.rotation0deg,
            format: Platform.isAndroid
                ? InputImageFormat.nv21
                : InputImageFormat.bgra8888,
            bytesPerRow: Platform.isAndroid ? width : width * 4,
          ),
        ),
      );
      return recognised.text;
    } catch (error) {
      debugPrint('L0: 車牌辨識失敗 — $error');
      return null;
    } finally {
      _busy = false;
    }
  }

  /// Greyscale NV21: the luma plane as-is, then neutral chroma.
  ///
  /// A plate is dark characters on a light field, so the colour being thrown
  /// away carries nothing the recogniser reads — and 0x80 in both channels is
  /// exactly "no colour", not a cast it would have to see past.
  static Uint8List _nv21(Uint8List luma) {
    final out = Uint8List(luma.length + luma.length ~/ 2);
    out.setRange(0, luma.length, luma);
    out.fillRange(luma.length, out.length, 0x80);
    return out;
  }

  /// Greyscale BGRA8888 — the only byte layout ML Kit takes on iOS.
  static Uint8List _bgra(Uint8List luma) {
    final out = Uint8List(luma.length * 4);
    for (var i = 0, j = 0; i < luma.length; i++) {
      final v = luma[i];
      out[j++] = v;
      out[j++] = v;
      out[j++] = v;
      out[j++] = 0xFF;
    }
    return out;
  }

  void dispose() {
    _disposed = true;
    _recogniser.close();
  }
}
