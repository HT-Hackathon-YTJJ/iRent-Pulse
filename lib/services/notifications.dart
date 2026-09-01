import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The follow-up push that lands after the driver has walked away.
///
/// Figma 分支A・清潔確認通知 (831:5789) shows it on a lock screen an hour after
/// the return: 「已確認車內整潔，您的信用分數維持不變，感謝配合🙌」. That timing is
/// the point of the whole four-layer design — nothing about the car's condition
/// is said at the counter, because the layers that can say it honestly take
/// minutes, and the driver has a bus to catch. So this has to be a real OS
/// notification, not an in-app toast: by the time it fires the app is usually
/// in the background or closed.
///
/// **Permissions.** Both platforms need one, and neither is granted by
/// installing the app:
///
/// * **Android 13+** — `POST_NOTIFICATIONS` is a runtime permission. It is
///   declared in `AndroidManifest.xml` and asked for by
///   [requestPermission]. Below 13 the request is a no-op and notifications
///   post regardless.
/// * **iOS** — `UNUserNotificationCenter` authorisation, asked for by the same
///   call. `AppDelegate` also sets itself as the notification-centre delegate,
///   which is what lets a notification appear while the app is open; without
///   that iOS silently swallows foreground notifications.
///
/// Neither is asked for at launch. The flow asks when it enters 還車拍照, where
/// the prompt has an obvious reason attached — and if it is refused the return
/// still completes, because [ReturnNoticeBanner] shows the same copy in-app.
class ReturnNotifications {
  ReturnNotifications._();

  static final ReturnNotifications instance = ReturnNotifications._();

  /// Set on the [MaterialApp] so a notification tap can open a route from
  /// outside the widget tree. A tap arrives with no `BuildContext` — the app
  /// may not even have been running — so there has to be one of these
  /// somewhere, and the notification is the only thing that needs it.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static const _channelId = 'return_result';
  static const _channelName = '還車檢測結果';
  static const _channelDescription = '還車後的車況與信用分數通知';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Called when the driver taps one. The payload is the order id.
  void Function(String orderId)? onOpenOrder;

  bool _ready = false;
  bool? _granted;
  int _nextId = 1;
  final List<Timer> _pending = [];

  /// True once the OS has said yes. Null until [requestPermission] has run.
  bool? get granted => _granted;

  /// Whether this build can post OS notifications at all. The web and desktop
  /// demos fall back to the in-app banner.
  bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (_ready || !supported) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          // @mipmap/ic_launcher rather than a dedicated white silhouette: the
          // demo would rather show the real mark than ship a second asset.
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Every request is deferred to requestPermission() so the prompt
          // lands where the user can see why it is being asked.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: _handleTap,
      );

      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: _channelDescription,
              // High, so it arrives as a heads-up banner rather than a silent
              // tray entry. This is the only notification the app sends.
              importance: Importance.high,
            ),
          );
      _ready = true;
    } catch (error) {
      debugPrint('通知初始化失敗，改用 App 內橫幅 — $error');
    }
  }

  /// Ask once, at a moment where the reason is on screen.
  ///
  /// Returns false on a platform that cannot post them, which the caller reads
  /// as "show the in-app banner instead" rather than as an error.
  Future<bool> requestPermission() async {
    if (!supported) return false;
    await init();
    if (!_ready) return false;
    if (_granted != null) return _granted!;

    try {
      if (Platform.isAndroid) {
        _granted =
            await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false;
      } else {
        _granted =
            await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
    } catch (error) {
      debugPrint('通知權限要求失敗 — $error');
      _granted = false;
    }
    return _granted ?? false;
  }

  /// Post [body] after [delay], as the boards show it.
  ///
  /// A plain [Timer] rather than `zonedSchedule`: the delays here are seconds,
  /// not hours, and an exact alarm on Android 13+ is its own special permission
  /// with its own prompt. If the demo ever needs a notification to survive the
  /// app being killed, that is the moment to switch — and the moment to add
  /// `SCHEDULE_EXACT_ALARM` to the manifest.
  ///
  /// Returns false when nothing was posted, so the caller can fall back.
  Future<bool> notify({
    required String body,
    required Duration delay,
    String? orderId,
  }) async {
    if (!supported || _granted == false) return false;
    await init();
    if (!_ready) return false;
    if (_granted == null && !await requestPermission()) return false;

    final id = _nextId++;
    // No title. The board draws the app name and the body, which is exactly
    // what Android and iOS render for a title-less notification.
    void post() {
      unawaited(
        _plugin
            .show(
              id: id,
              body: body,
              notificationDetails: NotificationDetails(
                android: AndroidNotificationDetails(
                  _channelId,
                  _channelName,
                  channelDescription: _channelDescription,
                  importance: Importance.high,
                  priority: Priority.high,
                  // The copy runs to two lines on a phone; without this the
                  // tray truncates it at the first.
                  styleInformation: BigTextStyleInformation(body),
                ),
                iOS: const DarwinNotificationDetails(),
              ),
              payload: orderId,
            )
            .catchError(
              (Object error) => debugPrint('通知發送失敗 — $error'),
            ),
      );
    }

    if (delay <= Duration.zero) {
      post();
    } else {
      late Timer timer;
      timer = Timer(delay, () {
        _pending.remove(timer);
        post();
      });
      _pending.add(timer);
    }
    return true;
  }

  /// Drop anything queued but not yet posted. Called when the demo restarts a
  /// scenario, so a previous run's verdict cannot arrive over the new one.
  void cancelPending() {
    for (final timer in _pending) {
      timer.cancel();
    }
    _pending.clear();
  }

  void _handleTap(NotificationResponse response) {
    final orderId = response.payload;
    if (orderId == null || orderId.isEmpty) return;
    onOpenOrder?.call(orderId);
  }
}
