import 'package:permission_handler/permission_handler.dart';

/// What the 還車拍照 flow is allowed to do on this device.
///
/// Camera is the only hard requirement — without it there is no L0 and no
/// photo. Location is asked for alongside it because the return has to be
/// pinned to a spot (路邊還車 needs to know where the car was left), but a
/// refusal there never blocks the return: nothing about 還車 should be
/// gate-kept by a permission the driver can reasonably decline.
///
/// The torch needs no runtime permission on either platform; it is driven
/// through the already-granted camera session.
class CapturePermissions {
  const CapturePermissions({
    required this.camera,
    required this.location,
    required this.cameraPermanentlyDenied,
  });

  final bool camera;
  final bool location;

  /// The user ticked "don't ask again" — only Settings can undo this, so the
  /// UI has to offer that door rather than asking a second time.
  final bool cameraPermanentlyDenied;

  bool get canCapture => camera;

  static Future<CapturePermissions> request() async {
    final results = await [Permission.camera, Permission.locationWhenInUse]
        .request();
    final cameraStatus = results[Permission.camera] ?? PermissionStatus.denied;
    final locationStatus =
        results[Permission.locationWhenInUse] ?? PermissionStatus.denied;
    return CapturePermissions(
      camera: cameraStatus.isGranted || cameraStatus.isLimited,
      location: locationStatus.isGranted || locationStatus.isLimited,
      cameraPermanentlyDenied: cameraStatus.isPermanentlyDenied,
    );
  }

  static Future<void> openSettings() => openAppSettings();
}
