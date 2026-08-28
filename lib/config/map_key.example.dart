// map_key.dart 的範本。
//
// `lib/config/map_key.dart` 帶著真實金鑰、已被 .gitignore 排除，所以剛 clone
// 下來的專案沒有這個檔案會編不過。第一次設定時擇一：
//
//   ./tool/gen_map_key.sh                     # 從 .env 產生（建議）
//   cp lib/config/map_key.example.dart lib/config/map_key.dart
//
// 留空也能跑，地圖會自動退回 OpenStreetMap 底圖。
const localGoogleMapsApiKey = '';
