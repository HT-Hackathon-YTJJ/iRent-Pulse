"""Crop a region of a photo, upscale, and draw a labelled pixel grid so
coordinates can be read off precisely.  usage: grid.py img x0 y0 x1 y1 step out [scale]"""
import sys
from PIL import Image, ImageDraw, ImageFont
img, x0, y0, x1, y1, step, out = sys.argv[1], *map(int, sys.argv[2:7]), sys.argv[7]
scale = float(sys.argv[8]) if len(sys.argv) > 8 else 2.0
im = Image.open(img).convert('RGB').crop((x0, y0, x1, y1))
im = im.resize((int(im.size[0]*scale), int(im.size[1]*scale)), Image.LANCZOS)
d = ImageDraw.Draw(im)
try:
    f = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 14)
except Exception:
    f = None
for x in range((x0 // step + 1) * step, x1, step):
    X = (x - x0) * scale
    d.line([(X, 0), (X, im.size[1])], fill=(255, 0, 255) if x % (step*5) == 0 else (0, 200, 255), width=1)
    d.text((X + 2, 2), str(x), fill=(255, 255, 0), font=f)
for y in range((y0 // step + 1) * step, y1, step):
    Y = (y - y0) * scale
    d.line([(0, Y), (im.size[0], Y)], fill=(255, 0, 255) if y % (step*5) == 0 else (0, 200, 255), width=1)
    d.text((2, Y + 2), str(y), fill=(255, 255, 0), font=f)
im.save(out)
