"""Write the outline model the app loads: assets/models/aqua_outline.json."""
import json, sys
import numpy as np
import aqua

def export(path):
    m = aqua.build()
    V = np.round(np.array(m.v), 3)
    F = np.array(m.f)
    P = np.array(m.part)
    # drop unreferenced vertices (centroid helpers etc. are all referenced, but be safe)
    used = np.unique(F)
    remap = -np.ones(len(V), int)
    remap[used] = np.arange(len(used))
    V = V[used]
    F = remap[F]
    # Convex hull of everything but the roof antenna. A bounding box only ever
    # touches hull vertices, so the app predicts the detector's box from these
    # few hundred points instead of projecting the whole mesh.
    from scipy.spatial import ConvexHull
    keep = np.array([i for i in range(len(V)) if used[i] not in m.fin])
    hull = sorted(int(keep[i]) for i in ConvexHull(V[keep]).vertices)
    lines = []
    for pts, nrm, name in m.features:
        lines.append({
            'name': name,
            'p': [round(float(c), 3) for c in np.asarray(pts).ravel()],
            'n': [round(float(c), 2) for c in np.asarray(nrm).ravel()],
        })
    doc = {
        'name': 'Toyota AQUA (NHP10, 2017 facelift)',
        'units': 'm',
        'axes': 'x forward, y left, z up; ground at z = 0; origin mid-length',
        'dimensions': {'length': aqua.L, 'width': aqua.W, 'height': aqua.H, 'wheelbase': aqua.WB,
                       'front_overhang': aqua.F_OH, 'rear_overhang': aqua.R_OH,
                       'track_front': aqua.TRACK_F, 'track_rear': aqua.TRACK_R},
        'parts': {'body': 0, 'wheel': 1, 'trim': 2, 'well': 3},
        'vertices': [float(c) for c in V.ravel()],
        'faces': [int(c) for c in F.ravel()],
        'face_parts': [int(c) for c in P],
        'hull': hull,
        'lines': lines,
    }
    s = json.dumps(doc, separators=(',', ':'))
    open(path, 'w').write(s)
    print(path, len(V), 'vertices', len(F), 'faces', len(hull), 'hull', len(lines), 'lines', f'{len(s)/1024:.0f} KB')

if __name__ == '__main__':
    import os
    default = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets', 'models', 'aqua_outline.json')
    export(sys.argv[1] if len(sys.argv) > 1 else os.path.normpath(default))
