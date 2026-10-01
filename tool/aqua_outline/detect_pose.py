"""Run the app's car detector on photos and read the corner off the box.

Same model, same box, same aspect curve as the app (viewport 3:4, fovY 66°,
eye 1.40 m, look-at 0.62 m, distance fitted to 82% width at the target)."""
import json, math, sys
import numpy as np
from PIL import Image
from ai_edge_litert.interpreter import Interpreter

import aqua
from render import Camera

import os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
itp = Interpreter(model_path=f'{ROOT}/assets/models/detect.tflite')
itp.allocate_tensors()
inp = itp.get_input_details()[0]
out = itp.get_output_details()
labels = [l.strip() for l in open(f'{ROOT}/assets/models/labelmap.txt')]


def detect(path):
    im = Image.open(path).convert('RGB')
    W, H = im.size
    x = np.asarray(im.resize((inp['shape'][2], inp['shape'][1])), dtype=np.uint8)[None]
    itp.set_tensor(inp['index'], x)
    itp.invoke()
    boxes, classes, scores, count = [itp.get_tensor(o['index']) for o in out]
    best = None
    for i in range(int(count[0])):
        lab = labels[int(round(classes[0][i])) + 1]
        if lab not in ('car', 'truck', 'bus') or scores[0][i] < 0.3:
            continue
        if best is None or scores[0][i] > best[1]:
            best = (boxes[0][i], float(scores[0][i]))
    if best is None:
        return None
    ymin, xmin, ymax, xmax = best[0]
    return dict(score=best[1], box=[float(xmin), float(ymin), float(xmax), float(ymax)],
                aspect=float((xmax - xmin) * W / ((ymax - ymin) * H)))


m = aqua.build()
V = np.array(m.v)
VIEW = (346, 461)
FOV = 66.0


def bounds(az, dist):
    a = math.radians(az)
    t = np.array([0, 0, 0.62])
    eye = np.array([dist * math.cos(a), dist * math.sin(a), 1.40])
    f = VIEW[1] / 2 / math.tan(math.radians(FOV / 2))
    cam = Camera(eye, t, f, VIEW)
    uv, _ = cam.project(V)
    return uv[:, 0].min(), uv[:, 1].min(), uv[:, 0].max(), uv[:, 1].max()


def fit(az, frac=0.82):
    lo, hi = 2.0, 20.0
    for _ in range(28):
        mid = (lo + hi) / 2
        x0, _, x1, _ = bounds(az, mid)
        if x1 - x0 > VIEW[0] * frac:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def curve(dist, step=2):
    out = []
    for az in np.arange(-180, 180, step):
        x0, y0, x1, y1 = bounds(az, dist)
        out.append((x1 - x0) / (y1 - y0))
    return out


def candidates(c, aspect, step=2):
    out = []
    n = len(c)
    for i in range(n):
        a, b = c[i], c[(i + 1) % n]
        lo, hi = min(a, b), max(a, b)
        if lo <= aspect <= hi and hi > lo:
            t = (aspect - a) / (b - a)
            out.append(round(((-180 + (i + t) * step) + 180) % 360 - 180, 1))
    return out


if __name__ == '__main__':
    d = fit(40)
    c = curve(d)
    print(f'fitted distance {d:.2f} m; aspect range {min(c):.2f}..{max(c):.2f}; at 40° {c[110]:.2f}')
    truth = {'左前': 40, '右前': -40, '右後': -140, '左後': 140}
    for name in sys.argv[1:]:
        r = detect(f'{ROOT}/demo/return_photos/{name}.webp')
        if r is None:
            print(name, 'no car'); continue
        cand = candidates(c, r['aspect'])
        exp = truth.get(name)
        err = min(abs(((x - exp) + 180) % 360 - 180) for x in cand) if exp is not None and cand else None
        print(f"{name}: score {r['score']:.2f} aspect {r['aspect']:.2f} -> {cand}  (nearest to {exp}: err {err})")
