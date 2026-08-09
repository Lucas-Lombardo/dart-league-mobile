#!/usr/bin/env python3
"""Offline replay of a DebugFrameDumpService session through both TFLite models.

Usage:
    python3 run_models.py <run_dir> [--models-dir ../../assets/models]

<run_dir> is a device dump: f<seq>.jpg frames + frames.jsonl (what the app
actually saw/decided, one line per analyzed frame).

For every frame, runs BOTH models:
  - dartboard-v7_float16.tflite  (the app's model — e2e head [1,300,6])
  - dart-rival-ia-heavy.tflite   (anchor head [1,13,21504] + NMS)
with the exact preprocessing/parsing/scoring ports of the app's pipeline
(dart_detection_service._preprocessDirect, detection_parsing.dart,
dart_scoring_service.dart).

Outputs <run_dir>/offline_results.jsonl (one line per frame: both models'
control points, tips, scores, inference ms) and prints a comparison summary.
"""

import argparse
import json
import math
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

try:
    from ai_edge_litert.interpreter import Interpreter
except ImportError:  # fall back to TF's bundled interpreter
    from tensorflow.lite.python.interpreter import Interpreter

CONF_THRESHOLD = 0.8
IOU_TIP = 0.958
IOU_P = 0.85
DART_NMS_MIN_DIST = 0.004
MAX_DARTS = 3
LABELS = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8', 'tip']
INPUT_SIZE = 1024

# ---------------------------------------------------------------------------
# Preprocess — port of _preprocessDirect: uniform scale to fit 1024, anchored
# top-left, black padding, nearest-neighbor, /255.
# ---------------------------------------------------------------------------

def preprocess(rgb: np.ndarray):
    h, w = rgb.shape[:2]
    scale = min(INPUT_SIZE / w, INPUT_SIZE / h)
    new_w, new_h = round(w * scale), round(h * scale)
    if w >= h:
        x_scale, y_scale = 1.0, w / h
    else:
        x_scale, y_scale = h / w, 1.0

    xs = np.clip((np.arange(new_w) * (w / new_w)).astype(np.int32), 0, w - 1)
    ys = np.clip((np.arange(new_h) * (h / new_h)).astype(np.int32), 0, h - 1)
    resized = rgb[ys][:, xs]

    canvas = np.zeros((INPUT_SIZE, INPUT_SIZE, 3), dtype=np.float32)
    canvas[:new_h, :new_w] = resized.astype(np.float32) / 255.0
    return canvas[None], x_scale, y_scale

# ---------------------------------------------------------------------------
# Output parsing — port of detection_parsing.dart
# ---------------------------------------------------------------------------

def parse_e2e(out: np.ndarray, x_scale, y_scale):
    """[1,300,6] rows of [x1,y1,x2,y2,conf,cls] in 1024-canvas pixels."""
    dets = []
    for row in out[0]:
        conf = float(row[4])
        if conf <= CONF_THRESHOLD:
            continue
        cls = int(round(float(row[5])))
        if cls < 0 or cls >= len(LABELS):
            continue
        cx = (float(row[0]) + float(row[2])) / 2.0 / INPUT_SIZE * x_scale
        cy = (float(row[1]) + float(row[3])) / 2.0 / INPUT_SIZE * y_scale
        w = abs(float(row[2]) - float(row[0])) / INPUT_SIZE * x_scale
        h = abs(float(row[3]) - float(row[1])) / INPUT_SIZE * y_scale
        if cx - w / 2 > 1.0 or cy - h / 2 > 1.0 or cx + w / 2 < 0.0 or cy + h / 2 < 0.0:
            continue
        dets.append(dict(cls=cls, x=min(max(cx, 0.0), 1.5), y=min(max(cy, 0.0), 1.5),
                         w=w, h=h, conf=conf))
    return dets


def parse_anchor(out: np.ndarray, x_scale, y_scale):
    """[1,13,21504]: rows 0-3 = cx,cy,w,h (normalized), 4-12 = class confs."""
    o = out[0]  # (13, N)
    confs = o[4:]  # (9, N)
    best_cls = confs.argmax(axis=0)
    best_conf = confs.max(axis=0)
    idx = np.nonzero(best_conf > CONF_THRESHOLD)[0]
    dets = []
    for i in idx:
        cx = float(o[0, i]) * x_scale
        cy = float(o[1, i]) * y_scale
        w = float(o[2, i]) * x_scale
        h = float(o[3, i]) * y_scale
        if cx - w / 2 > 1.0 or cy - h / 2 > 1.0 or cx + w / 2 < 0.0 or cy + h / 2 < 0.0:
            continue
        dets.append(dict(cls=int(best_cls[i]), x=min(max(cx, 0.0), 1.5),
                         y=min(max(cy, 0.0), 1.5), w=w, h=h, conf=float(best_conf[i])))
    return class_specific_nms(dets)


def iou(a, b):
    al, ar = a['x'] - a['w'] / 2, a['x'] + a['w'] / 2
    at, ab = a['y'] - a['h'] / 2, a['y'] + a['h'] / 2
    bl, br = b['x'] - b['w'] / 2, b['x'] + b['w'] / 2
    bt, bb = b['y'] - b['h'] / 2, b['y'] + b['h'] / 2
    il, ir = max(al, bl), min(ar, br)
    it, ib = max(at, bt), min(ab, bb)
    if il >= ir or it >= ib:
        return 0.0
    inter = (ir - il) * (ib - it)
    union = a['w'] * a['h'] + b['w'] * b['h'] - inter
    return inter / union if union > 0 else 0.0


def class_specific_nms(dets):
    result = []
    for cls in set(d['cls'] for d in dets):
        thr = IOU_TIP if LABELS[cls] == 'tip' else IOU_P
        group = sorted((d for d in dets if d['cls'] == cls),
                       key=lambda d: -d['conf'])
        kept = []
        for d in group:
            if not any(iou(d, k) > thr for k in kept):
                kept.append(d)
        result.extend(kept)
    return result

# ---------------------------------------------------------------------------
# Control-point selection + dart filter — port of dart_detection_service.dart
# ---------------------------------------------------------------------------

def extract_4cps(cps):
    quadrants = {}
    for cp in cps:
        quadrants.setdefault(cp['cls'] // 2, []).append(cp)
    selected = [max(g, key=lambda c: c['conf'])
                for q, g in sorted(quadrants.items())]
    if len(selected) == 4:
        return selected
    if len(cps) >= 4:
        best_by_class = {}
        for cp in sorted(cps, key=lambda c: -c['conf']):
            best_by_class.setdefault(cp['cls'], cp)
        if len(best_by_class) >= 4:
            return list(best_by_class.values())[:4]
    return selected


def filter_darts(tips):
    kept = []
    for d in sorted(tips, key=lambda t: -t['conf']):
        suppressed = False
        for k in kept:
            dist = math.hypot(d['x'] - k['x'], d['y'] - k['y'])
            if iou(d, k) > IOU_TIP or dist < DART_NMS_MIN_DIST:
                suppressed = True
                break
        if not suppressed:
            kept.append(d)
        if len(kept) >= MAX_DARTS:
            break
    return kept

# ---------------------------------------------------------------------------
# Scoring — port of dart_scoring_service.dart (DLT homography + dvBoard rings)
# ---------------------------------------------------------------------------

C = 170.0
INNER_BULL = 6.9 / 170.0
OUTER_BULL = 16.85 / 170.0
TRIPLE_MID = 101.9 / 170.0
DT_HALF = 10.0 / 340.0
ZONE2_LO = (170.0 - 5.0) / 170.0 - DT_HALF
ZONE3_HI = DT_HALF + TRIPLE_MID
ZONE3_LO = TRIPLE_MID - DT_HALF

ZONE_RADIANS = {
    10: (0.15707964, 0.47123891), 15: (0.47123891, 0.78539819),
    2: (0.78539819, 1.09955747), 17: (1.09955747, 1.41371674),
    3: (1.41371674, 1.72787602), 19: (1.72787602, 2.04203530),
    7: (2.04203530, 2.35619450), 16: (2.35619450, 2.67035380),
    8: (2.67035380, 2.98451310), 11: (2.98451310, 3.29867240),
    14: (3.29867240, 3.61283160), 9: (3.61283160, 3.92699090),
    12: (3.92699090, 4.24115040), 5: (4.24115040, 4.55530930),
    20: (4.55530930, 4.86946870), 1: (4.86946870, 5.18362800),
    18: (5.18362800, 5.49778750), 4: (5.49778750, 5.81194640),
    13: (5.81194640, 6.12610600), 6: (6.12610600, 6.44026470),
}

_S25, _C25 = math.sin(0.7853981633974483), math.cos(0.7853981633974483)
_S35, _C35 = math.sin(1.0995574287564276), math.cos(1.0995574287564276)
FLAG_DEST = {
    1: (C + _S25 * C, C - _C25 * C), 2: (C + _S35 * C, C - _C35 * C),
    3: (C + _S35 * C, C + _C35 * C), 4: (C + _S25 * C, C + _C25 * C),
    5: (C - _S25 * C, C + _C25 * C), 6: (C - _S35 * C, C + _C35 * C),
    7: (C - _S35 * C, C - _C35 * C), 8: (C - _S25 * C, C - _C25 * C),
}


def homography(cps):
    """cps: 4 dicts with x, y, cls (flag = cls+1). Hartley-normalized DLT."""
    src = np.array([[c['x'], c['y']] for c in cps])
    dst = np.array([FLAG_DEST[c['cls'] + 1] for c in cps])

    def normalize(pts):
        centroid = pts.mean(axis=0)
        avg = np.linalg.norm(pts - centroid, axis=1).mean()
        s = math.sqrt(2) / (avg if avg else 1)
        t = np.array([[s, 0, -s * centroid[0]], [0, s, -s * centroid[1]], [0, 0, 1]])
        return (pts - centroid) * s, t

    ns, ts = normalize(src)
    nd, td = normalize(dst)
    a = np.zeros((8, 8))
    b = np.zeros(8)
    for i in range(4):
        sx, sy = ns[i]
        dx, dy = nd[i]
        a[i * 2] = [sx, sy, 1, 0, 0, 0, -dx * sx, -dx * sy]
        b[i * 2] = dx
        a[i * 2 + 1] = [0, 0, 0, sx, sy, 1, -dy * sx, -dy * sy]
        b[i * 2 + 1] = dy
    hv = np.linalg.solve(a, b)
    hn = np.array([[hv[0], hv[1], hv[2]], [hv[3], hv[4], hv[5]], [hv[6], hv[7], 1.0]])
    return np.linalg.inv(td) @ hn @ ts


def score_tip(h, x, y):
    v = h @ np.array([x, y, 1.0])
    bx, by = v[0] / v[2], v[1] / v[2]
    nx, ny = bx / C, by / C
    dist = math.hypot(nx - 1.0, ny - 1.0)
    angle = math.atan2(ny - 1.0, nx - 1.0)
    while angle < 0:
        angle += 2 * math.pi
    if angle < 0.15707964:
        angle += 2 * math.pi
    elif angle > 6.44026470:
        angle -= 2 * math.pi

    if dist <= INNER_BULL:
        return 'DBull (50)', 50
    if dist <= OUTER_BULL:
        return 'SBull (25)', 25
    if dist > 1.0:
        return 'Miss (0)', 0

    segment = 20
    for seg, (lo, hi) in ZONE_RADIANS.items():
        if lo <= angle < hi:
            segment = seg
    if ZONE2_LO < dist <= 1.0:
        return f'D{segment} ({segment * 2})', segment * 2
    if ZONE3_LO < dist <= ZONE3_HI:
        return f'T{segment} ({segment * 3})', segment * 3
    return f'S{segment} ({segment})', segment

# ---------------------------------------------------------------------------
# Model runner
# ---------------------------------------------------------------------------

class Model:
    def __init__(self, path: Path):
        self.name = path.stem
        self.interp = Interpreter(model_path=str(path), num_threads=8)
        self.interp.allocate_tensors()
        self.inp = self.interp.get_input_details()[0]
        self.out = self.interp.get_output_details()[0]
        self.e2e = self.out['shape'][-1] == 6

    def run(self, canvas, x_scale, y_scale):
        t0 = time.perf_counter()
        self.interp.set_tensor(self.inp['index'], canvas)
        self.interp.invoke()
        out = self.interp.get_tensor(self.out['index'])
        ms = int((time.perf_counter() - t0) * 1000)
        dets = (parse_e2e if self.e2e else parse_anchor)(out, x_scale, y_scale)
        cps = extract_4cps([d for d in dets if d['cls'] < 8])
        tips = filter_darts([d for d in dets if d['cls'] == 8])
        scores = []
        if len(cps) >= 4:
            try:
                h = homography(cps[:4])
                scores = [score_tip(h, t['x'], t['y'])[0] for t in tips]
            except np.linalg.LinAlgError:
                pass
        return dict(
            ms=ms,
            cp=len(cps),
            cps=[dict(cls=LABELS[c['cls']], x=round(c['x'], 4),
                      y=round(c['y'], 4), conf=round(c['conf'], 3))
                 for c in cps],
            tips=[dict(x=round(t['x'], 4), y=round(t['y'], 4),
                       conf=round(t['conf'], 3),
                       score=scores[i] if i < len(scores) else None)
                  for i, t in enumerate(tips)],
        )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('run_dir', type=Path)
    ap.add_argument('--models-dir', type=Path,
                    default=Path(__file__).resolve().parents[2] / 'assets/models')
    args = ap.parse_args()

    frames = sorted(args.run_dir.glob('f*.jpg'))
    if not frames:
        sys.exit(f'no f*.jpg frames in {args.run_dir}')

    v7 = Model(args.models_dir / 'dartboard-v7_float16.tflite')
    heavy = Model(args.models_dir / 'dart-rival-ia-heavy.tflite')
    print(f'{len(frames)} frames | v7 e2e={v7.e2e} heavy e2e={heavy.e2e}')

    out_path = args.run_dir / 'offline_results.jsonl'
    with out_path.open('w') as out:
        for n, fp in enumerate(frames):
            rgb = np.asarray(Image.open(fp).convert('RGB'))
            canvas, xs, ys = preprocess(rgb)
            rec = dict(seq=int(fp.stem[1:]),
                       v7=v7.run(canvas, xs, ys),
                       heavy=heavy.run(canvas, xs, ys))
            out.write(json.dumps(rec) + '\n')
            if n % 25 == 0:
                print(f'  {n}/{len(frames)} '
                      f'(v7 {rec["v7"]["ms"]}ms, heavy {rec["heavy"]["ms"]}ms)')

    print(f'wrote {out_path}')

    # ---- quick summary ----
    recs = [json.loads(l) for l in out_path.open()]
    for name in ('v7', 'heavy'):
        r = [x[name] for x in recs]
        with_board = sum(1 for x in r if x['cp'] >= 4)
        tip_counts = [len(x['tips']) for x in r]
        print(f'{name:6s}: board 4CP {with_board}/{len(r)} | '
              f'frames with 1+ tip {sum(1 for t in tip_counts if t)} | '
              f'total tips {sum(tip_counts)} | '
              f'mean infer {np.mean([x["ms"] for x in r]):.0f}ms')
    diff = [x['seq'] for x in recs
            if len(x['v7']['tips']) != len(x['heavy']['tips'])]
    print(f'tip-count differs on {len(diff)} frames: {diff[:30]}')


if __name__ == '__main__':
    main()
