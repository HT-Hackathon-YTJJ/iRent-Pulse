import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../data/return_inspection.dart';
import 'aim.dart';
import 'car_detector.dart';
import 'frame_analysis.dart';
import 'permissions.dart';
import 'plate_reader.dart';

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
  CaptureSession({
    AimThresholds thresholds = const AimThresholds(),
    this.expectedPlate = '',
  }) : _evaluator = AimEvaluator(base: thresholds),
       _plates = PlateWatcher(expected: expectedPlate);

  /// The plate on the rental agreement. Empty switches the 車牌比對 off, which
  /// is what a scripted demo run or a widget test wants.
  final String expectedPlate;

  final AimEvaluator _evaluator;
  final PlateWatcher _plates;

  CameraController? _controller;
  CarDetector? _detector;
  PlateReader? _plateReader;

  CameraController? get controller => _controller;
  bool get ready =>
      _controller != null && _controller!.value.isInitialized && !_disposed;

  CaptureFailure failure = CaptureFailure.none;
  String? failureDetail;

  AimVerdict verdict = const AimVerdict(state: AimState.off, hint: '對齊輪廓線');

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
  DateTime _lastPlateRead = DateTime.fromMillisecondsSinceEpoch(0);
  int _darkFrames = 0;
  int _brightFrames = 0;

  double _zoom = 1;
  double _minZoom = 1;
  double _maxZoom = 1;

  /// What the driver is looking through, as a **linear** ratio against the
  /// main lens: 1.0 is the sensor's own field of view, 0.5 the ultra-wide.
  double get zoom => _zoom;
  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;

  /// Upright width ÷ height of the camera stream, or null before it opens.
  ///
  /// The viewfinder needs this to lay the preview out *whole* rather than
  /// cropped, which is the only way the guide rectangle it draws and the box
  /// the detector reports can be in the same coordinate space.
  double? get previewAspect {
    final preview = _controller?.value.previewSize;
    final description = _controller?.description;
    if (preview == null || description == null) return null;
    final rotated = (description.sensorOrientation % 180) != 0;
    final width = rotated ? preview.height : preview.width;
    final height = rotated ? preview.width : preview.height;
    if (width <= 0 || height <= 0) return null;
    return width / height;
  }

  /// Run the detector at about 5 Hz. The arithmetic checks run on every frame —
  /// they cost microseconds — but inference is the expensive part and a car
  /// does not move between two consecutive frames.
  static const Duration _detectInterval = Duration(milliseconds: 200);

  /// Read the plate about 1.5 times a second.
  ///
  /// Much slower than the detector on purpose. Recognition is a method-channel
  /// round trip with a megabyte of pixels on it, and the answer it produces is
  /// not per-frame information: a plate does not change, and [PlateWatcher]
  /// wants three agreeing readings before it says anything anyway. 650 ms gets
  /// to an answer in about two seconds — while the driver is still lining the
  /// shot up — without competing with the detector for the CPU.
  static const Duration _plateInterval = Duration(milliseconds: 650);

  /// Grow the car's box before cropping to it. The detector draws to the metal
  /// and a plate sits right at the bumper's edge, often a few pixels outside.
  static const double _plateCropPadding = 0.06;

  /// `--dart-define=L0_LOG_PLATES=true` prints every OCR result to the log.
  ///
  /// Off by default for two reasons. The plate check is the one part of L0 that
  /// **cannot** be debugged anywhere but on a handset — the recogniser is a
  /// method channel — so there has to be a way to see what it read; and a plate
  /// is identifying, so that way must not be on in a build anybody ships.
  static const bool _logPlates = bool.fromEnvironment('L0_LOG_PLATES');

  /// Consecutive dark/bright frames before the torch changes state. Without the
  /// hysteresis it strobes while someone walks around a car at dusk.
  static const int _torchOnAfter = 8;
  static const int _torchOffAfter = 24;
  static const double _darkLuma = 55;
  static const double _brightLuma = 95;

  /// Serialises camera ownership across [CaptureSession] instances.
  ///
  /// `State.dispose()` cannot await, so a screen that remounts — a retake, or
  /// the flow switching to live mode after /healthz answers — starts the new
  /// session's camera while the old one is still handing its CameraX use cases
  /// back. CameraX then refuses to bind:
  ///
  ///     No supported surface combination is found for camera device - Id : 0.
  ///     Existing surfaces: [... captureTypes=[IMAGE_ANALYSIS] ...]
  ///
  /// and the viewfinder falls back to the no-camera stand-in for the rest of
  /// the return. The photos are still taken, but they are taken by a screen
  /// that cannot see — which is the one failure L0 exists to prevent.
  ///
  /// Both [start] and [dispose] queue here, so a teardown always completes
  /// before the next open begins.
  static Future<void> _cameraQueue = Future<void>.value();

  static Future<T> _serialised<T>(Future<T> Function() action) {
    final result = _cameraQueue.then((_) => action());
    // Swallow the error *for the queue only*: one session failing to open must
    // not poison every session after it. The caller still sees it.
    _cameraQueue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

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
      // Behind any session still tearing down — see [_cameraQueue].
      await _serialised(controller.initialize);
      if (_disposed) {
        await controller.dispose();
        return;
      }
      await controller.setFlashMode(FlashMode.off);
      _controller = controller;
      await _resetZoom(controller);

      _detector = await CarDetector.load();
      // Best effort, exactly like the detector: a phone that cannot load the
      // recogniser keeps every other L0 check and simply never mentions plates.
      if (expectedPlate.isNotEmpty) _plateReader = await PlateReader.load();
      if (_logPlates) {
        debugPrint(
          'L0 車牌: reader=${_plateReader == null ? "無" : "就緒"} '
          'expected=$expectedPlate',
        );
      }
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

  /// Put the viewfinder on the main lens at its own field of view.
  ///
  /// On a multi-camera Android phone the plugin opens the back camera as one
  /// *logical* device spanning every lens, and it does not necessarily open it
  /// at 1×. On a Pixel 10 Pro the viewfinder came up somewhere around 2×, which
  /// is what put the driver several paces further back than the guide expected
  /// — an entire car park's worth of walking for a photo the main lens could
  /// have taken from where they stood. CameraX's zoom ratio is defined against
  /// the main lens, so 1.0 *is* "the best rear camera, uncropped", and asking
  /// for it explicitly is the fix.
  Future<void> _resetZoom(CameraController controller) async {
    try {
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
      await setZoom(1);
    } catch (error) {
      // A device that will not report its zoom range is left wherever it
      // opened; nothing else depends on this succeeding.
      debugPrint('L0: 無法設定鏡頭倍率 — $error');
    }
  }

  /// Switch lens magnification. Values outside the device's range are clamped,
  /// so the 0.5× chip is simply inert on a phone with no ultra-wide.
  Future<void> setZoom(double value) async {
    final controller = _controller;
    if (controller == null) return;
    final target = value.clamp(_minZoom, _maxZoom).toDouble();
    try {
      await controller.setZoomLevel(target);
      _zoom = target;
      notifyListeners();
    } catch (error) {
      debugPrint('L0: 倍率切換失敗 — $error');
    }
  }

  /// The cabin shot has no silhouette to line up with, so the guide check is
  /// switched off for it rather than being handed a rectangle that means
  /// nothing.
  ///
  /// [guideRect] is in **preview-normalised** coordinates — 0–1 across the
  /// image the driver can see. Because the preview is drawn whole rather than
  /// cropped to fill, that is the same space the detector reports its boxes in,
  /// so the shape being scored is pixel-for-pixel the shape on screen.
  void configure({
    required Rect? guideRect,
    required bool requireGuide,
    bool guideAllowsEdge = false,
  }) {
    _evaluator.guideRect = guideRect;
    _evaluator.guideAllowsEdge = guideAllowsEdge;
    _requireGuide = requireGuide;
  }

  /// Called between slots, and again after a 重拍.
  ///
  /// The streak and the smoothed box always go; [keepElapsed] decides whether
  /// the clock that widens the thresholds goes with them. A new slot is a new
  /// shot and gets the full strict window; a retake of the slot the driver is
  /// already standing at is the same shot continued, and restarting its clock
  /// would undo the widening they have been waiting on.
  void restartAim({bool keepElapsed = false}) {
    _evaluator.restart(keepElapsed: keepElapsed);
    // Only the pending-mismatch streak resets; a plate already confirmed as
    // this car stays confirmed across slots and retakes. See PlateWatcher.
    _plates.restart();
    verdict = const AimVerdict(state: AimState.off, hint: '對齊輪廓線');
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
      // Only the frames inference actually ran on carry a detection. Handing
      // the last one down on every frame is how a box that had gone stale kept
      // the badge green after the car had left the viewfinder; the evaluator
      // ages what it is given and stops trusting it after AimEvaluator.staleAfter.
      Detection? fresh;
      if (detector != null &&
          now.difference(_lastDetection) >= _detectInterval) {
        _lastDetection = now;
        fresh = detector.detect(
          pixels,
          _controller?.description.sensorOrientation ?? 90,
          0.3, // keep low-confidence boxes; the threshold lives in the evaluator
        );
      }

      _maybeReadPlate(pixels, now);

      verdict = _evaluator.evaluate(
        stats: stats,
        car: fresh,
        detectorAvailable: detector != null,
        requireGuide: _requireGuide,
        plate: _plates.state,
        plateSeen: _plates.lastSeen,
        now: now,
      );
      notifyListeners();
    } catch (error) {
      debugPrint('L0: 影格分析失敗 — $error');
    } finally {
      _analysing = false;
    }
  }

  /// Crop to the car and send it to the recogniser, at most [_plateInterval].
  ///
  /// The sampling is **synchronous and on this callback** because a
  /// `CameraImage`'s planes are recycled the moment [_onFrame] returns — the
  /// copy is what goes to the async recogniser. That is also why [PlateReader.busy]
  /// is checked before the sampling rather than inside `read`: dropping the
  /// frame costs nothing, sampling one we are about to throw away costs a
  /// megabyte of work in the frame loop.
  void _maybeReadPlate(FramePixels pixels, DateTime now) {
    final reader = _plateReader;
    // Only the four corner slots — the cabin rows and the sun visor have no
    // plate in shot, and _requireGuide is exactly "this slot is a body corner".
    if (reader == null || reader.busy || !_requireGuide) return;
    if (now.difference(_lastPlateRead) < _plateInterval) return;

    // Crop to what the detector found. Without a box there is no car in frame,
    // and OCR over the whole scene would mostly read the car park's signage.
    final box = _evaluator.boxAt(now);
    if (box == null) return;

    final grown = box.inflate(_plateCropPadding);
    final region = Rect.fromLTRB(
      grown.left.clamp(0.0, 1.0),
      grown.top.clamp(0.0, 1.0),
      grown.right.clamp(0.0, 1.0),
      grown.bottom.clamp(0.0, 1.0),
    );
    if (region.width <= 0.02 || region.height <= 0.02) return;

    final rotation = _controller?.description.sensorOrientation ?? 90;
    final upright = rotation == 90 || rotation == 270;
    final srcW = (upright ? pixels.height : pixels.width) * region.width;
    final srcH = (upright ? pixels.width : pixels.height) * region.height;
    final scale = math.min(1.0, PlateReader.maxEdge / math.max(srcW, srcH));
    // Both byte layouts subsample chroma 2×2, so an odd edge would leave the
    // last row or column without one.
    final outW = _even((srcW * scale).round());
    final outH = _even((srcH * scale).round());
    if (outW < 32 || outH < 32) return;

    _lastPlateRead = now;
    final luma = sampleRotatedLuma(pixels, rotation, region, outW, outH);
    unawaited(
      reader.read(luma, outW, outH).then((text) {
        if (_disposed) return;
        _plates.observe(text);
        if (_logPlates) {
          debugPrint(
            'L0 車牌: ${outW}x$outH '
            'ocr=${text?.replaceAll(RegExp(r"\s+"), " ").trim()} '
            '候選=${extractPlates(text ?? "")} → ${_plates.state.name}',
          );
        }
      }),
    );
  }

  static int _even(int value) => value.isEven ? value : value - 1;

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
  Future<void> dispose() {
    _disposed = true;
    _detector?.dispose();
    _detector = null;
    _plateReader?.dispose();
    _plateReader = null;
    final controller = _controller;
    final streaming = _streaming;
    final torch = _torchOn;
    _controller = null;
    _streaming = false;
    super.dispose();

    // Returned rather than awaited: the caller is a State.dispose(), which
    // cannot wait. What matters is that the next start() queues behind this.
    return _serialised(() async {
      if (controller == null) return;
      try {
        if (streaming) await controller.stopImageStream();
        if (torch) await controller.setFlashMode(FlashMode.off);
      } catch (_) {
        // The controller is going away either way.
      }
      await controller.dispose();
    });
  }
}
