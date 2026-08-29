#!/usr/bin/env python3
"""Derive the app-icon source images from the brand wordmark artwork.

Produces three files in assets/icon/, which `flutter_launcher_icons` then fans
out into every Android mipmap and iOS appiconset size:

  icon.png             1024, opaque   - iOS / Android legacy launcher icon
  icon_foreground.png  1024, alpha    - Android adaptive icon foreground layer
  icon_monochrome.png  1024, alpha    - Android 13+ themed ("Material You") icon

Usage:  python3 tool/gen_app_icon.py <wordmark.png>
        dart run flutter_launcher_icons
"""

import math
import sys
from pathlib import Path

from PIL import Image

OUT = Path("assets/icon")
S = 1024

# The artwork is flat white ink on flat red, so the green channel alone keys the
# ink out: background sits at g~2, ink at g=255.
KEY_LO, KEY_HI = 16, 250

# Framing of the opaque icon: how much of the square's width the wordmark spans.
# iOS masks with a squircle, so this leaves the corners clear.
COVERAGE = 0.70

# Android adaptive icons draw a 108dp canvas and guarantee only the centre 72dp
# survives the launcher mask; Google's keep-clear zone is the centre 66dp circle.
CANVAS_DP, SAFE_DP = 108, 66

# flutter_launcher_icons wraps the foreground in <inset android:inset="16%">, so
# the bitmap is rendered into the middle 68% of the canvas. Pre-scale by the
# inverse, otherwise the wordmark lands ~26% smaller than the safe zone allows.
FLI_INSET = 0.16


def main(src_path: str) -> None:
    src = Image.open(src_path).convert("RGB")

    soft = src.split()[1].point(
        lambda v: 0 if v <= KEY_LO
        else (255 if v >= KEY_HI else round((v - KEY_LO) * 255 / (KEY_HI - KEY_LO)))
    )

    # The soft key also catches ~1600 stray compression specks across the
    # background, so bound the wordmark with a hard threshold and clear the rest.
    bbox = soft.point(lambda v: 255 if v > 128 else 0).getbbox()
    clean = Image.new("L", src.size, 0)
    clean.paste(soft.crop(bbox), bbox[:2])
    white = Image.new("L", src.size, 255)
    mark = Image.merge("RGBA", (white, white, white, clean)).crop(bbox)
    mw, mh = mark.size
    print(f"wordmark {mw}x{mh} at {bbox}")

    OUT.mkdir(parents=True, exist_ok=True)

    # --- opaque icon --------------------------------------------------------
    # Framed as a square crop of the artwork, but repainted on the flat brand
    # red: the source's background carries ~8700 shades of compression noise,
    # which would both bloat the PNG and drift away from the flat colour the
    # Android adaptive background uses.
    side = mw / COVERAGE
    cx, cy = (bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2
    crop = tuple(round(v) for v in (cx - side / 2, cy - side / 2,
                                    cx + side / 2, cy + side / 2))
    if not (crop[0] >= 0 and crop[1] >= 0
            and crop[2] <= src.width and crop[3] <= src.height):
        sys.exit(f"crop {crop} falls outside the {src.width}x{src.height} artwork")

    bg = max(src.crop(crop).getcolors(maxcolors=1 << 24))[1]
    k = S / (crop[2] - crop[0])
    scaled = mark.resize((round(mw * k), round(mh * k)), Image.LANCZOS)
    icon = Image.new("RGB", (S, S), bg)
    icon.paste(scaled.convert("RGB"),
               (round((bbox[0] - crop[0]) * k), round((bbox[1] - crop[1]) * k)),
               scaled)
    icon.save(OUT / "icon.png", optimize=True)
    print(f"icon.png            crop {crop} side {crop[2] - crop[0]}, "
          f"background #{bg[0]:02X}{bg[1]:02X}{bg[2]:02X}")

    # --- adaptive foreground ------------------------------------------------
    # Scale by the wordmark's real ink radius, not its bounding box: "Pulse" is
    # narrower than "iRent", so the box corners are empty and would waste room.
    px = mark.load()
    mcx, mcy = (mw - 1) / 2, (mh - 1) / 2
    ink_r = math.sqrt(max((x - mcx) ** 2 + (y - mcy) ** 2
                          for y in range(mh) for x in range(mw) if px[x, y][3] > 32))

    target_r = (SAFE_DP / CANVAS_DP / 2 * S) / (1 - 2 * FLI_INSET)
    fw, fh = round(mw * target_r / ink_r), round(mh * target_r / ink_r)
    if math.hypot(fw, fh) / 2 > S / 2 and target_r > S / 2:
        sys.exit("foreground ink would overflow the canvas")
    resized = mark.resize((fw, fh), Image.LANCZOS)
    off = ((S - fw) // 2, (S - fh) // 2)
    print(f"foreground          {fw}x{fh}, renders at "
          f"{2 * target_r * (1 - 2 * FLI_INSET) / S * CANVAS_DP:.1f}dp "
          f"of the {SAFE_DP}dp safe circle")

    fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    fg.paste(resized, off)
    fg.save(OUT / "icon_foreground.png", optimize=True)

    # --- monochrome: same silhouette, solid ink, tinted by the system --------
    mono = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mono.paste((0, 0, 0, 255), off + (off[0] + fw, off[1] + fh), resized.split()[3])
    mono.save(OUT / "icon_monochrome.png", optimize=True)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
