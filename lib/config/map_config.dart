/// Google Maps 設定。
///
/// 金鑰放在專案根目錄的 `.env`（已被 .gitignore 排除），由 `tool/gen_map_key.sh`
/// 產生成同資料夾的 `map_key.dart`（同樣不進版控）。所以平常直接跑就好，
/// 不需要任何額外參數，三個平台都一樣：
///
/// ```bash
/// flutter run            # iOS / Android
/// flutter run -d chrome  # Web
/// ```
///
/// 換過 `.env` 的金鑰之後，再跑一次 `./tool/gen_map_key.sh` 即可。
/// CI 之類不方便放檔案的環境，仍可用 `--dart-define-from-file=.env` 覆蓋。
///
/// 沒有金鑰時 [useGoogleMaps] 會是 false，地圖自動退回 OpenStreetMap 底圖，
/// 所以不會編不過或跑不起來。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'map_key.dart';
import 'maps_loader.dart';

const _definedKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

/// `--dart-define` 優先，其次才是本機產生的 [localGoogleMapsApiKey]。
String get googleMapsApiKey =>
    _definedKey.isNotEmpty ? _definedKey : localGoogleMapsApiKey;

/// iOS 的 Maps SDK 一定要先呼叫原生的 `GMSServices.provideAPIKey()`，否則第一次
/// 建立地圖就會丟 `GMSServicesException` 閃退。金鑰只存在 Dart 這邊，所以
/// [initGoogleMaps] 會在 `runApp()` 之前透過 [_iosChannel] 把它交給原生端，
/// 成功之後這個旗標才會打開。
bool _iosMapsReady = false;

/// iOS 才需要原生初始化；Web 載 JS SDK，Android 直接讀 AndroidManifest。
bool get _iosNeedsNativeKey =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

const _iosChannel = MethodChannel('irent_pulse/maps');

/// 有金鑰、而且該平台的初始化也完成了，才走 Google Maps。
bool get useGoogleMaps =>
    googleMapsApiKey.isNotEmpty && (!_iosNeedsNativeKey || _iosMapsReady);

/// 啟動時呼叫一次，且一定要在第一張地圖建立之前完成（`main()` 會 await）。
///
/// * Web ─ 動態插入 Maps JavaScript API 的 `<script>`。
/// * iOS ─ 把金鑰交給原生的 `GMSServices`。
/// * Android ─ 不用做事，Gradle 已經把金鑰塞進 AndroidManifest。
///
/// 任何一步失敗都只是讓 [useGoogleMaps] 維持 false 退回 OpenStreetMap 底圖，
/// 不會讓 App 掛掉。
Future<void> initGoogleMaps() async {
  if (googleMapsApiKey.isEmpty) return;

  if (kIsWeb) {
    await loadGoogleMapsJs(googleMapsApiKey);
    return;
  }
  if (!_iosNeedsNativeKey) return;

  try {
    _iosMapsReady =
        await _iosChannel.invokeMethod<bool>(
          'provideApiKey',
          googleMapsApiKey,
        ) ??
        false;
  } on PlatformException catch (e) {
    _iosMapsReady = false;
    debugPrint('Google Maps iOS 初始化失敗（${e.message}），改用 OpenStreetMap 底圖。');
  } on MissingPluginException {
    // 原生端還沒接這條 channel（例如 AppDelegate 被改掉了）。
    _iosMapsReady = false;
    debugPrint('找不到 irent_pulse/maps channel，改用 OpenStreetMap 底圖。');
  }
}
