"""Reference outline renderer -- the same algorithm the Flutter painter runs.

1. project vertices with a pinhole camera
2. classify faces front / back facing
3. rasterise front faces into a low-res inverse-depth buffer
4. candidate edges: silhouettes (front|back), creases (dihedral > threshold,
   at least one side front-facing), feature polylines
5. sample each candidate, keep samples not behind the depth buffer
6. draw: 12% fill of the front faces, lines on top
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw


class Camera:
    def __init__(self, eye, target, f_px, size, up=(0, 0, 1), roll=0.0, principal=None):
        self.eye = np.asarray(eye, float)
        self.target = np.asarray(target, float)
        self.f = float(f_px)
        self.w, self.h = size
        self.cx, self.cy = principal if principal is not None else (self.w / 2, self.h / 2)
        fwd = self.target - self.eye
        fwd /= np.linalg.norm(fwd)
        right = np.cross(fwd, np.asarray(up, float))
        right /= np.linalg.norm(right)
        upv = np.cross(right, fwd)
        if roll:
            c, s = math.cos(roll), math.sin(roll)
            right, upv = right * c + upv * s, -right * s + upv * c
        self.R = np.stack([right, upv, fwd])  # rows: camera x, y, z in world

    def to_cam(self, p):
        return (np.asarray(p) - self.eye) @ self.R.T

    def project(self, p):
        c = self.to_cam(p)
        z = c[..., 2]
        u = self.cx + self.f * c[..., 0] / z
        v = self.cy - self.f * c[..., 1] / z
        return np.stack([u, v], axis=-1), z


def edge_table(V, F, crease_deg=32.0):
    """Unique edges with their two faces (-1 if boundary) and crease flag."""
    fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    area = np.linalg.norm(fn, axis=1)
    fn = fn / np.maximum(area[:, None], 1e-12)
    em = {}
    for fi, (a, b, c) in enumerate(F):
        for e0, e1 in ((a, b), (b, c), (c, a)):
            k = (min(e0, e1), max(e0, e1))
            em.setdefault(k, []).append(fi)
    E, EF, crease = [], [], []
    cos_t = math.cos(math.radians(crease_deg))
    for (a, b), fs in em.items():
        f1 = fs[0]
        f2 = fs[1] if len(fs) > 1 else -1
        E.append((a, b))
        EF.append((f1, f2))
        if f2 < 0:
            crease.append(True)
        else:
            crease.append(float(np.dot(fn[f1], fn[f2])) < cos_t)
    return np.array(E), np.array(EF), np.array(crease), fn, area


class Outline:
    def __init__(self, V, F, features=(), crease_deg=32.0, part=None):
        self.V = np.asarray(V, float)
        self.F = np.asarray(F, int)
        self.E, self.EF, self.crease, self.fn, self.area = edge_table(self.V, self.F, crease_deg)
        self.part = None if part is None else np.asarray(part)
        self.features = [(np.asarray(f[0], float), np.asarray(f[1], float)) for f in features]

    def render(self, cam: Camera, scale=0.5, tol_abs=0.03, tol_rel=0.006):
        V, F = self.V, self.F
        uv, z = cam.project(V)
        cen = V[F].mean(axis=1)
        facing = np.einsum('ij,ij->i', self.fn, cam.eye - cen) > 0
        facing &= self.area > 1e-10
        # depth buffer of inverse depth at reduced resolution
        bw, bh = int(cam.w * scale), int(cam.h * scale)
        buf = np.zeros((bh, bw), np.float32)
        suv = uv * scale
        iz = 1.0 / z
        for fi in np.nonzero(facing)[0]:
            a, b, c = F[fi]
            _raster(buf, suv[a], suv[b], suv[c], iz[a], iz[b], iz[c])
        # visibility is tested against the *farthest* depth in a 3x3
        # neighbourhood, so a silhouette sample that lands on the pixel of the
        # surface it bounds still counts as visible
        pad = np.pad(buf, 1, mode='constant', constant_values=0)
        far = buf.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                far = np.minimum(far, pad[1 + dy:1 + dy + bh, 1 + dx:1 + dx + bw])
        self.buf = far

        segs_sil, segs_in = [], []
        f1, f2 = self.EF[:, 0], self.EF[:, 1]
        fa = facing[f1]
        fb = np.where(f2 >= 0, facing[np.maximum(f2, 0)], False)
        sil = (fa != fb) & (f2 >= 0)
        inner = self.crease & (fa | fb) & ~sil
        for mask, out in ((sil, segs_sil), (inner, segs_in)):
            for a, b in self.E[mask]:
                out.extend(self._visible(V[a], V[b], cam, scale, tol_abs, tol_rel))
        segs_feat = []
        for pts, nrm in self.features:
            for i in range(len(pts) - 1):
                mid = (pts[i] + pts[i + 1]) / 2
                n = nrm[i]
                if np.dot(n, cam.eye - mid) <= 0:
                    continue
                segs_feat.extend(self._visible(pts[i], pts[i + 1], cam, scale, tol_abs, tol_rel))
        self.facing = facing
        self.uv = uv
        return segs_sil, segs_in, segs_feat

    def _visible(self, p0, p1, cam, scale, tol_abs, tol_rel):
        (u0, v0), z0 = cam.project(p0)
        (u1, v1), z1 = cam.project(p1)
        if z0 <= 0.05 or z1 <= 0.05:
            return []
        L = math.hypot(u1 - u0, v1 - v0) * scale
        n = max(2, int(L / 1.0) + 1)
        t = np.linspace(0, 1, n)
        # perspective-correct depth along the segment
        iz = (1 / z0) * (1 - t) + (1 / z1) * t
        u = u0 + (u1 - u0) * t
        v = v0 + (v1 - v0) * t
        bu = np.clip((u * scale).astype(int), 0, self.buf.shape[1] - 1)
        bv = np.clip((v * scale).astype(int), 0, self.buf.shape[0] - 1)
        b = self.buf[bv, bu]
        # a sample is visible unless something is clearly nearer than it
        zs = 1.0 / iz
        zb = np.where(b > 0, 1.0 / np.maximum(b, 1e-9), np.inf)
        vis = zs <= zb + tol_abs + tol_rel * zs
        inside = (u >= 0) & (u < cam.w) & (v >= 0) & (v < cam.h)
        vis &= inside
        out = []
        i = 0
        while i < n:
            if vis[i]:
                j = i
                while j + 1 < n and vis[j + 1]:
                    j += 1
                if j > i:
                    out.append(((u[i], v[i]), (u[j], v[j])))
                i = j + 1
            else:
                i += 1
        return out


def _raster(buf, a, b, c, za, zb, zc):
    h, w = buf.shape
    xmin = max(int(math.floor(min(a[0], b[0], c[0]))), 0)
    xmax = min(int(math.ceil(max(a[0], b[0], c[0]))), w - 1)
    ymin = max(int(math.floor(min(a[1], b[1], c[1]))), 0)
    ymax = min(int(math.ceil(max(a[1], b[1], c[1]))), h - 1)
    if xmin > xmax or ymin > ymax:
        return
    den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(den) < 1e-12:
        return
    xs = np.arange(xmin, xmax + 1) + 0.5
    ys = np.arange(ymin, ymax + 1) + 0.5
    X, Y = np.meshgrid(xs, ys)
    l1 = ((b[1] - c[1]) * (X - c[0]) + (c[0] - b[0]) * (Y - c[1])) / den
    l2 = ((c[1] - a[1]) * (X - c[0]) + (a[0] - c[0]) * (Y - c[1])) / den
    l3 = 1 - l1 - l2
    m = (l1 >= -1e-4) & (l2 >= -1e-4) & (l3 >= -1e-4)
    if not m.any():
        return
    iz = l1 * za + l2 * zb + l3 * zc
    sub = buf[ymin:ymax + 1, xmin:xmax + 1]
    upd = m & (iz > sub)
    sub[upd] = iz[upd]


def draw(outline: Outline, cam: Camera, base=None, color=(255, 255, 255), fill_alpha=0.12,
         sil_w=3, in_w=2, feat_w=2, scale=0.5):
    segs_sil, segs_in, segs_feat = outline.render(cam, scale=scale)
    W, H = cam.w, cam.h
    SS = 2
    over = Image.new('RGBA', (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    # fill
    fill = Image.new('L', (W * SS, H * SS), 0)
    fd = ImageDraw.Draw(fill)
    for fi in np.nonzero(outline.facing)[0]:
        pts = [tuple(outline.uv[i] * SS) for i in outline.F[fi]]
        fd.polygon(pts, fill=255)
    for segs, w, a in ((segs_in, in_w, 200), (segs_feat, feat_w, 220), (segs_sil, sil_w, 255)):
        for (p, q) in segs:
            d.line([(p[0] * SS, p[1] * SS), (q[0] * SS, q[1] * SS)], fill=color + (a,), width=w * SS)
    over = over.resize((W, H), Image.LANCZOS)
    fill = fill.resize((W, H), Image.LANCZOS)
    tint = Image.new('RGBA', (W, H), color + (0,))
    tint.putalpha(fill.point(lambda v: int(v * fill_alpha)))
    if base is None:
        base = Image.new('RGBA', (W, H), (30, 40, 55, 255))
    out = base.convert('RGBA')
    out.alpha_composite(tint)
    out.alpha_composite(over)
    return out
