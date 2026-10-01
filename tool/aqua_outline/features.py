"""Surface detail lines -- windows, doors, lamps, grille, plates.

Each line is authored as a list of anchor points with a projection
direction.  At build time every anchor is shot onto the body along -dir from
just outside it, so the lines sit on the surface whatever the body looks like.

The anchors themselves come from two sources:

* traced on real photos and back-projected through the solved cameras
  (`trace()`, run once; the result is `features_src.json`)
* defined from the car's own geometry (windscreen edges, window tops), which
  follow the body parameters directly.
"""
from __future__ import annotations

import json
import math
import os

import numpy as np

import aqua

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'features_src.json')

# ---------------------------------------------------------------------------
# Photo traces (image pixels), grouped by photo.  Only the car's right side is
# traced; everything is mirrored to the left.
# ---------------------------------------------------------------------------
SIDE_TRACES = {
    # 2017-2021_Toyota_Aqua_rear.jpg, camera from fit.SIDE_PHOTO
    'rear_glass': ([(275, 222), (505, 230), (525, 246), (480, 350), (265, 346), (205, 332), (240, 262), (275, 222)], False),
    'taillight': ([(540, 250), (575, 265), (630, 320), (640, 360), (620, 430), (580, 480), (520, 510), (470, 505),
                   (478, 420), (505, 320), (540, 250)], True),
    'rear_plate': ([(247, 432), (333, 437), (330, 510), (246, 503), (247, 432)], False),
    'hatch_bottom': ([(180, 520), (240, 530), (300, 537), (370, 542), (430, 545)], True),
}
FRONT_TRACES = {
    # 2017-2021_Toyota_Aqua.jpg, camera from fit.FRONT_PHOTO
    'headlight': ([(1145, 432), (1200, 440), (1300, 460), (1400, 490), (1455, 530), (1420, 548), (1330, 540),
                   (1250, 520), (1195, 500), (1160, 470), (1145, 432)], True),
    'hood_front': ([(1455, 512), (1500, 514), (1560, 510), (1610, 506), (1650, 503)], True),
    'grille_near': ([(1650, 566), (1515, 572), (1455, 630), (1420, 690), (1425, 730), (1480, 772), (1650, 771)], True),
    'fog_inlet': ([(1188, 617), (1215, 622), (1290, 685), (1355, 745), (1340, 755), (1300, 748), (1240, 712),
                   (1195, 655), (1188, 617)], True),
    'front_plate': ([(1583, 614), (1693, 612), (1693, 698), (1585, 700), (1583, 614)], False),
}


def trace():
    """Back-project the photo traces onto the current body -> features_src.json."""
    import backproject
    import fit
    from PIL import Image

    m = aqua.build(with_features=False)
    V = np.array(m.v)
    F = np.array(m.f)
    P = np.array(m.part)
    body = F[P == aqua.PART_BODY]
    fn = np.cross(V[body[:, 1]] - V[body[:, 0]], V[body[:, 2]] - V[body[:, 0]])
    fn /= np.linalg.norm(fn, axis=1, keepdims=True)
    out = []
    for photo, camfile, traces in (
        (fit.SIDE_PHOTO['path'], 'side_cam.json', SIDE_TRACES),
        (fit.FRONT_PHOTO['path'], 'front_cam.json', FRONT_TRACES),
    ):
        size = Image.open(os.path.join(HERE, photo)).size
        cam = fit.cam_from(json.load(open(os.path.join(HERE, camfile))), size)
        for name, (pts, mirror) in traces.items():
            dirs = backproject.pixel_rays(cam, pts)
            X, N = [], []
            for d in dirs:
                t, k = _first_hit(cam.eye, d, V, body)
                if k is None:
                    continue
                X.append((cam.eye + d * t).tolist())
                N.append(fn[k].tolist())
            out.append({'name': name, 'pts': X, 'dirs': N, 'mirror': mirror})
            print(name, len(X), 'of', len(pts))
    json.dump(out, open(SRC, 'w'), indent=1)


def _first_hit(orig, d, V, F):
    v0, v1, v2 = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    e1, e2 = v1 - v0, v2 - v0
    p = np.cross(d, e2)
    det = np.einsum('ij,ij->i', e1, p)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
    t = orig - v0
    u = np.einsum('ij,ij->i', t, p) * inv
    q = np.cross(t, e1)
    v = np.einsum('j,ij->i', d, q) * inv
    dist = np.einsum('ij,ij->i', e2, q) * inv
    hit = ok & (u >= -1e-6) & (v >= -1e-6) & (u + v <= 1 + 1e-6) & (dist > 0)
    if not hit.any():
        return None, None
    idx = np.nonzero(hit)[0]
    k = idx[np.argmin(dist[idx])]
    return dist[k], k


# ---------------------------------------------------------------------------
# Lines defined from the geometry
# ---------------------------------------------------------------------------
def _side(s, z, side=1):
    """Anchor on the body side at (s, z), projected along the side normal."""
    return [float(aqua.sx(s)), side * 1.2, float(z)], [0.0, float(side), 0.0]


def geometric():
    lines = []
    s_top = np.linspace(1.12, 3.30, 60)
    zb = aqua.z_belt

    def top_z(s):
        z, y, _ = aqua.top_edge(float(s))
        return z - 0.030

    # window line (DLO): belt from the A-pillar base back to the quarter glass,
    # up to the rear tip, along under the roof rail, and down the A-pillar
    front = 1.40
    for s in np.linspace(1.10, 1.60, 200):
        if top_z(s) > zb(s):
            front = s
            break
    belt = [(s, float(zb(s))) for s in np.linspace(front, 3.15, 24)]
    tip = [(3.23, 1.10), (3.32, 1.205)]
    rail = [(s, top_z(s)) for s in np.linspace(3.28, front, 40)]
    dlo = belt + tip + rail
    lines.append(('dlo', [_side(s, z) for s, z in dlo], True, True))
    # B-pillar and the quarter-glass divider
    # B-pillar and door gap: the side photo and the front photo disagree by
    # ~0.12 m mid-car (long-lens depth ambiguity); these split the difference
    lines.append(('b_pillar_f', [_side(2.42, zb(2.42)), _side(2.48, top_z(2.48))], True, False))
    lines.append(('b_pillar_r', [_side(2.515, zb(2.515)), _side(2.58, top_z(2.58))], True, False))
    lines.append(('divider', [_side(3.125, zb(3.125)), _side(3.08, top_z(3.08))], True, False))
    # door cut lines
    lines.append(('door_front', [_side(s, z) for s, z in [(1.25, 0.28), (1.27, 0.47), (1.29, 0.69), (1.26, zb(1.26))]], True, False))
    lines.append(('door_gap', [_side(s, z) for s, z in [(2.31, 0.28), (2.33, 0.585), (2.34, 0.80), (2.345, zb(2.345))]], True, False))
    lines.append(('door_rear', [_side(s, z) for s, z in [(2.974, 0.296), (3.005, 0.38), (3.097, 0.526), (3.228, 0.69),
                                                         (3.346, 0.83), (3.428, 0.969), (3.44, 1.02)]], True, False))
    lines.append(('sill', [_side(s, 0.275) for s in np.linspace(1.25, 2.97, 12)], True, False))
    # windscreen: cowl, header and the two A-pillar glass edges, on the crown
    def crown_pt(s, frac):
        z_e, y_e, m = aqua.top_edge(float(s))
        z_hi = float(aqua.upper_z(s))
        y = frac * y_e * 0.94
        # superellipse crown: z at lateral fraction
        c = min(1.0, abs(y) / max(y_e, 1e-6))
        th = math.acos(c ** (m / 2)) if c < 1 else 0.0
        z = z_e + (z_hi - z_e) * math.sin(th) ** (2 / m)
        return [float(aqua.sx(s)), y, z + 0.3], [0.0, 0.0, 1.0]
    cowl = [crown_pt(1.13, f) for f in np.linspace(-1, 1, 21)]
    header = [crown_pt(1.93, f) for f in np.linspace(-1, 1, 21)]
    lines.append(('cowl', cowl, False, False))
    lines.append(('header', header, False, False))
    return lines


def build(mesh) -> list:
    """Project every line onto `mesh`; returns [(points Nx3, normals Nx3)]."""
    V = np.array(mesh.v)
    F = np.array(mesh.f)
    P = np.array(mesh.part)
    body = F[P == aqua.PART_BODY]
    fn = np.cross(V[body[:, 1]] - V[body[:, 0]], V[body[:, 2]] - V[body[:, 0]])
    fn /= np.linalg.norm(fn, axis=1, keepdims=True)

    def shoot(p, d):
        p = np.asarray(p, float)
        d = np.asarray(d, float)
        d = d / np.linalg.norm(d)
        orig = p + d * 0.6
        t, k = _first_hit(orig, -d, V, body)
        if k is None:
            return None
        return orig - d * t, fn[k]

    lines = []
    for name, anchors, mirror, closed in geometric():
        lines.append((name, anchors, mirror, closed))
    if os.path.exists(SRC):
        for f in json.load(open(SRC)):
            lines.append((f['name'], list(zip(f['pts'], f['dirs'])), f['mirror'], False))

    out = []
    for name, anchors, mirror, closed in lines:
        variants = [1, -1] if mirror else [1]
        for sgn in variants:
            pts, nrm = [], []
            for p, d in anchors:
                p = np.array(p, float)
                d = np.array(d, float)
                if sgn < 0:
                    p[1] = -p[1]
                    d[1] = -d[1]
                hit = shoot(p, d)
                if hit is None:
                    continue
                pts.append(hit[0])
                nrm.append(hit[1])
            if len(pts) < 2:
                continue
            pts, nrm = _densify(np.array(pts), np.array(nrm), shoot, closed)
            # lift a few mm off the surface so faceting never hides the line
            out.append((pts + nrm * 0.006, nrm, name))
    return out


def _densify(pts, nrm, shoot, closed, step=0.04):
    """Re-shoot extra points between anchors so long lines follow the surface."""
    if closed:
        pts = np.vstack([pts, pts[:1]])
        nrm = np.vstack([nrm, nrm[:1]])
    P, N = [pts[0]], [nrm[0]]
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        n = max(1, int(math.ceil(np.linalg.norm(b - a) / step)))
        for j in range(1, n + 1):
            t = j / n
            p = a + (b - a) * t
            d = nrm[i] * (1 - t) + nrm[i + 1] * t
            if j < n:
                hit = shoot(p, d)
                if hit is not None:
                    P.append(hit[0])
                    N.append(hit[1])
                    continue
            P.append(b if j == n else p)
            N.append(nrm[i + 1] if j == n else d / np.linalg.norm(d))
    return np.array(P), np.array(N)


if __name__ == '__main__':
    trace()
