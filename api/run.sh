#!/usr/bin/env bash
# 起本機 API。第一次跑會自動建 venv 並裝套件。
#   api/run.sh              → 127.0.0.1:8000（模擬器 / Web 用）
#   api/run.sh 0.0.0.0      → 綁所有介面（實機用，手機連同一個 Wi-Fi）
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d .venv ]; then
  python3 -m venv .venv
  .venv/bin/pip install --upgrade pip -q
  .venv/bin/pip install -q -r requirements.txt
fi

HOST="${1:-127.0.0.1}"
PORT="${2:-8000}"
exec .venv/bin/uvicorn app.main:app --host "$HOST" --port "$PORT" --reload
