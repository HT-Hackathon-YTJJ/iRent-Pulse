#!/usr/bin/env python3
"""Build the 還車拍照 slot artwork from the `slot_paint_*.png` source icons.

The source icons live in the design repo (Tinghedy/irent-car-scan) at 72x72 —
exactly the size of one strip tile, and far too small to stretch across the
viewfinder. Four different things come out of each one:

* ``assets/images/return/slots/<key>.png``
      the strip indicator, copied through untouched at its native 72x72.

* ``assets/images/return/guide/<key>_art.png``
      the 示意圖 itself, upscaled. This is what the driver actually lines the
      car up against — drawn semi-transparent over the live frame so the
      bumper, the A-pillar and the wheel arches can be matched feature by
      feature. A flat silhouette cannot be aligned to that precision; it only
      says "car goes roughly here".

* ``assets/images/return/guide/<key>.png``
      the silhouette, as a soft wash under the art. Flat white so the app can
      tint the whole thing with one `BlendMode.srcIn` per aim state.

* ``assets/images/return/guide/<key>_edge.png``
      the same silhouette as an outline. A flat translucent wash disappears
      against a bright wall, which is exactly the background the 未對準 state has
      to survive; the outline is the part the eye actually locks onto. All
      three guide layers are registered pixel for pixel, so they stack without
      any layout of their own.

Usage:
    python3 tool/gen_slot_assets.py              # fetch the sources over HTTPS
    python3 tool/gen_slot_assets.py --src DIR    # use a local checkout instead

Needs Pillow and numpy. `api/.venv` already has both:
    api/.venv/bin/python tool/gen_slot_assets.py

**On resolution.** Everything upstream of this script is 72x72 — the design
repo, and the image fills inside the Figma board itself (node 843:900 exports
at 55x37 native). There is no higher-resolution original to reach for, so the
quality here is won by *how* the 72px source is enlarged, not by finding a
bigger one:

* the alpha is enlarged as a smooth field and then re-thresholded with a narrow
  ramp, which is what an SDF glyph renderer does — the curve comes out clean
  instead of carrying a 28x staircase;
* the outline is derived at the output resolution, so it is a thin crisp stroke
  rather than an enlarged fat one;
* the colour art gets Lanczos plus an unsharp pass, and is then drawn at ~40%
  opacity, where softness reads as "ghost image" rather than as "bad asset".

If genuinely sharp artwork turns up later (a 4x export of the car renders, or
SVG paths), drop it in as ``slot_paint_<key>@4x.png`` beside the sources and
this script will prefer it — see ``load()``.
"""

from __future__ import annotations

import argparse
import io
import pathlib
import urllib.request

import numpy as np
from PIL import Image, ImageChops, ImageFilter

SOURCE_URL = (
    "https://raw.githubusercontent.com/Tinghedy/irent-car-scan/main/public/images"
)

# Strip order, which is also the order the driver shoots them in: the two cards
# and the cabin first, then the body clockwise from the front-right corner.
SLOTS = [
    "fuel_card",
    "indoor_front",
    "indoor_back",
    "right_front",
    "left_front",
    "right_back",
    "left_back",
]

# Slot key -> source file name.
#
# The design repo's four body renders are named for the mirror of the angle
# they actually show. `slot_paint_left_front.png` is a car whose nose points
# into the *right* of the frame, so the flank facing the camera is the car's
# right side — that is the view a driver standing at the **front-right** corner
# gets. Shipping them under their own names put every body shot on the wrong
# side of the car: the 右後 slot showed the left-rear render, which is what
# "後面兩個車屁股拍照對調" was reporting.
#
# The mapping is fixed here rather than in Dart so `CaptureSpot.art` can stay
# the honest name of the angle, and so the aspect ratios printed below already
# belong to the render each slot will really draw.
SOURCES = {
    "fuel_card": "fuel_card",
    "indoor_front": "indoor_front",
    "indoor_back": "indoor_back",
    "right_front": "left_front",
    "left_front": "right_front",
    "right_back": "left_back",
    "left_back": "right_back",
}

ROOT = pathlib.Path(__file__).resolve().parent.parent
SLOT_DIR = ROOT / "assets/images/return/slots"
GUIDE_DIR = ROOT / "assets/images/return/guide"

# How wide the blown-up guide is before it is written out. The guide is drawn
# up to ~390pt wide on a 3x display, so 2048 keeps a comfortable margin over
# the ~1170 physical pixels it can occupy.
GUIDE_WIDTH = 2048

# Anything fainter than this in the source alpha is the PNG's own anti-aliasing
# fringe, not part of the silhouette.
ALPHA_FLOOR = 8

# Width of the ramp the enlarged alpha is re-thresholded through, in *output*
# pixels. Narrow enough to read as an edge, wide enough not to alias.
EDGE_RAMP_PX = 3.0

# Outline thickness at GUIDE_WIDTH, in pixels. The guide is drawn ~340pt wide,
# so this lands at a bit over 1.5pt on screen. Must be odd — it is the kernel
# the dilate/erode pair runs at.
EDGE_KERNEL = 9

# The colour art is drawn semi-transparent, so it does not need the guide's
# full resolution; half of it keeps the bundle small and still resolves every
# feature the 72px source has.
ART_WIDTH = GUIDE_WIDTH // 2


def load(name: str, src: pathlib.Path | None) -> Image.Image:
    """The source render for one slot, preferring an `@4x` file if one exists."""
    if src is not None:
        hi = src / f"slot_paint_{name}@4x.png"
        path = hi if hi.exists() else src / f"slot_paint_{name}.png"
        return Image.open(path).convert("RGBA")
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
    band = band.filter(ImageFilter.GaussianBlur(EDGE_KERNEL / 5))
    # The blur costs the band its peak; this puts the middle of the stroke back
    # to solid and leaves the falloff on either side.
    return band.point(lambda v: min(255, round(v * 1.9)))


def crop_box(icon: Image.Image) -> tuple[int, int, int, int]:
    alpha = icon.getchannel("A")
    box = alpha.point(lambda v: 255 if v > ALPHA_FLOOR else 0).getbbox()
    if box is None:
        raise ValueError("the source icon is fully transparent")
    return box


def guide_mask(icon: Image.Image, box: tuple[int, int, int, int]) -> Image.Image:
    """Enlarge the silhouette as a field, then re-cut the edge at the new size.

    Scaling an 8-bit alpha directly reproduces the source's own staircase at
    28x. Scaling it as a smooth field and *then* deciding where the edge is —
    the trick an SDF glyph renderer uses — puts the curve back, because the
    interpolated ramp between an inside and an outside pixel carries the
    sub-pixel position of the boundary with it.
    """
    cropped = icon.getchannel("A").crop(box)
    scale = GUIDE_WIDTH / cropped.width
    height = max(1, round(cropped.height * scale))

    # BICUBIC rather than LANCZOS: the ringing LANCZOS leaves on a hard alpha
    # edge shows up as a halo once the mask is tinted.
    field = np.asarray(
        cropped.resize((GUIDE_WIDTH, height), Image.BICUBIC).filter(
            ImageFilter.GaussianBlur(EDGE_RAMP_PX)
        ),
        dtype=np.float32,
    )
    # Re-cut at the half-way point through a ramp a few output pixels wide.
    ramp = 255.0 / (2.2 * EDGE_RAMP_PX)
    cut = np.clip((field - 128.0) * ramp + 128.0, 0, 255)
    return Image.fromarray(cut.astype(np.uint8), mode="L")


def art(icon: Image.Image, box: tuple[int, int, int, int]) -> Image.Image:
    """The colour render, enlarged for use as a半透明 ghost over the frame."""
    cropped = icon.crop(box)
    scale = ART_WIDTH / cropped.width
    height = max(1, round(cropped.height * scale))
    big = cropped.resize((ART_WIDTH, height), Image.LANCZOS)
    # Lanczos on a 10x enlargement leaves the panel lines flat; the unsharp
    # pass is what keeps the bumper and the A-pillar readable through 40%
    # opacity. Radius is in output pixels, so it scales with ART_WIDTH.
    big = big.filter(
        ImageFilter.UnsharpMask(radius=scale * 0.9, percent=110, threshold=2)
    )

    # The enlargement smears the cutout's edge outwards into transparent
    # pixels; re-cutting the alpha against the guide mask keeps the ghost
    # exactly inside the silhouette the outline draws.
    mask = guide_mask(icon, box).resize(big.size, Image.BILINEAR)
    big.putalpha(ImageChops.multiply(big.getchannel("A"), mask))
    return big


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

    print("slot            source          guide           aspect")
    for key in SLOTS:
        source = SOURCES[key]
        icon = load(source, args.src)
        icon.save(SLOT_DIR / f"{key}.png")

        box = crop_box(icon)
        alpha = guide_mask(icon, box)
        white(alpha).save(GUIDE_DIR / f"{key}.png")
        white(outline(alpha)).save(GUIDE_DIR / f"{key}_edge.png")
        art(icon, box).save(GUIDE_DIR / f"{key}_art.png")

        aspect = (box[2] - box[0]) / (box[3] - box[1])
        print(
            f"{key:<15} {source:<15} "
            f"{alpha.width}x{alpha.height}      {aspect:.4f}"
        )

    print()
    print("Paste the aspect column into CaptureSpot.guideAspect.")


if __name__ == "__main__":
    main()
