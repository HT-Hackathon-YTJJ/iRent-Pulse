#!/usr/bin/env bash
# 下載 L0 端上車體偵測用的 COCO SSD MobileNet v1（量化版，約 4 MB）。
# 權重被 .gitignore 的 *.tflite 排除，所以 clone 之後要跑一次這支腳本。
# 沒有模型時 App 不會壞：L0 會退回純運算的清晰度／曝光檢查，
# 只是少了「車體存在／畫面佔比／匡線對齊」三項。
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$root/assets/models"
url="https://storage.googleapis.com/download.tensorflow.org/models/tflite/coco_ssd_mobilenet_v1_1.0_quant_2018_06_29.zip"

if [[ -f "$dest/detect.tflite" ]]; then
  echo "已存在 assets/models/detect.tflite（$(du -h "$dest/detect.tflite" | cut -f1)），略過下載"
  exit 0
fi

mkdir -p "$dest"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "下載 $url"
curl -fsSL -o "$tmp/coco.zip" "$url"
unzip -oq "$tmp/coco.zip" -d "$tmp"
cp "$tmp/detect.tflite" "$dest/detect.tflite"
# labelmap 很小且會進版控，只有不存在時才補寫。
[[ -f "$dest/labelmap.txt" ]] || cp "$tmp/labelmap.txt" "$dest/labelmap.txt"

echo "已寫入 assets/models/detect.tflite（$(du -h "$dest/detect.tflite" | cut -f1)）"
