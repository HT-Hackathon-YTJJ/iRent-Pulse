import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// 把 Maps JavaScript API 的 `<script>` 插進 `<head>`，並等它載完。
///
/// 一定要在第一個 GoogleMap widget 建立之前完成，所以 main() 會 await 它。
Future<void> loadGoogleMapsJs(String apiKey) async {
  if (apiKey.isEmpty) return;

  final done = Completer<void>();
  final script = web.HTMLScriptElement()
    ..src = 'https://maps.googleapis.com/maps/api/js?key=$apiKey'
    ..async = true
    ..defer = false;

  script.onload = ((web.Event _) {
    if (!done.isCompleted) done.complete();
  }).toJS;
  script.onerror = ((web.Event _) {
    // 金鑰錯了或被擋掉時不要卡住啟動，讓地圖自己顯示錯誤即可。
    if (!done.isCompleted) done.complete();
  }).toJS;

  web.document.head!.appendChild(script);
  return done.future;
}
