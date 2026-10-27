#!/usr/bin/env python3
"""Writes assets/lantern.glb: the Lantern Spirit rig and its state clips.

The character is a set of separate spheres plus a face cap (a thin shell in
front of the head that carries the expression sprite). Every part hangs off two nodes:

    <Part>Ctrl   keyed by the clips (the "timeline" layer)
    <Part>Fx     left at identity in the file, driven from Dart at runtime
                 (look-at, squash springs, follow-through, explode)

so authored animation and interactive motion never fight over one transform.

Clips: Awake, Sleepy, Curious, Dizzy, Watch, Lean, and the emotion-pad corners
(Happy, Content, Glum, Grumpy) loop; Poked, Delighted, Flinch, and Cheer play
once and end on a rest pose.

Run from the package root:  python3 tool/make_lantern_glb.py
"""

import json
import math
import struct

import numpy as np

OUT = "assets/lantern.glb"
FPS = 30
HEAD_R = 0.62
FACE_K = 1.3  # face sprite canvas half-width, in head radii

REST = {
    "Head": (0.0, 1.8, 0.0),
    "Body": (0.0, 1.02, 0.0),
    "HandL": (-0.66, 1.12, 0.08),
    "HandR": (0.68, 1.18, 0.12),
    "Wisp": (0.0, 0.6, -0.02),
}
RADIUS = {"Head": HEAD_R, "Body": 0.30, "HandL": 0.10, "HandR": 0.10, "Wisp": 0.13}
SKIN_PARTS = ("Head", "Body")
PARTS = ("Head", "Body", "HandL", "HandR", "Wisp")


# ----------------------------------------------------------------- math
def quat_euler(pitch=0.0, yaw=0.0, roll=0.0):
    """Quaternion (x, y, z, w) for yaw about Y, then pitch about X, then roll about Z."""
    def axis(ax, a):
        s = math.sin(a / 2)
        return np.array([ax[0] * s, ax[1] * s, ax[2] * s, math.cos(a / 2)])

    def mul(a, b):
        ax, ay, az, aw = a
        bx, by, bz, bw = b
        return np.array([
            aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz,
        ])

    q = mul(mul(axis((0, 1, 0), yaw), axis((1, 0, 0), pitch)), axis((0, 0, 1), roll))
    return q / np.linalg.norm(q)


def ease(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def pose(t=None, r=None, s=None):
    return (t, r if r is not None else quat_euler(), s if s is not None else (1.0, 1.0, 1.0))


# ----------------------------------------------------------------- states
def awake(t, P=3.2):
    w = math.tau * t / P
    b = 0.012 * math.sin(2 * w)
    return {
        "Head": pose(add(REST["Head"], (0, 0.04 * math.sin(w), 0)),
                     quat_euler(0.03 * math.sin(w + 1.0), 0.0, 0.035 * math.sin(w + 0.6)),
                     (1 + b, 1 - b, 1 + b)),
        "Body": pose(add(REST["Body"], (0, 0.03 * math.sin(w - 0.7), 0))),
        "HandL": pose(add(REST["HandL"], (0, 0.05 * math.sin(w + 1.8), 0.02 * math.sin(w + 0.5)))),
        "HandR": pose(add(REST["HandR"], (0, 0.05 * math.sin(w + 3.1), 0.02 * math.sin(w + 2.0)))),
        "Wisp": pose(add(REST["Wisp"], (0.035 * math.sin(2 * w), 0.03 * math.sin(w - 1.4), 0)),
                     None, (1.0, 1 + 0.12 * math.sin(2 * w + 0.3), 1.0)),
    }


def sleepy(t, P=4.0):
    w = math.tau * t / P
    br = 0.02 * math.sin(w)
    return {
        "Head": pose((0, 1.66 + 0.02 * math.sin(w), 0), quat_euler(0.16 + 0.03 * math.sin(w)),
                     (1.05 + br, 0.93 - br, 1.05 + br)),
        "Body": pose((0, 0.98 + 0.015 * math.sin(w - 0.8), 0)),
        "HandL": pose((-0.5, 0.96 + 0.02 * math.sin(w + 1.0), 0.12)),
        "HandR": pose((0.5, 0.94 + 0.02 * math.sin(w + 2.0), 0.12)),
        "Wisp": pose((0.015 * math.sin(2 * w), 0.56 + 0.015 * math.sin(w), -0.02)),
    }


def curious(t, P=2.4):
    w = math.tau * t / P
    return {
        "Head": pose((-0.03, 1.8 + 0.025 * math.sin(w), 0.02),
                     quat_euler(-0.07, -0.38 + 0.04 * math.sin(w), 0.17 + 0.03 * math.sin(w + 1.0))),
        "Body": pose((0, 1.02 + 0.02 * math.sin(w - 0.6), 0)),
        "HandL": pose((-0.7, 1.08 + 0.04 * math.sin(w + 1.0), 0.05)),
        "HandR": pose((0.36, 1.48 + 0.02 * math.sin(2 * w), 0.46)),
        "Wisp": pose((0.03 * math.sin(2 * w), 0.6 + 0.02 * math.sin(w), -0.02)),
    }


def dizzy(t, P=1.6):
    w = math.tau * t / P
    return {
        "Head": pose((-0.05 + 0.05 * math.sin(w), 1.76 + 0.02 * math.sin(2 * w), 0.03 * math.cos(w)),
                     quat_euler(0.06 * math.sin(w + 1.0), 0.1 * math.sin(w), 0.12 + 0.16 * math.cos(w))),
        "Body": pose((0.03 * math.sin(w - 0.6), 1.02, 0)),
        "HandL": pose((-0.72 + 0.06 * math.cos(w + 1), 1.32 + 0.06 * math.sin(w + 1), 0.05)),
        "HandR": pose((0.55 + 0.05 * math.cos(w + 2), 0.92 + 0.05 * math.sin(w + 2), 0.1)),
        "Wisp": pose((0.05 * math.sin(w - 1.2), 0.6, -0.02)),
    }


def poked(t, D=0.7):
    u = t / D
    s = math.exp(-6 * u) * math.sin(12 * u) if u < 1 else 0.0
    base = awake(0.0)
    hT, _, _ = base["Head"]
    return {
        "Head": pose(add(hT, (0.18 * s, -0.08 * s, 0)), quat_euler(0, 0, -0.25 * s),
                     (1 + 0.16 * s, 1 - 0.17 * s, 1 + 0.16 * s)),
        "Body": pose(add(base["Body"][0], (0.06 * s, -0.04 * s, 0))),
        "HandL": pose(add(base["HandL"][0], (-0.3 * s, 0.4 * s, 0))),
        "HandR": pose(add(base["HandR"][0], (0.25 * s, 0.4 * s, 0))),
        "Wisp": pose(add(base["Wisp"][0], (0.05 * s, 0, 0)), None, base["Wisp"][2]),
    }


# Delighted: anticipation squat, jump with stretch, wiggle at the top, land.
# (time, head dy, head sx, head sy, roll, hands dy, hands spread)
DELIGHT_KEYS = [
    (0.00, 0.00, 1.00, 1.00, 0.00, 0.00, 0.00),
    (0.16, -0.10, 1.08, 0.90, 0.00, -0.06, 0.00),
    (0.42, 0.34, 0.95, 1.07, 0.00, 0.95, 0.00),
    (0.62, 0.30, 1.00, 1.00, 0.12, 0.90, -0.05),
    (0.80, 0.30, 1.00, 1.00, -0.12, 0.95, 0.05),
    (0.98, 0.05, 1.00, 1.00, 0.00, 0.20, 0.00),
    (1.10, -0.06, 1.06, 0.93, 0.00, 0.00, 0.00),
    (1.30, 0.00, 1.00, 1.00, 0.00, 0.00, 0.00),
]


def delighted(t):
    k = DELIGHT_KEYS
    for i in range(len(k) - 1):
        if k[i][0] <= t <= k[i + 1][0]:
            a, b = k[i], k[i + 1]
            e = ease((t - a[0]) / (b[0] - a[0]))
            v = [a[j] + (b[j] - a[j]) * e for j in range(1, 7)]
            break
    else:
        v = list(k[-1][1:])
    dy, sx, sy, roll, hdy, spread = v
    base = awake(0.0)
    return {
        "Head": pose(add(base["Head"][0], (0, dy, 0)), quat_euler(0, 0, roll), (sx, sy, sx)),
        "Body": pose(add(base["Body"][0], (0, dy * 0.78, 0))),
        "HandL": pose(add(base["HandL"][0], (-spread, hdy, 0))),
        "HandR": pose(add(base["HandR"][0], (spread, hdy * 1.04, 0))),
        "Wisp": pose(add(base["Wisp"][0], (0, dy * 0.62, 0)), None, base["Wisp"][2]),
    }


def watch(t, P=4.0):
    """Sitting at the rail, looking up at the sky."""
    w = math.tau * t / P
    br = 0.012 * math.sin(w)
    return {
        "Head": pose((0, 1.76 + 0.015 * math.sin(w), 0), quat_euler(-0.3 + 0.03 * math.sin(w + 0.7)),
                     (1 + br, 1 - br, 1 + br)),
        "Body": pose((0, 1.0 + 0.01 * math.sin(w - 0.6), 0)),
        "HandL": pose((-0.32, 1.02 + 0.015 * math.sin(w + 1), 0.34)),
        "HandR": pose((0.32, 1.04 + 0.015 * math.sin(w + 2), 0.34)),
        "Wisp": pose((0.02 * math.sin(2 * w), 0.58 + 0.015 * math.sin(w), -0.02)),
    }


def flinch(t, D=0.55):
    """A startle on a bright flash: a quick squash and a jump of the hands."""
    u = t / D
    s = math.exp(-7 * u) * math.sin(11 * u) if u < 1 else 0.0
    base = watch(0.0)
    return {
        "Head": pose(add(base["Head"][0], (0, -0.07 * s, -0.04 * s)), quat_euler(-0.3 + 0.12 * s),
                     (1 + 0.1 * s, 1 - 0.12 * s, 1 + 0.1 * s)),
        "Body": pose(add(base["Body"][0], (0, -0.03 * s, 0))),
        "HandL": pose(add(base["HandL"][0], (-0.2 * s, 0.22 * s, 0))),
        "HandR": pose(add(base["HandR"][0], (0.2 * s, 0.22 * s, 0))),
        "Wisp": pose(base["Wisp"][0]),
    }


# Cheer: a celebration jump with the hands waving overhead.
CHEER_KEYS = [
    (0.00, 0.00, 1.00, 1.00, 0.00, 0.00, 0.00),
    (0.14, -0.08, 1.07, 0.92, 0.00, -0.05, 0.00),
    (0.38, 0.3, 0.96, 1.06, 0.00, 1.0, 0.0),
    (0.58, 0.26, 1.00, 1.00, 0.14, 0.95, -0.12),
    (0.78, 0.28, 1.00, 1.00, -0.14, 1.0, 0.12),
    (0.98, 0.26, 1.00, 1.00, 0.12, 0.95, -0.12),
    (1.16, 0.04, 1.00, 1.00, 0.00, 0.3, 0.00),
    (1.28, -0.05, 1.05, 0.94, 0.00, 0.0, 0.00),
    (1.45, 0.00, 1.00, 1.00, 0.00, 0.00, 0.00),
]


def keyed(keys, t, base):
    for i in range(len(keys) - 1):
        if keys[i][0] <= t <= keys[i + 1][0]:
            a, b = keys[i], keys[i + 1]
            e = ease((t - a[0]) / (b[0] - a[0]))
            v = [a[j] + (b[j] - a[j]) * e for j in range(1, 7)]
            break
    else:
        v = list(keys[-1][1:])
    dy, sx, sy, roll, hdy, spread = v
    return {
        "Head": pose(add(base["Head"][0], (0, dy, 0)), quat_euler(0, 0, roll), (sx, sy, sx)),
        "Body": pose(add(base["Body"][0], (0, dy * 0.78, 0))),
        "HandL": pose(add(base["HandL"][0], (-spread, hdy, 0))),
        "HandR": pose(add(base["HandR"][0], (spread, hdy * 1.04, 0))),
        "Wisp": pose(add(base["Wisp"][0], (0, dy * 0.62, 0)), None, base["Wisp"][2]),
    }


def cheer(t):
    return keyed(CHEER_KEYS, t, awake(0.0))


def lean(t, P=4.4):
    """Content after the show, leaning on the rail."""
    w = math.tau * t / P
    br = 0.01 * math.sin(w)
    return {
        "Head": pose((0.05, 1.72 + 0.012 * math.sin(w), 0.02), quat_euler(-0.12, 0.0, 0.18 + 0.02 * math.sin(w)),
                     (1 + br, 1 - br, 1 + br)),
        "Body": pose((0.02, 0.98, 0)),
        "HandL": pose((-0.44, 0.94 + 0.01 * math.sin(w + 1), 0.22)),
        "HandR": pose((0.42, 0.96 + 0.01 * math.sin(w + 2), 0.22)),
        "Wisp": pose((0.015 * math.sin(2 * w), 0.57, -0.02)),
    }


def happy(t, P=1.6):
    """The high-energy, good-mood corner of the emotion pad: a bouncy loop."""
    w = math.tau * t / P
    bounce = abs(math.sin(w)) * 0.1
    sq = 0.04 * math.cos(2 * w)
    return {
        "Head": pose((0, 1.86 + bounce, 0), quat_euler(-0.06, 0, 0.1 * math.sin(w)), (1 + sq, 1 - sq, 1 + sq)),
        "Body": pose((0, 1.06 + bounce * 0.8, 0)),
        "HandL": pose((-0.64, 1.55 + 0.12 * math.sin(w * 2 + 0.5), 0.06)),
        "HandR": pose((0.66, 1.58 + 0.12 * math.sin(w * 2 + 2.0), 0.06)),
        "Wisp": pose((0.03 * math.sin(2 * w), 0.66 + bounce * 0.6, -0.02)),
    }


def content(t, P=4.4):
    w = math.tau * t / P
    br = 0.012 * math.sin(w)
    return {
        "Head": pose((0, 1.78 + 0.02 * math.sin(w), 0), quat_euler(0.04, 0, 0.17 + 0.02 * math.sin(w)),
                     (1 + br, 1 - br, 1 + br)),
        "Body": pose((0, 1.0 + 0.015 * math.sin(w - 0.6), 0)),
        "HandL": pose((-0.24, 1.08 + 0.01 * math.sin(w + 1), 0.4)),
        "HandR": pose((0.24, 1.1 + 0.01 * math.sin(w + 2), 0.4)),
        "Wisp": pose((0.02 * math.sin(2 * w), 0.58 + 0.015 * math.sin(w), -0.02)),
    }


def glum(t, P=5.0):
    w = math.tau * t / P
    return {
        "Head": pose((0, 1.7 + 0.01 * math.sin(w), 0), quat_euler(0.17 + 0.02 * math.sin(w))),
        "Body": pose((0, 0.98, 0)),
        "HandL": pose((-0.5, 0.86 + 0.01 * math.sin(w + 1), 0)),
        "HandR": pose((0.5, 0.86 + 0.01 * math.sin(w + 2), 0)),
        "Wisp": pose((0.01 * math.sin(2 * w), 0.58, -0.02)),
    }


def grumpy(t, P=2.0):
    w = math.tau * t / P
    return {
        "Head": pose((0, 1.8, 0), quat_euler(0.02, 0, 0.04 * math.sin(2 * w)), (1.06, 1.06, 1.06)),
        "Body": pose((0, 1.02, 0)),
        "HandL": pose((-0.38, 1.0 + 0.01 * math.sin(w), -0.08)),
        "HandR": pose((0.38, 1.0 + 0.01 * math.sin(w + 1), -0.08)),
        "Wisp": pose((0.03 * math.sin(4 * w), 0.6, -0.02)),
    }


CLIPS = [
    ("Awake", awake, 3.2),
    ("Sleepy", sleepy, 4.0),
    ("Curious", curious, 2.4),
    ("Dizzy", dizzy, 1.6),
    ("Poked", poked, 0.7),
    ("Delighted", delighted, 1.3),
    ("Watch", watch, 4.0),
    ("Flinch", flinch, 0.55),
    ("Cheer", cheer, 1.45),
    ("Lean", lean, 4.4),
    ("Happy", happy, 1.6),
    ("Content", content, 4.4),
    ("Glum", glum, 5.0),
    ("Grumpy", grumpy, 2.0),
]


# ----------------------------------------------------------------- geometry
def uv_sphere(seg=48, rings=24):
    pos, uv, idx = [], [], []
    for r in range(rings + 1):
        v = r / rings
        phi = v * math.pi
        for s in range(seg + 1):
            u = s / seg
            th = u * math.tau
            x, y, z = math.sin(phi) * math.sin(th), math.cos(phi), math.sin(phi) * math.cos(th)
            pos.append((x, y, z))
            uv.append((u, v))
    for r in range(rings):
        for s in range(seg):
            a = r * (seg + 1) + s
            b = a + seg + 1
            # counter-clockwise seen from outside
            idx += [a, b, a + 1, a + 1, b, b + 1]
    p = np.array(pos, np.float32)
    return p, p.copy(), np.array(uv, np.float32), np.array(idx, np.uint16)


def face_cap(cap_deg=70.0, seg=64, rings=24):
    """A spherical cap around +Z just outside the head, UV-mapped by projection from the front."""
    R = HEAD_R * 1.012
    cmax = math.radians(cap_deg)
    pos, nrm, uv, idx = [], [], [], []
    for r in range(rings + 1):
        a = cmax * r / rings  # angle away from +Z
        for s in range(seg + 1):
            th = math.tau * s / seg
            d = (math.sin(a) * math.cos(th), math.sin(a) * math.sin(th), math.cos(a))
            pos.append(tuple(R * c for c in d))
            nrm.append(d)
            uv.append((d[0] * R / (2 * FACE_K * HEAD_R) + 0.5, 0.5 - d[1] * R / (2 * FACE_K * HEAD_R)))
    for r in range(rings):
        for s in range(seg):
            a = r * (seg + 1) + s
            b = a + seg + 1
            idx += [a, b, a + 1, a + 1, b, b + 1]
    return (np.array(pos, np.float32), np.array(nrm, np.float32), np.array(uv, np.float32),
            np.array(idx, np.uint16))


# ----------------------------------------------------------------- glTF writer
class Builder:
    def __init__(self):
        self.bin = bytearray()
        self.g = {"asset": {"version": "2.0", "generator": "lantern_spirit/make_lantern_glb.py"},
                  "buffers": [], "bufferViews": [], "accessors": [], "meshes": [], "materials": [],
                  "nodes": [], "scenes": [{"nodes": []}], "scene": 0, "animations": []}

    def view(self, data, target=None):
        while len(self.bin) % 4:
            self.bin += b"\0"
        off = len(self.bin)
        self.bin += data
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        self.g["bufferViews"].append(v)
        return len(self.g["bufferViews"]) - 1

    def accessor(self, arr, kind, target=None, minmax=False):
        comp = {np.float32: 5126, np.uint16: 5123}[arr.dtype.type]
        bv = self.view(arr.tobytes(), target)
        a = {"bufferView": bv, "componentType": comp, "count": int(arr.shape[0]), "type": kind}
        if minmax:
            flat = arr.reshape(arr.shape[0], -1)
            a["min"] = [float(x) for x in flat.min(0)]
            a["max"] = [float(x) for x in flat.max(0)]
        self.g["accessors"].append(a)
        return len(self.g["accessors"]) - 1

    def material(self, name, color, emissive=(0, 0, 0)):
        self.g["materials"].append({"name": name, "pbrMetallicRoughness": {
            "baseColorFactor": list(color), "metallicFactor": 0.0, "roughnessFactor": 0.4},
            "emissiveFactor": list(emissive)})
        return len(self.g["materials"]) - 1

    def mesh(self, name, prim_arrays, material):
        p, n, uv, idx = prim_arrays
        attrs = {"POSITION": self.accessor(p, "VEC3", 34962, minmax=True),
                 "NORMAL": self.accessor(n, "VEC3", 34962),
                 "TEXCOORD_0": self.accessor(uv, "VEC2", 34962)}
        prim = {"attributes": attrs, "indices": self.accessor(idx, "SCALAR", 34963), "material": material}
        self.g["meshes"].append({"name": name, "primitives": [prim]})
        return len(self.g["meshes"]) - 1

    def node(self, name, children=(), mesh=None, t=None, s=None):
        n = {"name": name}
        if children:
            n["children"] = list(children)
        if mesh is not None:
            n["mesh"] = mesh
        if t is not None:
            n["translation"] = list(t)
        if s is not None:
            n["scale"] = list(s)
        self.g["nodes"].append(n)
        return len(self.g["nodes"]) - 1

    def write(self, path):
        while len(self.bin) % 4:
            self.bin += b"\0"
        self.g["buffers"] = [{"byteLength": len(self.bin)}]
        js = json.dumps(self.g, separators=(",", ":")).encode()
        while len(js) % 4:
            js += b" "
        total = 12 + 8 + len(js) + 8 + len(self.bin)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A))
            f.write(js)
            f.write(struct.pack("<II", len(self.bin), 0x004E4942))
            f.write(self.bin)


def main():
    b = Builder()
    skin = b.material("Skin", (0.45, 0.78, 1.0, 1.0))
    ember = b.material("Ember", (1.0, 0.6, 0.25, 1.0), (1.0, 0.55, 0.18))
    face = b.material("Face", (1.0, 1.0, 1.0, 1.0))
    sphere = uv_sphere()
    skin_mesh = b.mesh("SkinSphere", sphere, skin)
    ember_mesh = b.mesh("EmberSphere", sphere, ember)
    face_mesh = b.mesh("FaceCap", face_cap(), face)

    ctrl = {}
    for part in PARTS:
        r = RADIUS[part]
        geo = b.node(part, mesh=skin_mesh if part in SKIN_PARTS else ember_mesh, s=(r, r, r))
        kids = [geo]
        if part == "Head":
            kids.append(b.node("Face", mesh=face_mesh))
        if part == "Body":
            # Socket for neck accessories (the scarf), at the top of the body.
            kids.append(b.node("NeckFx", t=(0.0, 0.26, 0.0)))
        fx = b.node(part + "Fx", children=kids)
        ctrl[part] = b.node(part + "Ctrl", children=[fx], t=REST[part])
    root = b.node("Lantern", children=[ctrl[p] for p in PARTS])
    b.g["scenes"][0]["nodes"] = [root]

    for name, fn, dur in CLIPS:
        n = int(round(dur * FPS)) + 1
        times = np.array([dur * i / (n - 1) for i in range(n)], np.float32)
        frames = [fn(float(tt)) for tt in times]
        samplers, channels = [], []
        tin = b.accessor(times, "SCALAR", minmax=True)
        for part in PARTS:
            for path, k, kind in (("translation", 0, "VEC3"), ("rotation", 1, "VEC4"), ("scale", 2, "VEC3")):
                vals = np.array([np.asarray(f[part][k], np.float64) for f in frames], np.float32)
                samplers.append({"input": tin, "output": b.accessor(vals, kind), "interpolation": "LINEAR"})
                channels.append({"sampler": len(samplers) - 1, "target": {"node": ctrl[part], "path": path}})
        b.g["animations"].append({"name": name, "samplers": samplers, "channels": channels})

    b.write(OUT)
    print(f"wrote {OUT}: {len(b.bin)} bytes of buffer, {len(CLIPS)} clips")


if __name__ == "__main__":
    main()
