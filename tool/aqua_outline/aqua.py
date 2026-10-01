"""Low-poly Toyota AQUA (NHP10, 2017 facelift) for the return-photo outline guide.

Coordinates, metres: x forward (front bumper tip at +L/2), y to the car's
left, z up, ground at z = 0.

    全長 4,050  全幅 1,695  全高 1,455  軸距 2,550  (toyota.jp 主要諸元 2019-03)
    輪距 前 1,470 / 後 1,460   最低地上高 140   輪胎 185/60R15
    前懸 850 / 後懸 650  (Prius c 2015: 810 / 635 at L = 3,995; the facelift
                          bumpers added 55 mm, split here 40 front / 15 rear)

The body is a loft of cross-sections taken across the car.  Each section
spans the side profile's bottom and top at that station and is as wide as
the plan view allows; its upper corners are rounded into a crown (hood,
windscreen, roof or tailgate) and the greenhouse above the beltline leans in.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np

L = 4.050
W = 1.695
H = 1.455
WB = 2.550
F_OH = 0.850
R_OH = L - WB - F_OH
TRACK_F = 1.470
TRACK_R = 1.460
TIRE_R = 0.300
TIRE_W = 0.185
RIM_R = 0.205

X_FRONT = L / 2
X_REAR = -L / 2
X_FA = X_FRONT - F_OH
X_RA = X_FA - WB
HUB_Z = 0.295


def sx(s):
    return X_FRONT - s


# Side profile, (s, z) with s = metres behind the front tip.
UPPER = [
    (0.000, 0.505), (0.010, 0.585), (0.035, 0.650),
    (0.085, 0.705),   # hood leading edge
    (0.220, 0.760), (0.450, 0.815), (0.700, 0.862), (0.920, 0.900),
    (1.080, 0.932),   # cowl
    (1.300, 1.045), (1.550, 1.175), (1.800, 1.300),
    (1.980, 1.380),   # header
    (2.150, 1.428), (2.400, 1.453),
    (2.650, 1.455),   # roof peak, over the rear seat
    (2.900, 1.440), (3.150, 1.405), (3.400, 1.350), (3.620, 1.296), (3.790, 1.268),
    (3.845, 1.250),   # spoiler tip
    (3.852, 1.200), (3.880, 1.000), (3.940, 0.840), (4.005, 0.680), (4.038, 0.590),
    (4.050, 0.520),   # rearmost, bumper
]

ARCH_R = 0.340
ARCH_CZ = 0.295
SILL_Z = 0.190

_US = np.array([p[0] for p in UPPER])
# The published 1,455 is to the top of the roof fin; two photo overlays put
# the roof itself 3-5 cm lower, so the roof zone is dropped here and the fin is
# modelled on its own.
_UZ = np.array([p[1] for p in UPPER]) + np.interp(
    _US, [1.08, 1.98, 2.65, 3.40, 3.85], [0.0, -0.045, -0.055, -0.042, -0.025])


def upper_z(s):
    return np.interp(s, _US, _UZ)


def lower_z(s):
    """Underside of the body at s: bumpers, sill, and the wheel arches."""
    s = np.asarray(s, dtype=float)
    base = np.interp(s, [0.0, 0.015, 0.055, 0.12, 0.26, 0.42, 1.33, 1.70, 2.60, 2.95, 3.79, 3.85,
                         3.95, 4.010, 4.043, 4.050],
                     [0.505, 0.390, 0.285, 0.225, 0.215, 0.232, SILL_Z + 0.02, SILL_Z, SILL_Z,
                      SILL_Z + 0.02, 0.235, 0.232, 0.250, 0.320, 0.420, 0.520])
    out = base.copy()
    for s_c in (F_OH, F_OH + WB):
        dx = s - s_c
        inside = np.abs(dx) < ARCH_R
        arch = ARCH_CZ + np.sqrt(np.maximum(ARCH_R ** 2 - dx ** 2, 0))
        out = np.where(inside, np.maximum(base, arch), out)
    return out


B = W / 2
Z_SHOULDER = 0.70


def z_belt(s):
    return np.interp(s, [0.9, 1.25, 2.0, 2.9, 3.35, 3.8], [0.93, 0.972, 1.010, 1.055, 1.080, 1.10])


def w_belt(s):
    return np.interp(s, [0.0, 1.0, 1.25, 1.7, 3.2, 3.6, 3.85, 4.05], [0.80, 0.790, 0.785, 0.815, 0.815, 0.780, 0.700, 0.640])


def body_hw(s, z):
    """Half-width of the metal below the beltline."""
    lower = B - 0.055 * np.clip((Z_SHOULDER - z) / (Z_SHOULDER - 0.18), 0, 1.4) ** 2
    zb = z_belt(s)
    t = np.clip((z - Z_SHOULDER) / np.maximum(zb - Z_SHOULDER, 1e-3), 0, 1)
    upper = B + (w_belt(s) - B) * t ** 1.5
    return float(np.where(z < Z_SHOULDER, lower, upper))


def top_edge(s):
    """Where the crown starts at station s: (z, half-width, exponent)."""
    zt = float(upper_z(s))
    if s < 1.08:      # hood: fender line
        d = float(np.interp(s, [0.0, 0.085, 0.5, 1.08], [0.05, 0.09, 0.10, 0.10]))
        return zt - d, body_hw(s, zt - d), 2.8
    if s < 1.98:      # windscreen: A-pillar
        t = (s - 1.08) / 0.90
        return zt - (0.075 + 0.030 * t), 0.705 - 0.095 * t, 2.4
    if s < 3.845:     # roof: roof rails
        # the spoiler is a flat wing, so the crown flattens out towards it
        d = float(np.interp(s, [1.98, 2.6, 3.4, 3.65, 3.845], [0.105, 0.100, 0.090, 0.060, 0.035]))
        y = float(np.interp(s, [1.98, 2.6, 3.3, 3.845], [0.610, 0.615, 0.585, 0.500]))
        return zt - d, y, 2.4
    d = float(np.interp(s, [3.845, 3.95, 4.05], [0.05, 0.09, 0.06]))   # tailgate
    z = zt - d
    zb = float(z_belt(s))
    y = float(np.interp(z, [zb, 1.25], [0.58, 0.47])) if z > zb else body_hw(s, z)
    return z, y, 2.4


def plan(s, z=0.5):
    """Plan-view taper at the nose and tail, as a fraction of full width.

    The tail rounds harder above the bumper: the lamps wrap round the corners
    and the tailgate is much narrower than the bumper under it."""
    if s < 0.75:
        u = 1 - s / 0.75
        return 0.50 + 0.50 * (1 - u ** 2.0) ** 0.5
    rt = L - s
    zs = [0.50, 0.70, 1.00, 1.15, 1.25]
    f0 = float(np.interp(z, zs, [0.74, 0.58, 0.50, 0.60, 0.85]))
    rr = float(np.interp(z, zs, [0.36, 0.60, 0.80, 0.60, 0.30]))
    if rt < rr:
        u = 1 - rt / rr
        return f0 + (1 - f0) * (1 - u ** 2.2) ** (1 / 2.2)
    return 1.0


def section(s, n_side=8, n_crown=7, n_bot=3):
    """Half cross-section at s: (y, z) from bottom centre, up +y, to top centre."""
    z_lo = float(lower_z(s))
    z_hi = float(upper_z(s))
    z_e, y_e, m = top_edge(s)
    d_bot = min(0.035, 0.3 * max(z_hi - z_lo, 1e-3))
    z0 = z_lo + d_bot
    if z_e <= z0 + 0.005:                 # thin end sections: squeeze the crown
        z_e = z0 + 0.45 * max(z_hi - z0, 1e-4)
        y_e = body_hw(s, z_e)
    pts = [(0.0, z_lo)]
    y_b = body_hw(s, z0) * plan(s, z0)
    for j in range(1, n_bot + 1):
        th = (math.pi / 2) * j / n_bot
        pts.append((y_b * math.sin(th) ** (2 / 3.0), z_lo + d_bot * (1 - math.cos(th) ** (2 / 3.0))))
    zb = float(z_belt(s))
    for j in range(1, n_side + 1):
        z = z0 + (z_e - z0) * j / n_side
        if z_e <= zb:
            y = body_hw(s, z) if j < n_side else y_e
        elif z <= zb:
            y = body_hw(s, z)
        else:
            yb = body_hw(s, zb)
            y = yb + (y_e - yb) * (z - zb) / max(z_e - zb, 1e-4)
        pts.append((y * plan(s, z), z))
    y_top = pts[-1][0]
    d_top = z_hi - z_e
    for j in range(1, n_crown + 1):
        th = (math.pi / 2) * j / n_crown
        pts.append((y_top * math.cos(th) ** (2 / m), z_e + d_top * math.sin(th) ** (2 / m)))
    pts[-1] = (0.0, z_hi)
    return pts


def stations():
    s = [0.0, 0.003, 0.010, 0.022, 0.040, 0.062, 0.085, 0.12, 0.17, 0.23, 0.30]
    s += list(np.arange(0.38, 3.80, 0.085))
    s += [3.80, 3.845, 3.870, 3.900, 3.935, 3.965, 3.995, 4.018, 4.035, 4.045, 4.050]
    for s_c in (F_OH, F_OH + WB):          # a station right at each arch edge
        for t in np.linspace(-1, 1, 11):
            s.append(s_c + t * (ARCH_R - 0.002))
    return np.array(sorted(set(round(float(v), 4) for v in s)))


@dataclass
class Mesh:
    v: list = field(default_factory=list)
    f: list = field(default_factory=list)
    part: list = field(default_factory=list)
    features: list = field(default_factory=list)
    fin: set = field(default_factory=set)

    def add_v(self, p):
        self.v.append(tuple(float(c) for c in p))
        return len(self.v) - 1

    def add_f(self, a, b, c, part=0):
        if a == b or b == c or a == c:
            return
        self.f.append((a, b, c))
        self.part.append(part)

    def quad(self, a, b, c, d, part=0):
        self.add_f(a, b, c, part)
        self.add_f(a, c, d, part)


PART_BODY, PART_WHEEL, PART_MIRROR, PART_WELL = 0, 1, 2, 3


def make_consistent(mesh: Mesh, first_face: int, last_face: int):
    """Flood-fill a consistent winding, then point the shell outwards."""
    from collections import deque
    faces = [list(mesh.f[k]) for k in range(first_face, last_face)]
    edge_faces = {}
    for k, (a, b, c) in enumerate(faces):
        for e in ((a, b), (b, c), (c, a)):
            edge_faces.setdefault((min(e), max(e)), []).append(k)
    seen = [False] * len(faces)
    for start in range(len(faces)):
        if seen[start]:
            continue
        seen[start] = True
        dq = deque([start])
        while dq:
            k = dq.popleft()
            a, b, c = faces[k]
            for e0, e1 in ((a, b), (b, c), (c, a)):
                for j in edge_faces[(min(e0, e1), max(e0, e1))]:
                    if j == k or seen[j]:
                        continue
                    fa, fb, fc = faces[j]
                    if (fa, fb) == (e0, e1) or (fb, fc) == (e0, e1) or (fc, fa) == (e0, e1):
                        faces[j] = [fa, fc, fb]
                    seen[j] = True
                    dq.append(j)
    V = np.array(mesh.v)
    F = np.array(faces)
    vol = np.einsum('ij,ij->i', V[F[:, 0]], np.cross(V[F[:, 1]], V[F[:, 2]])).sum()
    if vol < 0:
        F = F[:, [0, 2, 1]]
    for k, f in enumerate(F):
        mesh.f[first_face + k] = tuple(int(i) for i in f)


def build_body(mesh: Mesh):
    rows = []
    for s in stations():
        half = section(s)
        ring = [(-y, z) for y, z in reversed(half[1:-1])] + half
        rows.append([mesh.add_v((sx(s), y, z)) for y, z in ring])
    f0 = len(mesh.f)
    n = len(rows[0])
    for r in range(len(rows) - 1):
        a, b = rows[r], rows[r + 1]
        for j in range(n):
            j2 = (j + 1) % n
            mesh.quad(a[j], a[j2], b[j2], b[j], PART_BODY)
    for row in (rows[0], rows[-1]):
        ci = mesh.add_v(np.mean([mesh.v[i] for i in row], axis=0))
        for j in range(n):
            mesh.add_f(row[j], row[(j + 1) % n], ci, PART_BODY)
    make_consistent(mesh, f0, len(mesh.f))


def build_wheel(mesh: Mesh, xc, side, track, seg=24):
    yc = side * track / 2
    hw = TIRE_W / 2
    prof = [(TIRE_R - 0.08, -hw), (TIRE_R - 0.02, -hw), (TIRE_R, -hw + 0.035),
            (TIRE_R, hw - 0.035), (TIRE_R - 0.02, hw), (RIM_R + 0.01, hw - 0.004),
            (RIM_R - 0.012, hw - 0.028), (0.06, hw - 0.045)]
    rings = []
    for r, dy in prof:
        rings.append([mesh.add_v((xc + r * math.cos(2 * math.pi * k / seg), yc + side * dy,
                                  HUB_Z + r * math.sin(2 * math.pi * k / seg))) for k in range(seg)])
    f0 = len(mesh.f)
    for r in range(len(rings) - 1):
        for k in range(seg):
            k2 = (k + 1) % seg
            mesh.quad(rings[r][k], rings[r][k2], rings[r + 1][k2], rings[r + 1][k], PART_WHEEL)
    hub = mesh.add_v((xc, yc + side * (hw - 0.05), HUB_Z))
    inner = mesh.add_v((xc, yc - side * hw, HUB_Z))
    for k in range(seg):
        k2 = (k + 1) % seg
        mesh.add_f(rings[-1][k], rings[-1][k2], hub, PART_WHEEL)
        mesh.add_f(rings[0][k2], rings[0][k], inner, PART_WHEEL)
    make_consistent(mesh, f0, len(mesh.f))


def build_box(mesh: Mesh, lo, hi, part):
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    c = [mesh.add_v(p) for p in [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                                 (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]]
    f0 = len(mesh.f)
    for q in [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]:
        mesh.quad(*[c[i] for i in q], part)
    make_consistent(mesh, f0, len(mesh.f))


def build_liner(mesh: Mesh, xa):
    """Wheel-well liner: the arch opening extruded across the car, closed
    underneath, so nothing but the tunnel's own wall shows through the arch."""
    a = math.acos((0.17 - ARCH_CZ) / (ARCH_R - 0.01))
    pts = []
    for t in np.linspace(-a, a, 13):
        pts.append((xa + (ARCH_R - 0.01) * math.sin(t), ARCH_CZ + (ARCH_R - 0.01) * math.cos(t)))
    rings = [[mesh.add_v((x, yy, z)) for x, z in pts] for yy in (-0.60, 0.60)]
    f0 = len(mesh.f)
    n = len(pts)
    for k in range(n):
        k2 = (k + 1) % n
        mesh.quad(rings[0][k], rings[0][k2], rings[1][k2], rings[1][k], PART_WELL)
    for ring in rings:
        ci = mesh.add_v(np.mean([mesh.v[i] for i in ring], axis=0))
        for k in range(n):
            mesh.add_f(ring[k], ring[(k + 1) % n], ci, PART_WELL)
    make_consistent(mesh, f0, len(mesh.f))


def build_mirror(mesh: Mesh, side):
    s0 = 1.30
    x_f, x_r = sx(s0 - 0.03), sx(s0 + 0.19)
    z_lo, z_hi = 0.915, 1.055
    seg = 10
    rings = []
    for t, (yy, scale) in enumerate([(0.765, 0.35), (0.825, 0.8), (0.88, 1.0), (0.945, 0.92), (0.975, 0.55)]):
        cx, cz = (x_f + x_r) / 2 - 0.02 * t, (z_lo + z_hi) / 2
        rx, rz = (x_f - x_r) / 2 * scale, (z_hi - z_lo) / 2 * scale
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            ex = math.cos(a) * (0.5 if math.cos(a) < 0 else 1.0)
            ring.append(mesh.add_v((cx + rx * ex, side * yy, cz + rz * math.sin(a))))
        rings.append(ring)
    f0 = len(mesh.f)
    for r in range(len(rings) - 1):
        for k in range(seg):
            k2 = (k + 1) % seg
            mesh.quad(rings[r][k], rings[r][k2], rings[r + 1][k2], rings[r + 1][k], PART_MIRROR)
    for ring in (rings[0], rings[-1]):
        ci = mesh.add_v(np.mean([mesh.v[i] for i in ring], axis=0))
        for k in range(seg):
            mesh.add_f(ring[k], ring[(k + 1) % seg], ci, PART_MIRROR)
    make_consistent(mesh, f0, len(mesh.f))


def build_fin(mesh: Mesh):
    """Roof fin antenna; its tip is the published overall height."""
    s0, s1 = 3.18, 3.40
    zr0 = float(upper_z(s0)) - 0.004
    zr1 = float(upper_z(s1)) - 0.004
    tip = (sx(s0 + 0.13), H)
    prof = [(sx(s0), zr0), (sx(s1), zr1), (tip[0] - 0.05, H - 0.012), tip]
    first = len(mesh.v)
    ring_l = [mesh.add_v((x, 0.035, z)) for x, z in prof[:2]]
    ring_r = [mesh.add_v((x, -0.035, z)) for x, z in prof[:2]]
    top = [mesh.add_v((x, 0.0, z)) for x, z in prof[2:]]
    # The detector's box does not reach up to a 7 cm antenna, so the box
    # the app predicts (the hull) leaves it out. See export.py.
    mesh.fin = set(range(first, len(mesh.v)))
    f0 = len(mesh.f)
    mesh.quad(ring_l[0], ring_l[1], ring_r[1], ring_r[0], PART_MIRROR)
    mesh.add_f(ring_l[0], top[1], ring_l[1], PART_MIRROR)
    mesh.add_f(ring_l[1], top[1], top[0], PART_MIRROR)
    mesh.add_f(ring_r[0], ring_r[1], top[1], PART_MIRROR)
    mesh.add_f(ring_r[1], top[0], top[1], PART_MIRROR)
    mesh.add_f(ring_l[1], top[0], ring_r[1], PART_MIRROR)
    mesh.add_f(ring_l[0], ring_r[0], top[1], PART_MIRROR)
    make_consistent(mesh, f0, len(mesh.f))


def build_spoiler(mesh: Mesh):
    """Roof spoiler: a flat wing that runs on past the rear glass."""
    s0, s1 = 3.58, 3.935
    z_root = float(upper_z(s0))
    prof_top = [(s0, z_root + 0.004), (3.78, 1.262), (s1, 1.262)]
    prof_bot = [(s1 - 0.01, 1.222), (3.80, 1.215), (s0 + 0.06, z_root - 0.03)]
    loop = prof_top + prof_bot
    half = [(0.0, 0.49), (0.6, 0.485), (1.0, 0.455)]

    def hw(s):
        return float(np.interp((s - s0) / (s1 - s0), [h[0] for h in half], [h[1] for h in half]))

    rows = []
    for side in (-1, 1):
        rows.append([mesh.add_v((sx(ss), side * hw(ss), zz)) for ss, zz in loop])
    f0 = len(mesh.f)
    n = len(loop)
    for k in range(n):
        k2 = (k + 1) % n
        mesh.quad(rows[0][k], rows[0][k2], rows[1][k2], rows[1][k], PART_MIRROR)
    for row in rows:
        ci = mesh.add_v(np.mean([mesh.v[i] for i in row], axis=0))
        for k in range(n):
            mesh.add_f(row[k], row[(k + 1) % n], ci, PART_MIRROR)
    make_consistent(mesh, f0, len(mesh.f))


def build(with_features=True):
    mesh = Mesh()
    build_body(mesh)
    for xa in (X_FA, X_RA):   # wheel-well liners close the arch tunnels
        build_liner(mesh, xa)
    for xa, tr in ((X_FA, TRACK_F), (X_RA, TRACK_R)):
        for side in (1, -1):
            build_wheel(mesh, xa, side, tr)
    for side in (1, -1):
        build_mirror(mesh, side)
    build_fin(mesh)
    build_spoiler(mesh)
    if with_features:
        import features
        mesh.features = features.build(mesh)
    return mesh


if __name__ == '__main__':
    m = build()
    print(len(m.v), 'vertices', len(m.f), 'faces')
