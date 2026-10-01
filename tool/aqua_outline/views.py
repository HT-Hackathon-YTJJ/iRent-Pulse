import math, sys
import numpy as np
from PIL import Image
import aqua
from render import Camera, Outline, draw

def cam_at(az_deg, dist, eye_h, size=(600, 400), fov_v=None, f=None, target=(0, 0, 0.72)):
    a = math.radians(az_deg)
    t = np.array(target, float)
    eye = t + np.array([dist * math.cos(a), dist * math.sin(a), 0])
    eye[2] = eye_h
    if f is None:
        f = size[1] / 2 / math.tan(math.radians(fov_v) / 2)
    return Camera(eye, t, f, size)

def load():
    m = aqua.build()
    V = np.array(m.v); F = np.array(m.f)
    feats = getattr(m, 'features', [])
    return Outline(V, F, feats, part=m.part)

if __name__ == '__main__':
    o = load()
    tiles = []
    # near-orthographic side / front / rear / top
    tiles.append(draw(o, cam_at(90, 60, 0.72, fov_v=4.4)))       # left side
    tiles.append(draw(o, cam_at(0, 60, 0.72, fov_v=4.4)))        # front
    tiles.append(draw(o, cam_at(180, 60, 0.72, fov_v=4.4)))      # rear
    top = Camera(np.array([0, 0, 60.0]), np.array([0, 0, 0.7]), 400 / 2 / math.tan(math.radians(2.2)) * 1.0, (600, 400), up=(1, 0, 0))
    tiles.append(draw(o, top))
    for az in (40, -40, -140, 140):
        tiles.append(draw(o, cam_at(az, 5.0, 1.45, fov_v=50)))
    W, H = 600, 400
    sheet = Image.new('RGBA', (W * 4, H * 2))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % 4) * W, (i // 4) * H))
    sheet.convert('RGB').save(sys.argv[1] if len(sys.argv) > 1 else 'views.png')


def corners(out, size=(360, 480), fov_v=62.0, dist=4.6, eye_h=1.40):
    """The four target corners as a phone held in portrait would see them."""
    o = load()
    tiles = []
    for az in (40, -40, -140, 140):
        cam = cam_at(az, dist, eye_h, size=size, fov_v=fov_v, target=(0, 0, 0.62))
        tiles.append(draw(o, cam))
    sheet = Image.new('RGBA', (size[0] * 4, size[1]))
    for i, t in enumerate(tiles):
        sheet.paste(t, (i * size[0], 0))
    sheet.convert('RGB').save(out)
