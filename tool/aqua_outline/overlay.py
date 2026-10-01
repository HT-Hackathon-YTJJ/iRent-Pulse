import json, sys, math
import numpy as np
from PIL import Image
import aqua
from render import Outline, draw
from fit import cam_from

def run(photo, camjson, out, color=(255, 40, 200), crop=None):
    base = Image.open(photo).convert('RGBA')
    p = json.load(open(camjson))
    cam = cam_from(p, base.size)
    m = aqua.build()
    o = Outline(np.array(m.v), np.array(m.f), getattr(m, 'features', []), part=m.part)
    img = draw(o, cam, base=base, color=color, fill_alpha=0.0, sil_w=3, in_w=2, feat_w=2, scale=0.5)
    if crop:
        img = img.crop(crop)
    img.convert('RGB').save(out)

if __name__ == '__main__':
    run(sys.argv[1], sys.argv[2], sys.argv[3], crop=tuple(map(int, sys.argv[4].split(','))) if len(sys.argv) > 4 else None)
