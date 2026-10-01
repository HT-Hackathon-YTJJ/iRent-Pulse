import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// How far the phone has turned about the vertical, integrated from the
/// gyroscope — the other half of [OrbitTracker].
///
/// The rate that matters is the component of the gyroscope's angular velocity
/// along *world* up, which is `ω · û` with û the gravity direction in the
/// phone's own axes. That makes it independent of how the phone is held:
/// upright in portrait, tipped towards the ground, or rolled. Both platforms
/// report ω right-handed about the device axes and sensors_plus reports the
/// accelerometer as the reaction to gravity (+9.8 along up), so a phone turned
/// anticlockwise seen from above reads positive — the same sense as the
/// orbit azimuth.
///
/// No magnetometer: a car is a tonne of steel and the compass beside it is
/// worthless. The gyroscope drifts instead, a degree or so a minute, and the
/// detector pulls that back (see [OrbitTracker.observe]).
class HeadingTracker extends ChangeNotifier {
  StreamSubscription<GyroscopeEvent>? _gyro;
  StreamSubscription<AccelerometerEvent>? _accel;

  double _ux = 0, _uy = 1, _uz = 0;
  bool _haveGravity = false;
  DateTime? _last;

  /// Gyroscope bias about the vertical, learnt while the phone is still.
  double _bias = 0;

  /// Integrated heading, degrees, anticlockwise positive, unwrapped.
  double yaw = 0;

  /// True once the gyroscope has reported at all.
  bool available = false;

  static const Duration _period = Duration(milliseconds: 16);

  /// Below this rate (rad/s) the phone is taken to be held still, and what
  /// the gyroscope reads is folded into the bias estimate.
  static const double _stillRate = 0.02;

  void start() {
    if (_gyro != null) return;
    try {
      _accel = accelerometerEventStream(samplingPeriod: _period)
          .listen(_onAccel, onError: (Object _) {}, cancelOnError: true);
      _gyro = gyroscopeEventStream(samplingPeriod: _period)
          .listen(_onGyro, onError: (Object _) {}, cancelOnError: true);
    } catch (error) {
      // Desktop and the web without motion sensors: the orbit guide falls
      // back to the detector and to dragging.
      debugPrint('Orbit: 沒有陀螺儀 — $error');
    }
  }

  void _onAccel(AccelerometerEvent e) {
    final len = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (len < 1) return;
    final x = e.x / len, y = e.y / len, z = e.z / len;
    if (!_haveGravity) {
      _ux = x;
      _uy = y;
      _uz = z;
      _haveGravity = true;
      return;
    }
    // low-pass: gravity, not the jolts of walking
    const k = 0.08;
    _ux += (x - _ux) * k;
    _uy += (y - _uy) * k;
    _uz += (z - _uz) * k;
    final n = math.sqrt(_ux * _ux + _uy * _uy + _uz * _uz);
    _ux /= n;
    _uy /= n;
    _uz /= n;
  }

  void _onGyro(GyroscopeEvent e) {
    final now = e.timestamp;
    final last = _last;
    _last = now;
    available = true;
    if (last == null || !_haveGravity) return;
    final dt = now.difference(last).inMicroseconds / 1e6;
    // A gap is integrated across, not dropped: a busy phone (or an emulator)
    // delivers events unevenly, and every dropped interval is rotation the
    // outline never makes. Only a gap long enough to mean the stream stopped
    // — the app was in the background — is skipped.
    if (dt <= 0 || dt > 0.5) return;
    final rate = e.x * _ux + e.y * _uy + e.z * _uz;
    final total = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (total < _stillRate) {
      _bias += (rate - _bias) * 0.02;
    }
    yaw += (rate - _bias) * dt * 180 / math.pi;
    _events++;
    if (_log && now.difference(_loggedAt) > const Duration(seconds: 1)) {
      debugPrint(
        'Orbit 陀螺儀: yaw=${yaw.toStringAsFixed(1)}° '
        'events/s=$_events bias=${(_bias * 180 / math.pi).toStringAsFixed(2)}°/s',
      );
      _loggedAt = now;
      _events = 0;
    }
    notifyListeners();
  }

  /// `--dart-define=ORBIT_LOG=true` prints the heading once a second.
  static const bool _log = bool.fromEnvironment('ORBIT_LOG');
  DateTime _loggedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _events = 0;

  @override
  void dispose() {
    unawaited(_gyro?.cancel());
    unawaited(_accel?.cancel());
    super.dispose();
  }
}
