#!/usr/bin/env bash
# Download the two reference photos the model was fitted against, from
# Wikimedia Commons (both by TTTNIS, CC0; not committed — see
# README.md). Only needed to re-fit the cameras, re-trace detail lines or
# redraw the overlay checks; building the model needs neither.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p refs
UA="irent-pulse/1.0 (outline model reference)"
fetch() {
  local title="$1" out="$2"
  local url
  url=$(curl -s -A "$UA" "https://commons.wikimedia.org/w/api.php?action=query&prop=imageinfo&iiprop=url&iiurlwidth=1920&format=json&titles=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$title")" |
    python3 -c 'import json,sys; p=next(iter(json.load(sys.stdin)["query"]["pages"].values())); print(p["imageinfo"][0]["thumburl"])')
  curl -s -A "$UA" -o "refs/$out" "$url"
  echo "refs/$out"
}
fetch "File:2017-2021 Toyota Aqua rear.jpg" 2017-2021_Toyota_Aqua_rear.jpg
fetch "File:2017-2021 Toyota Aqua.jpg" 2017-2021_Toyota_Aqua.jpg
