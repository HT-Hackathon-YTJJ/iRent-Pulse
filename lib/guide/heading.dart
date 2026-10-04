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
///
/// Two more things the tracker needs from the motion sensors: the heading at
/// the moment a camera frame was *exposed*, which is a few frames before the
/// box found in it arrives ([yawAt]), and whether the driver is walking or
/// just turning the phone where they stand ([walking]).
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

  /// When [yaw] was last brought up to date, on the sensor's clock.
  DateTime? updatedAt;

  /// True once the gyroscope has reported at all.
  bool available = false;

  /// True while the accelerometer shows the bounce of footsteps. Turning on
  /// the spot to frame the car does not move the driver round it; walking
  /// does. See [OrbitTracker.updateYaw].
  bool walking = false;

  /// Recent (time in µs, yaw), oldest first, for [yawAt].
  final List<(int, double)> _history = [];
  static const int _historyMicros = 1500000;

  double _accelMean = 9.81;
  double _accelVar = 0;

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
      // Desktop and the web without motion sensors: the orbit guide works
      // from the detector alone.
      debugPrint('Orbit: 沒有陀螺儀 — $error');
    }
  }

  void _onAccel(AccelerometerEvent e) {
    final len = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (len < 1) return;
    _noteBounce(len);
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
    updatedAt = now;
    _remember(now, yaw);
    _events++;
    if (_log && now.difference(_loggedAt) > const Duration(seconds: 1)) {
      debugPrint(
        'Orbit 陀螺儀: yaw=${yaw.toStringAsFixed(1)}° '
        'events/s=$_events bias=${(_bias * 180 / math.pi).toStringAsFixed(2)}°/s '
        'walking=$walking',
      );
      _loggedAt = now;
      _events = 0;
    }
    notifyListeners();
  }

  /// Footsteps are a ~2 Hz bounce of 1–3 m/s² in the size of the
  /// acceleration; a phone held still or panned is a few tenths. The spread
  /// is tracked over about half a second, with a gap between the on and off
  /// thresholds so it does not chatter.
  void _noteBounce(double magnitude) {
    const k = 0.035;
    _accelMean += (magnitude - _accelMean) * k;
    final d = magnitude - _accelMean;
    _accelVar += (d * d - _accelVar) * k;
    final spread = math.sqrt(_accelVar);
    if (walking ? spread < 0.55 : spread > 0.95) walking = !walking;
  }

  void _remember(DateTime at, double value) {
    final t = at.microsecondsSinceEpoch;
    _history.add((t, value));
    while (_history.length > 2 && t - _history.first.$1 > _historyMicros) {
      _history.removeAt(0);
    }
  }

  /// The heading at [at], interpolated from the last second and a half.
  double yawAt(DateTime at) {
    if (_history.isEmpty) return yaw;
    final t = at.microsecondsSinceEpoch;
    if (t <= _history.first.$1) return _history.first.$2;
    if (t >= _history.last.$1) return _history.last.$2;
    var lo = 0, hi = _history.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_history[mid].$1 <= t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final (t0, y0) = _history[lo];
    final (t1, y1) = _history[hi];
    return t1 == t0 ? y1 : y0 + (y1 - y0) * (t - t0) / (t1 - t0);
  }

  /// Degrees a second the phone was turning about the vertical at [at],
  /// over a tenth of a second.
  double rateAt(DateTime at) {
    const half = Duration(milliseconds: 50);
    return (yawAt(at.add(half)) - yawAt(at.subtract(half))) / 0.1;
  }

  /// Stands in for the sensors in tests and simulations.
  @visibleForTesting
  void feed(DateTime at, double value, {bool walking = false}) {
    available = true;
    yaw = value;
    updatedAt = at;
    this.walking = walking;
    _remember(at, value);
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
