/// 非 Web 平台不需要載入 JS SDK：Android 讀 AndroidManifest 的
/// `com.google.android.geo.API_KEY`，iOS 由 `initGoogleMaps()` 走 method channel 交給原生的 `GMSServices`。
Future<void> loadGoogleMapsJs(String apiKey) async {}
