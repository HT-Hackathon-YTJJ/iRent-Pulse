import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;

/// Where the phone actually is.
///
/// The map used to draw its blue dot on the same coordinate it opened the
/// camera at, which is a fine stand-in right up until someone runs the demo
/// somewhere that is not Taichung — at which point the dot is a lie and the
/// stations around it are a lie about a lie. So the position is asked for once
/// when the map opens, and everything that means "near me" (the station
/// scatter, 立即預約, the 定位 button) reads from here.
///
/// Nothing in the app is gated on the answer. A refusal, a device with location
/// switched off, a web build, a simulator that never gets a fix — all of them
/// return null and leave the map on its scripted opening position, because a
/// rental app that will not draw a map until it knows where you are is worse
/// than one that draws the wrong city.
abstract final class UserLocation {
  /// The last fix, kept so a second screen does not have to wait for the
  /// platform to answer again.
  static LatLng? _last;

  static LatLng? get last => _last;

  /// True once the OS has refused. The 定位 button reads it so it can stop
  /// re-prompting into a dialog the system will no longer show.
  static bool _denied = false;

  static bool get denied => _denied;

  /// Asks for permission if it has not been asked for yet, then reads one fix.
  ///
  /// This is the call that raises the first-launch location prompt. It is made
  /// from the map rather than from `main()` on purpose: the reason for the
  /// permission is the map that is already on screen behind the dialog.
  ///
  /// Returns null when there is no answer to give. [last] is preferred over
  /// null on a failure, so a dropped fix never blanks a dot that was already
  /// on screen.
  static Future<LatLng?> locate({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return _last;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _denied = true;
        return _last;
      }
      _denied = false;

      // The cached fix first: it comes back in a millisecond and is almost
      // always good enough to place a pin field, so the map can settle while
      // the real reading is still being taken.
      //
      // In its own try, because geolocator_web throws UnsupportedError from
      // this call unconditionally — the browser exposes no cached-position API.
      // Sharing the outer catch would let that throw swallow the real reading
      // below, which is how the web build ended up never getting a fix at all.
      try {
        final cached = await Geolocator.getLastKnownPosition();
        if (cached != null) _last = LatLng(cached.latitude, cached.longitude);
      } catch (_) {
        // No cache to prime the map with; the reading below is the only answer.
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
      return _last = LatLng(position.latitude, position.longitude);
    } catch (error) {
      // Includes the timeout, a missing plugin on desktop, and the web build's
      // permission API. None of them are worth a dialog.
      debugPrint('UserLocation: 取不到定位（$error）');
      return _last;
    }
  }
}
