"""Back-project annotated photo points onto the model surface -> (s, z)."""
import json, math
import numpy as np
from PIL import Image
import aqua
from fit import cam_from


def ray_mesh(orig, dirs, V, F):
    """First hit distance of each ray against the triangles (Moller-Trumbore)."""
    v0, v1, v2 = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    e1, e2 = v1 - v0, v2 - v0
    out = []
    for d in dirs:
        p = np.cross(d, e2)
        det = np.einsum('ij,ij->i', e1, p)
        ok = np.abs(det) > 1e-12
        inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
        t = orig - v0
        u = np.einsum('ij,ij->i', t, p) * inv
        q = np.cross(t, e1)
        v = np.einsum('j,ij->i', d, q) * inv
        dist = np.einsum('ij,ij->i', e2, q) * inv
        hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (dist > 0)
        out.append(dist[hit].min() if hit.any() else np.nan)
    return np.array(out)


def pixel_rays(cam, pts):
    pts = np.asarray(pts, float)
    x = (pts[:, 0] - cam.cx) / cam.f
    y = -(pts[:, 1] - cam.cy) / cam.f
    d = x[:, None] * cam.R[0] + y[:, None] * cam.R[1] + cam.R[2]
    return d / np.linalg.norm(d, axis=1, keepdims=True)


def backproject(photo, camjson, pts, body_only=True):
    size = Image.open(photo).size
    cam = cam_from(json.load(open(camjson)), size)
    m = aqua.build()
    V = np.array(m.v); F = np.array(m.f); P = np.array(m.part)
    if body_only:
        F = F[P == aqua.PART_BODY]
    dirs = pixel_rays(cam, pts)
    t = ray_mesh(cam.eye, dirs, V, F)
    X = cam.eye + dirs * t[:, None]
    return X


if __name__ == '__main__':
    groups = {
        'belt': [(1440, 395), (1300, 381), (1200, 372), (1100, 364), (1000, 356), (900, 350), (820, 345)],
        'quarter_low': [(820, 345), (760, 290), (697, 238)],
        'divider': [(797, 222), (830, 345)],
        'b_rear': [(1015, 168), (1050, 360)],
        'b_front': [(1045, 170), (1088, 365)],
        'door_gap': [(1105, 385), (1112, 450), (1120, 550), (1128, 690)],
        'rear_door_rear': [(690, 176), (672, 200), (668, 260), (680, 320), (700, 360), (740, 430), (790, 500), (840, 580), (872, 650), (880, 690)],
        'front_door_front': [(1512, 410), (1518, 500), (1524, 600), (1528, 685)],
        'sill': [(880, 692), (1100, 692), (1300, 690), (1520, 688)],
    }
    out = {}
    for k, pts in groups.items():
        X = backproject('refs/2017-2021_Toyota_Aqua_rear.jpg', 'side_cam.json', pts)
        s = aqua.X_FRONT - X[:, 0]
        out[k] = [(round(float(a), 3), round(float(y), 3), round(float(z), 3)) for a, y, z in zip(s, X[:, 1], X[:, 2])]
        print(k, out[k])
    json.dump(out, open('side_features.json', 'w'), indent=1)
