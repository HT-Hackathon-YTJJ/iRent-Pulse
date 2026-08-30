#!/usr/bin/env python3
"""Build the 還車拍照 slot artwork from the `slot_paint_*.png` source icons.

The source icons live in the design repo (Tinghedy/irent-car-scan) at 72x72 —
exactly the size of one strip tile, and far too small to stretch across the
viewfinder. Two different things come out of each one:

* ``assets/images/return/slots/<key>.png``
      the strip indicator, copied through untouched at its native 72x72.

* ``assets/images/return/guide/<key>.png``
      the alignment mask. Only the alpha channel matters: it is cropped to the
      silhouette, blown up, and blurred so the edge arrives on screen as a soft
      gradient rather than the 72px staircase you get from scaling the source
      directly. The RGB is flat white so the app can tint the whole thing with
      one `BlendMode.srcIn` per aim state.

* ``assets/images/return/guide/<key>_edge.png``
      the same silhouette as an outline. A flat translucent wash disappears
      against a bright wall, which is exactly the background the 未對準 state has
      to survive; the outline is the part the eye actually locks onto, and it is
      what "對齊灰色輪廓線" is telling the driver to look for. Registered pixel
      for pixel with the fill, so the two stack without any layout of their own.

Usage:
    python3 tool/gen_slot_assets.py              # fetch the sources over HTTPS
    python3 tool/gen_slot_assets.py --src DIR    # use a local checkout instead

Needs Pillow. `api/.venv` already has it:
    api/.venv/bin/python tool/gen_slot_assets.py
"""

from __future__ import annotations

import argparse
import io
import pathlib
import urllib.request

from PIL import Image, ImageChops, ImageFilter

SOURCE_URL = (
    "https://raw.githubusercontent.com/Tinghedy/irent-car-scan/main/public/images"
)

# Strip order, which is also the order the driver shoots them in.
SLOTS = [
    "fuel_card",
    "indoor_front",
    "indoor_back",
    "right_front",
    "left_front",
    "right_back",
    "left_back",
]

ROOT = pathlib.Path(__file__).resolve().parent.parent
SLOT_DIR = ROOT / "assets/images/return/slots"
GUIDE_DIR = ROOT / "assets/images/return/guide"

# How wide the blown-up mask is before it is written out. The silhouette is
# ~55px across in the source, so this is a ~19x enlargement — the blur below is
# what makes that survivable.
GUIDE_WIDTH = 1024

# Blur radius, in *source* pixels. Half a source pixel is enough to melt the
# staircase without eating the shape.
BLUR_SOURCE_PX = 0.55

# Anything fainter than this in the source alpha is the PNG's own anti-aliasing
# fringe, not part of the silhouette.
ALPHA_FLOOR = 8

# Outline thickness at GUIDE_WIDTH, in pixels. The guide is drawn ~340pt wide,
# so this lands at a bit over 2pt on screen. Must be odd — it is the kernel
# the dilate/erode pair runs at.
EDGE_KERNEL = 7


def load(name: str, src: pathlib.Path | None) -> Image.Image:
    if src is not None:
        return Image.open(src / f"slot_paint_{name}.png").convert("RGBA")
    url = f"{SOURCE_URL}/slot_paint_{name}.png"
    with urllib.request.urlopen(url) as response:  # noqa: S310 - fixed host
        return Image.open(io.BytesIO(response.read())).convert("RGBA")


def white(alpha: Image.Image) -> Image.Image:
    """Wrap an alpha channel as a flat-white RGBA image, ready to be tinted."""
    out = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def outline(alpha: Image.Image) -> Image.Image:
    """The band where the silhouette's edge is: dilate minus erode, softened."""
    grown = alpha.filter(ImageFilter.MaxFilter(EDGE_KERNEL))
    shrunk = alpha.filter(ImageFilter.MinFilter(EDGE_KERNEL))
    band = ImageChops.difference(grown, shrunk)
    band = band.filter(ImageFilter.GaussianBlur(EDGE_KERNEL / 4))
    # The blur costs the band its peak; this puts the middle of the stroke back
    # to solid and leaves the falloff on either side.
    return band.point(lambda v: min(255, round(v * 1.7)))


def guide_mask(icon: Image.Image) -> tuple[Image.Image, float]:
    """Crop, enlarge and soften the silhouette. Returns the mask and its aspect."""
    alpha = icon.getchannel("A")
    box = alpha.point(lambda v: 255 if v > ALPHA_FLOOR else 0).getbbox()
    if box is None:
        raise ValueError("the source icon is fully transparent")
    cropped = alpha.crop(box)

    scale = GUIDE_WIDTH / cropped.width
    height = max(1, round(cropped.height * scale))
    # BICUBIC rather than LANCZOS: the ringing LANCZOS leaves on a hard alpha
    # edge shows up as a halo once the mask is tinted.
    big = cropped.resize((GUIDE_WIDTH, height), Image.BICUBIC)
    big = big.filter(ImageFilter.GaussianBlur(BLUR_SOURCE_PX * scale))

    # The blur pulls the edge in and washes the centre out; this puts the
    # silhouette back at full opacity and re-steepens the falloff, leaving a
    # soft-but-defined edge a few pixels wide.
    big = big.point(lambda v: min(255, max(0, round((v - 60) * 255 / 135))))

    return big, cropped.width / cropped.height


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--src",
        type=pathlib.Path,
        help="directory holding slot_paint_*.png instead of fetching them",
    )
    args = parser.parse_args()

    SLOT_DIR.mkdir(parents=True, exist_ok=True)
    GUIDE_DIR.mkdir(parents=True, exist_ok=True)

    print("slot            strip      guide          aspect")
    for name in SLOTS:
        icon = load(name, args.src)
        icon.save(SLOT_DIR / f"{name}.png")

        alpha, aspect = guide_mask(icon)
        white(alpha).save(GUIDE_DIR / f"{name}.png")
        white(outline(alpha)).save(GUIDE_DIR / f"{name}_edge.png")
        print(
            f"{name:<15} {icon.width}x{icon.height}      "
            f"{alpha.width}x{alpha.height}      {aspect:.4f}"
        )

    print()
    print("Paste the aspect column into CaptureSpot.guideAspect.")


if __name__ == "__main__":
    main()
