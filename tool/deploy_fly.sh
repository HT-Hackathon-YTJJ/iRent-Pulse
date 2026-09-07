#!/usr/bin/env bash
# 把 api/ 部署到 Fly.io。
#
#   tool/deploy_fly.sh              → 只推程式碼
#   tool/deploy_fly.sh --with-key   → 順便把 .env 的 OPENROUTER_API_KEY 同步成 Fly secret
#
# 設定在 api/fly.toml。機器閒置會自動停機，第一個請求再喚醒。
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${FLY_APP:-irent-pulse-api}"

command -v flyctl >/dev/null || { echo "找不到 flyctl"; exit 1; }
flyctl auth whoami >/dev/null 2>&1 || { echo "尚未登入，先跑 flyctl auth login"; exit 1; }

if [ "${1:-}" = "--with-key" ]; then
  KEY="$(sed -n 's/^OPENROUTER_API_KEY=//p' .env | tr -d '"'"'"' \r')"
  [ -n "$KEY" ] || { echo ".env 裡沒有 OPENROUTER_API_KEY"; exit 1; }
  echo "==> 同步 OPENROUTER_API_KEY"
  # --stage 讓它跟著下面這次 deploy 一起生效，而不是各自重啟一次機器。
  flyctl secrets set "OPENROUTER_API_KEY=$KEY" -a "$APP" --stage >/dev/null
fi

echo "==> 部署 $APP"
(cd api && flyctl deploy --ha=false)

echo "==> https://$APP.fly.dev/healthz"
curl -fsS --max-time 60 "https://$APP.fly.dev/healthz" && echo
