import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../data/return_inspection.dart';
import 'aim.dart';
import 'car_detector.dart';
import 'frame_analysis.dart';
import 'permissions.dart';

/// One captured frame plus what L0 measured at the moment of the shutter.
class CapturedShot {
  const CapturedShot({
    required this.file,
    required this.report,
    required this.manual,
  });

  final File file;

  /// The `l0` block that travels with the photo to L1.
  final Map<String, Object?> report;

  /// True when the driver pressed the shutter rather than the checks firing it.
  final bool manual;
}

/// Why the live camera is not running.
enum CaptureFailure { none, permission, noCamera, error }

/// Owns the camera, the frame loop and the torch for the viewfinder.
///
/// The whole of L0 lives behind this one object so the screen stays
/// presentational: it renders [verdict] and calls [capture]. Nothing else in
/// the app needs to know that there is a neural net in the loop.
class CaptureSession extends ChangeNotifier {
  CaptureSession({AimThresholds thresholds = const AimThresholds()})
    : _evaluator = AimEvaluator(base: thresholds);

  final AimEvaluator _evaluator;

  CameraController? _controller;
  CarDetector? _detector;

  CameraController? get controller => _controller;
  bool get ready =>
      _controller != null && _controller!.value.isInitialized && !_disposed;

  CaptureFailure failure = CaptureFailure.none;
  String? failureDetail;

  AimVerdict verdict = const AimVerdict(state: AimState.off, hint: '對齊灰色輪廓線');

  /// Whether the torch is lit, however it got that way.
  bool get torchOn => _torchOn;
  bool _torchOn = false;

  /// Set once the driver taps the flash button; auto-torch then stands down for
  /// the rest of the shot, because overriding a deliberate choice every few
  /// frames is worse than a badly lit photo.
  bool _torchManual = false;

  bool _disposed = false;
  bool _streaming = false;
  bool _analysing = false;
  bool _requireGuide = true;
  DateTime _lastDetection = DateTime.fromMillisecondsSinceEpoch(0);
  int _darkFrames = 0;
  int _brightFrames = 0;
  Detection? _lastCar;

  /// Run the detector at about 5 Hz. The arithmetic checks run on every frame —
  /// they cost microseconds — but inference is the expensive part and a car
  /// does not move between two consecutive frames.
  static const Duration _detectInterval = Duration(milliseconds: 200);

  /// Consecutive dark/bright frames before the torch changes state. Without the
  /// hysteresis it strobes while someone walks around a car at dusk.
  static const int _torchOnAfter = 8;
  static const int _torchOffAfter = 24;
  static const double _darkLuma = 55;
  static const double _brightLuma = 95;

  /// Everything here reports failure through [failure] rather than throwing:
  /// the caller is a `initState`, so an escaping exception would leave the
  /// viewfinder black with nothing on screen explaining why. Asking for
  /// permission is inside the guard too — a plugin that is missing or wedged is
  /// exactly the case where the driver most needs to be told something.
  Future<void> start() async {
    try {
      final granted = await CapturePermissions.request();
      if (!granted.canCapture) {
        failure = CaptureFailure.permission;
        failureDetail = granted.cameraPermanentlyDenied
            ? '相機權限已被永久拒絕，請到系統設定開啟。'
            : '需要相機權限才能拍攝還車照片。';
        notifyListeners();
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        failure = CaptureFailure.noCamera;
        failureDetail = '這台裝置沒有可用的相機。';
        notifyListeners();
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        // Android hands out YUV420 and iOS BGRA8888; asking for anything else
        // forces a conversion in the plugin that L0 would only undo again.
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (_disposed) {
        await controller.dispose();
        return;
      }
      await controller.setFlashMode(FlashMode.off);
      _controller = controller;

      _detector = await CarDetector.load();
      _evaluator.restart();
      await _startStream();
      failure = CaptureFailure.none;
    } catch (error, stack) {
      failure = CaptureFailure.error;
      failureDetail = '相機啟動失敗：$error';
      debugPrint('L0: $error');
      debugPrintStack(stackTrace: stack);
    }
    notifyListeners();
  }

  /// The cabin shot has no silhouette to line up with, so the guide check is
  /// switched off for it rather than being handed a rectangle that means
  /// nothing.
  void configure({required Rect? guideRect, required bool requireGuide}) {
    _evaluator.guideRect = guideRect;
    _requireGuide = requireGuide;
  }

  /// Translate a rectangle drawn on screen into the detector's coordinate space.
  ///
  /// The preview is painted with `BoxFit.cover`, so part of the frame is off
  /// screen — comparing a screen rectangle against a box the model reported in
  /// frame coordinates without undoing that crop would silently mis-measure the
  /// alignment on every phone whose aspect ratio differs from the stream's.
  Rect? frameRectFor(Rect screenNorm, Size screenSize) {
    final preview = _controller?.value.previewSize;
    if (preview == null || screenSize.isEmpty) return null;

    final rotated = (_controller!.description.sensorOrientation % 180) != 0;
    final uprightWidth = rotated ? preview.height : preview.width;
    final uprightHeight = rotated ? preview.width : preview.height;
    if (uprightWidth <= 0 || uprightHeight <= 0) return null;

    final frameAspect = uprightWidth / uprightHeight;
    final screenAspect = screenSize.width / screenSize.height;

    // Cover crops whichever axis is longer than the screen's, so the guide
    // shrinks on that axis when expressed in frame coordinates.
    double Function(double) mapX = (x) => x;
    double Function(double) mapY = (y) => y;
    if (frameAspect > screenAspect) {
      final visible = screenAspect / frameAspect;
      mapX = (x) => 0.5 + (x - 0.5) * visible;
    } else {
      final visible = frameAspect / screenAspect;
      mapY = (y) => 0.5 + (y - 0.5) * visible;
    }

    return Rect.fromLTRB(
      mapX(screenNorm.left).clamp(0.0, 1.0),
      mapY(screenNorm.top).clamp(0.0, 1.0),
      mapX(screenNorm.right).clamp(0.0, 1.0),
      mapY(screenNorm.bottom).clamp(0.0, 1.0),
    );
  }

  /// Called between slots: the clock that widens the thresholds restarts, so
  /// the driver gets the full strict window for every shot.
  void restartAim() {
    _evaluator.restart();
    _lastCar = null;
    verdict = const AimVerdict(state: AimState.off, hint: '對齊灰色輪廓線');
    notifyListeners();
  }

  Future<void> _startStream() async {
    final controller = _controller;
    if (controller == null || _streaming) return;
    _streaming = true;
    await controller.startImageStream(_onFrame);
  }

  Future<void> _stopStream() async {
    final controller = _controller;
    if (controller == null || !_streaming) return;
    _streaming = false;
    await controller.stopImageStream();
  }

  void _onFrame(CameraImage image) {
    if (_disposed || _analysing) return;
    _analysing = true;
    try {
      final pixels = FramePixels.of(image);
      final stats = FrameStats.measure(pixels);
      _updateTorch(stats);

      final now = DateTime.now();
      final detector = _detector;
      if (detector != null &&
          now.difference(_lastDetection) >= _detectInterval) {
        _lastDetection = now;
        _lastCar = detector.detect(
          pixels,
          _controller?.description.sensorOrientation ?? 90,
          0.3, // keep low-confidence boxes; the threshold lives in the evaluator
        );
      }

      verdict = _evaluator.evaluate(
        stats: stats,
        car: _lastCar,
        detectorAvailable: detector != null,
        requireGuide: _requireGuide,
      );
      notifyListeners();
    } catch (error) {
      debugPrint('L0: 影格分析失敗 — $error');
    } finally {
      _analysing = false;
    }
  }

  /// 自動閃光燈 — 昏暗環境下自己亮起來，不必使用者去找按鈕。
  void _updateTorch(FrameStats stats) {
    if (_torchManual) return;
    final dark = stats.meanLuma < _darkLuma || stats.underExposed > 0.35;
    if (dark) {
      _brightFrames = 0;
      if (!_torchOn && ++_darkFrames >= _torchOnAfter) _setTorch(true);
    } else if (stats.meanLuma > _brightLuma) {
      _darkFrames = 0;
      if (_torchOn && ++_brightFrames >= _torchOffAfter) _setTorch(false);
    } else {
      _darkFrames = 0;
      _brightFrames = 0;
    }
  }

  void _setTorch(bool on) {
    final controller = _controller;
    if (controller == null || _torchOn == on) return;
    _torchOn = on;
    _darkFrames = 0;
    _brightFrames = 0;
    controller
        .setFlashMode(on ? FlashMode.torch : FlashMode.off)
        .catchError((Object error) {
          // Some devices refuse the torch while streaming; a photo without it
          // is still a photo.
          debugPrint('L0: 閃光燈切換失敗 — $error');
          _torchOn = !on;
        });
  }

  /// The flash button. From here on the driver owns the torch.
  Future<void> toggleTorch() async {
    _torchManual = true;
    _setTorch(!_torchOn);
    notifyListeners();
  }

  /// Take the shot. [manual] marks a driver-pressed shutter, which is what
  /// stamps `capture_mode: manual` / `bypassed` onto the report for L1.
  Future<CapturedShot?> capture({required bool manual}) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    final report = verdict.report(manual: manual);
    try {
      // takePicture cannot run while the image stream is open on Android.
      await _stopStream();
      final shot = await controller.takePicture();
      return CapturedShot(
        file: File(shot.path),
        report: report,
        manual: manual,
      );
    } catch (error) {
      debugPrint('L0: 拍攝失敗 — $error');
      return null;
    } finally {
      if (!_disposed) await _startStream();
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _detector?.dispose();
    _detector = null;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        if (_streaming) await controller.stopImageStream();
        if (_torchOn) await controller.setFlashMode(FlashMode.off);
      } catch (_) {
        // The controller is going away either way.
      }
      await controller.dispose();
    }
    super.dispose();
  }
}
