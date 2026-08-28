#!/usr/bin/env bash
# 把 .env 裡的 GOOGLE_MAPS_API_KEY 產生成 lib/config/map_key.dart，
# 這樣 `flutter run` 不用再帶 --dart-define-from-file=.env。
# 產出的檔案已被 .gitignore 排除，金鑰不會進版控。
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/lib/config/map_key.dart"
key=""

if [[ -f "$root/.env" ]]; then
  key="$(grep -E '^[[:space:]]*GOOGLE_MAPS_API_KEY=' "$root/.env" | head -n1 | cut -d= -f2- | tr -d '"'\''[:space:]')"
fi

cat > "$out" <<DART
// 由 tool/gen_map_key.sh 從 .env 產生 — 請勿手改，也不會進版控。
// 重新產生：./tool/gen_map_key.sh
const localGoogleMapsApiKey = '$key';
DART

if [[ -n "$key" ]]; then
  echo "已寫入 lib/config/map_key.dart（金鑰長度 ${#key}）"
else
  echo "警告：.env 沒有 GOOGLE_MAPS_API_KEY，已產生空金鑰，地圖會退回 OpenStreetMap"
fi
