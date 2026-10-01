"""Solve a photo's camera from what the model knows exactly -- the wheels.

Parameters: eye (x, y, z), yaw, pitch, roll, focal length.  Observations are
hub centres, the image extremes of each rim ellipse, and tyre contact points.
"""
import math, json, os, sys
import numpy as np
from scipy.optimize import least_squares
import aqua
from render import Camera

HERE = os.path.dirname(os.path.abspath(__file__))
RIM = 0.195


def cam_from(p, size):
    ex, ey, ez, yaw, pitch, roll, f = p
    eye = np.array([ex, ey, ez])
    fwd = np.array([math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), math.sin(pitch)])
    return Camera(eye, eye + fwd, f, size, roll=roll)


def wheel(which):
    """(hub centre, axle direction) for 'RF', 'RR', 'LF', 'LR' (R = car's right, -y)."""
    x = aqua.X_FA if which[1] == 'F' else aqua.X_RA
    tr = aqua.TRACK_F if which[1] == 'F' else aqua.TRACK_R
    side = -1 if which[0] == 'R' else 1
    face = side * (tr / 2 + aqua.TIRE_W / 2 - 0.03)
    return np.array([x, face, aqua.HUB_Z]), side


def rim_pts(which, r=RIM, n=72):
    c, side = wheel(which)
    t = np.linspace(0, 2 * math.pi, n, endpoint=False)
    return c + np.stack([r * np.cos(t), np.zeros(n), r * np.sin(t)], axis=1)


def residuals(p, obs, size):
    cam = cam_from(p, size)
    res = []
    for kind, which, target in obs:
        if kind == 'hub':
            uv, _ = cam.project(wheel(which)[0])
            res += list(uv - target)
        elif kind == 'rim':
            uv, _ = cam.project(rim_pts(which))
            l, r = uv[:, 0].min(), uv[:, 0].max()
            t, b = uv[:, 1].min(), uv[:, 1].max()
            res += [l - target[0], r - target[1], t - target[2], b - target[3]]
        elif kind == 'contact':
            c, side = wheel(which)
            c = c.copy(); c[1] -= side * 0.06; c[2] = 0.0
            uv, _ = cam.project(c)
            res += list((uv - target) * 0.5)
    return np.array(res)


def solve(obs, size, p0):
    r = least_squares(residuals, p0, args=(obs, size), x_scale=[1, 1, 1, 0.1, 0.1, 0.1, 500])
    print('rms px', math.sqrt(np.mean(r.fun ** 2)))
    return r.x


SIDE_PHOTO = dict(
    path='refs/2017-2021_Toyota_Aqua_rear.jpg',
    obs=[('hub', 'RF', (1643, 671)), ('rim', 'RF', (1575, 1712, 581, 763)),
         ('hub', 'RR', (699, 693)), ('rim', 'RR', (614, 780, 594, 794)),
         ('contact', 'LR', (352, 768))],
    # rear-right, a long way back
    p0=[-9.0, -14.0, 1.2, math.atan2(14.0, 9.0), -0.03, 0.0, 3000],
)


FRONT_PHOTO = dict(
    path='refs/2017-2021_Toyota_Aqua.jpg',
    obs=[('hub', 'RF', (1045, 745)), ('rim', 'RF', (977, 1122, 642, 850)),
         ('hub', 'RR', (243, 715)), ('rim', 'RR', (183, 302, 622, 808)),
         ('contact', 'LF', (1590, 845))],
    p0=[7.0, -10.0, 1.2, math.atan2(10.0, -7.0), -0.03, 0.0, 3000],
)


def solve_named(name):
    from PIL import Image
    ph = {'side': SIDE_PHOTO, 'front': FRONT_PHOTO}[name]
    size = Image.open(os.path.join(HERE, ph['path'])).size
    p = solve(ph['obs'], size, np.array(ph['p0'], float))
    cam = cam_from(p, size)
    az = math.degrees(math.atan2(cam.eye[1], cam.eye[0]))
    print(name, f'eye {np.round(cam.eye, 2)} dist {np.linalg.norm(cam.eye[:2]):.2f} az {az:.1f} f {p[6]:.0f}')
    json.dump(p.tolist(), open(os.path.join(HERE, f'{name}_cam.json'), 'w'))
    return p


if __name__ == '__main__':
    for n in sys.argv[1:] or ['side', 'front']:
        solve_named(n)
