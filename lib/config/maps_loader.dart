/// 在 Web 上動態載入 Google Maps JavaScript API。
///
/// 這樣金鑰只需要存在 `.env` 一個地方，不必寫進 `web/index.html`（會進版控）。
library;

export 'maps_loader_stub.dart'
    if (dart.library.js_interop) 'maps_loader_web.dart';
