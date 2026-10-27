#!/usr/bin/env python3
"""Writes the friends' expression sheets to assets/faces/<id>.png.

Every friend has the same twelve expressions as Lumi, in the same 4x3 order
(see tool/make_face_atlas.py), so moods, blinks, and the emotion pad work the
same for all of them. Each sheet is derived from Lumi's crisp expression
shapes and restyled:

    juju   Gummy Toy: big glossy candy eyes with highlights, a red mouth
    mochi  Soft Pebble: tiny dot eyes, a small mouth, blush on every frame
    nova   Orbit Guide: an LED pixel face (white, tinted cyan in the shader)

Run from the package root:  python3 tool/make_friend_faces.py
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_face_atlas as lumi  # noqa: E402  (also rewrites Lumi's own sheet)

S = 1024
CELL = 512
OUT = "assets/faces"

# Where Lumi's features sit, as (u0, v0, u1, v1) with v up, and their centers.
REGIONS = {
    "eyeL": ((0.24, 0.5, 0.5, 0.74), (0.38, 0.56)),
    "eyeR": ((0.5, 0.5, 0.76, 0.74), (0.62, 0.56)),
    "mouth": ((0.32, 0.3, 0.68, 0.5), (0.5, 0.43)),
}


def px(u, v):
    return int(round(u * S)), int(round((1 - v) * S))


def restyle_layout(mask, layout):
    """Moves and scales each feature of a crisp sprite: layout maps a region
    name to (scale, new_center)."""
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    for name, ((u0, v0, u1, v1), (cu, cv)) in REGIONS.items():
        scale, (nu, nv) = layout[name]
        x0, y0 = px(u0, v1)
        x1, y1 = px(u1, v0)
        part = mask.crop((x0, y0, x1, y1))
        w, h = part.size
        part = part.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
        # Keep the feature's center where the region's center maps to.
        cx, cy = px(nu + (((u0 + u1) / 2) - cu) * scale, nv + (((v0 + v1) / 2) - cv) * scale)
        out.alpha_composite(part, (cx - part.size[0] // 2, cy - part.size[1] // 2))
    return out


def region_mask(alpha, name):
    (u0, v0, u1, v1), _ = REGIONS[name]
    m = np.zeros_like(alpha, dtype=bool)
    x0, y0 = px(u0, v1)
    x1, y1 = px(u1, v0)
    m[y0:y1, x0:x1] = True
    return m & (alpha > 40)


def bbox(m):
    ys, xs = np.nonzero(m)
    if len(xs) == 0:
        return None
    return xs.min(), ys.min(), xs.max(), ys.max()


def painted(crisp, layout, ink, mouth_fill, tongue, shine, blush=None):
    """A colored face: dark eyes with highlights when open, a filled mouth
    when it is open, and optional blush."""
    shape = restyle_layout(crisp, layout)
    alpha = np.asarray(shape.split()[3])
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if blush:
        color, spots = blush
        for (u, v, w, h) in spots:
            x0, y0 = px(u - w / 2, v + h / 2)
            x1, y1 = px(u + w / 2, v - h / 2)
            d.ellipse([x0, y0, x1, y1], fill=color)
        img = img.filter(ImageFilter.GaussianBlur(10))

    layer = np.zeros((S, S, 4), dtype=np.uint8)

    def paint(m, rgba):
        layer[m] = rgba

    for name in ("eyeL", "eyeR"):
        m = region_mask(alpha, name)
        paint(m, ink)
        b = bbox(m)
        if b is None:
            continue
        x0, y0, x1, y1 = b
        w, h = x1 - x0, y1 - y0
        fill = m[y0:y1 + 1, x0:x1 + 1].mean()
        if fill > 0.55 and h > 0.07 * S:
            # An open eye: a big catch light up and to one side, a small one low.
            hl = Image.new("L", (S, S), 0)
            hd = ImageDraw.Draw(hl)
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            for (ox, oy, rw, rh) in shine:
                hd.ellipse([cx + ox * w - rw * w, cy + oy * h - rh * h, cx + ox * w + rw * w, cy + oy * h + rh * h], fill=255)
            hm = (np.asarray(hl) > 0) & m
            paint(hm, (255, 255, 255, 255))

    m = region_mask(alpha, "mouth")
    b = bbox(m)
    if b is not None:
        x0, y0, x1, y1 = b
        w, h = x1 - x0, y1 - y0
        fill = m[y0:y1 + 1, x0:x1 + 1].mean()
        if mouth_fill and fill > 0.45 and h > 0.035 * S:
            paint(m, mouth_fill)
            if tongue:
                tl = Image.new("L", (S, S), 0)
                ImageDraw.Draw(tl).ellipse([x0 + w * 0.22, y1 - h * 0.55, x1 - w * 0.22, y1 + h * 0.25], fill=255)
                paint((np.asarray(tl) > 0) & m, tongue)
        else:
            paint(m, ink)

    # Soft edges: keep the shape's own antialiasing.
    layer[..., 3] = np.minimum(layer[..., 3], alpha)
    img.alpha_composite(Image.fromarray(layer, "RGBA"))
    return img


def led(crisp, pitch=0.027, center=(0.5, 0.52)):
    """An LED matrix face: Lumi's shapes sampled on a grid of rounded dots."""
    a = crisp.split()[3].filter(ImageFilter.MaxFilter(9))
    alpha = np.asarray(a).astype(np.float32) / 255
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    step = pitch * S
    cx, cy = px(*center)
    n = int(0.5 / pitch) + 2
    for j in range(-n, n + 1):
        for i in range(-n, n + 1):
            x, y = cx + i * step, cy + j * step
            x0, y0, x1, y1 = int(x - step / 2), int(y - step / 2), int(x + step / 2), int(y + step / 2)
            if x0 < 0 or y0 < 0 or x1 >= S or y1 >= S:
                continue
            if alpha[y0:y1, x0:x1].mean() > 0.3:
                r = step * 0.39
                d.rounded_rectangle([x - r, y - r, x + r, y + r], radius=step * 0.12, fill=(255, 255, 255, 255))
    g = img.filter(ImageFilter.GaussianBlur(12))
    g.putalpha(g.split()[3].point(lambda x: min(255, int(x * 1.8))))
    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    base.alpha_composite(g)
    base.alpha_composite(img)
    return base


# ----------------------------------------------------------------- drawn faces
# Juju and Mochi are drawn from their design sheet, expression by expression,
# in the sheet's own coordinates; `xf` maps those onto the app's face cap.
class Pen:
    def __init__(self, xf=lambda u, v: (u, v), sx=1.0, sy=1.0):
        self.im = Image.new("RGBA", (S * 4, S * 4), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)
        self.xf, self.sx, self.sy = xf, sx, sy

    def P(self, u, v):
        u, v = self.xf(u, v)
        return (u * S * 4, (1 - v) * S * 4)

    def box(self, cu, cv, w, h):
        x0, y0 = self.P(cu - w / 2, cv + h / 2)
        x1, y1 = self.P(cu + w / 2, cv - h / 2)
        return [x0, y0, x1, y1]

    def w(self, t):
        return max(1, int(t * S * 4 * self.sx))

    def ellipse(self, cu, cv, w, h, fill):
        self.d.ellipse(self.box(cu, cv, w * self.sx, h * self.sy), fill=fill)

    def chord(self, cu, cv, w, h, a0, a1, fill):
        self.d.chord(self.box(cu, cv, w * self.sx, h * self.sy), a0, a1, fill=fill)

    def arc(self, cu, cv, w, h, a0, a1, width, fill):
        self.d.arc(self.box(cu, cv, w * self.sx, h * self.sy), a0, a1, fill=fill, width=self.w(width))

    def line(self, pts, width, fill):
        self.d.line([self.P(u, v) for u, v in pts], fill=fill, width=self.w(width), joint="curve")
        r = self.w(width) / 2
        for u, v in (pts[0], pts[-1]):
            x, y = self.P(u, v)
            self.d.ellipse([x - r, y - r, x + r, y + r], fill=fill)

    def done(self):
        return self.im.resize((S, S), Image.LANCZOS)


def spiral(pen, cu, cv, size, width, fill, turns=1.75, flip=1):
    pts = []
    for i in range(140):
        t = i / 139 * turns * math.tau
        r = size * (0.12 + 0.88 * i / 139)
        pts.append((cu + flip * r * math.cos(t), cv + r * math.sin(t)))
    pen.line(pts, width, fill)


def juju(name):
    """Big glossy candy eyes, a wide open grin with a tongue."""
    K, Wh, M, T = (28, 22, 30, 255), (255, 255, 255, 255), (120, 20, 40, 255), (255, 110, 130, 255)
    p = Pen()
    E = (0.39, 0.61)
    EV = 0.57

    def open_eye(cu, cv=EV, w=0.10, h=0.17, look=0.0):
        p.ellipse(cu, cv, w, h, K)
        p.ellipse(cu + 0.018 + look, cv + 0.04, 0.035, 0.045, Wh)
        p.ellipse(cu - 0.02 + look, cv - 0.035, 0.015, 0.02, Wh)

    def grin(w=0.17, h=0.15, cv=0.44):
        p.chord(0.5, cv, w, h, 0, 180, M)
        p.ellipse(0.5, cv - h * 0.36, w * 0.47, h * 0.33, T)

    def happy_eyes(width=0.03):
        for cu in E:
            p.arc(cu, 0.55, 0.11, 0.12, 200, 340, width, K)

    if name == "awake":
        for cu in E:
            open_eye(cu)
        grin()
    elif name == "blink":
        for cu in E:
            p.arc(cu, 0.585, 0.11, 0.08, 20, 160, 0.03, K)
        grin()
    elif name == "sleepy":
        for cu in E:
            p.arc(cu, 0.56, 0.11, 0.06, 20, 160, 0.026, K)
        p.ellipse(0.5, 0.43, 0.045, 0.04, M)
    elif name == "curious":
        open_eye(E[0] - 0.01, 0.575, 0.11, 0.185, look=-0.02)
        open_eye(E[1] - 0.01, 0.565, 0.09, 0.15, look=-0.02)
        p.ellipse(0.47, 0.43, 0.055, 0.06, M)
    elif name == "poked":
        for s, cu in ((-1, E[0]), (1, E[1])):
            p.line([(cu + s * 0.05, 0.62), (cu - s * 0.045, 0.57), (cu + s * 0.05, 0.52)], 0.03, K)
        p.ellipse(0.5, 0.425, 0.09, 0.08, M)
        p.ellipse(0.5, 0.405, 0.05, 0.03, T)
    elif name == "delighted":
        happy_eyes()
        grin(0.22, 0.22, 0.45)
    elif name == "dizzy":
        for s, cu in ((-1, E[0]), (1, E[1])):
            spiral(p, cu, EV, 0.06, 0.022, K, flip=s)
        p.line([(0.42 + 0.16 * i / 60, 0.43 + 0.016 * math.sin(i / 60 * 3 * math.tau)) for i in range(61)], 0.02, M)
    elif name == "surprised":
        for cu in E:
            open_eye(cu, EV + 0.01, 0.12, 0.2)
        p.ellipse(0.5, 0.415, 0.08, 0.095, M)
        p.ellipse(0.5, 0.39, 0.045, 0.035, T)
    elif name == "content":
        happy_eyes(0.024)
        p.arc(0.5, 0.455, 0.12, 0.08, 20, 160, 0.024, M)
    elif name == "glum":
        for s, cu in ((-1, E[0]), (1, E[1])):
            p.chord(cu, 0.55, 0.10, 0.13, 0, 180, K)
            p.ellipse(cu + 0.012, 0.535, 0.025, 0.025, Wh)
            p.line([(cu - s * 0.055, 0.635), (cu + s * 0.045, 0.61)], 0.016, K)
        p.arc(0.5, 0.405, 0.1, 0.06, 200, 340, 0.022, M)
    elif name == "grumpy":
        for s, cu in ((-1, E[0]), (1, E[1])):
            p.ellipse(cu, 0.55, 0.085, 0.11, K)
            p.ellipse(cu + 0.014, 0.57, 0.025, 0.03, Wh)
            p.line([(cu + s * 0.06, 0.65), (cu - s * 0.05, 0.615)], 0.026, K)
        p.line([(0.445 + 0.11 * i / 40, 0.43 + 0.01 * math.sin(i / 40 * 2 * math.tau)) for i in range(41)], 0.022, M)
    elif name == "wow":
        for cu in E:
            p.ellipse(cu, EV + 0.01, 0.12, 0.19, K)
            # Star-shaped catch lights.
            for (dx, dy, r) in ((0.02, 0.045, 0.028), (-0.022, -0.04, 0.012)):
                x, y = cu + dx, EV + 0.01 + dy
                pts = [(x + math.cos(a) * (r if k % 2 == 0 else r * 0.42), y + math.sin(a) * (r if k % 2 == 0 else r * 0.42))
                       for k, a in enumerate([math.pi / 2 + i * math.pi / 4 for i in range(8)])]
                p.d.polygon([p.P(u, v) for u, v in pts], fill=Wh)
        p.ellipse(0.5, 0.42, 0.06, 0.07, M)
    return p.done()


def mochi(name):
    """Tiny dot eyes with a glint, an ω mouth, and blush that never leaves."""
    K, Wh, B, M = (52, 40, 40, 255), (255, 255, 255, 255), (255, 120, 120, 140), (150, 50, 60, 255)
    # The design sheet's face sat on a bigger cap; spread it to match.
    p = Pen(xf=lambda u, v: (0.5 + (u - 0.5) * 1.05, 0.5 + (v - 0.5) * 1.15))
    E = (0.40, 0.60)
    EV = 0.54
    blush = Image.new("RGBA", (S * 4, S * 4), (0, 0, 0, 0))
    bd = ImageDraw.Draw(blush)
    strength = {"delighted": 190, "poked": 200, "content": 160, "wow": 170}.get(name, 120)
    for cu in (0.33, 0.67):
        bd.ellipse(p.box(cu, 0.465, 0.11, 0.06), fill=(255, 120, 120, strength))
    blush = blush.filter(ImageFilter.GaussianBlur(28))

    def dot(cu, cv=EV, w=0.045, h=0.058):
        p.ellipse(cu, cv, w, h, K)
        p.ellipse(cu + 0.009, cv + 0.012, w * 0.3, h * 0.26, Wh)

    def omega(cv=0.48, width=0.013):
        p.arc(0.475, cv, 0.05, 0.045, 10, 170, width, K)
        p.arc(0.525, cv, 0.05, 0.045, 10, 170, width, K)

    def lids(cv=EV, up=True, width=0.016):
        for cu in E:
            if up:
                p.arc(cu, cv - 0.01, 0.07, 0.06, 200, 340, width, K)
            else:
                p.arc(cu, cv, 0.065, 0.04, 20, 160, width, K)

    if name == "awake":
        for cu in E:
            dot(cu)
        omega()
    elif name == "blink":
        lids(up=False)
        omega()
    elif name == "sleepy":
        lids(EV - 0.005, up=False, width=0.014)
        p.ellipse(0.5, 0.475, 0.024, 0.02, K)
    elif name == "curious":
        dot(E[0] - 0.012, EV + 0.004, 0.05, 0.064)
        dot(E[1] - 0.012, EV - 0.002, 0.042, 0.054)
        p.ellipse(0.49, 0.475, 0.026, 0.03, K)
        p.ellipse(0.49, 0.475, 0.012, 0.016, (0, 0, 0, 0))
    elif name == "poked":
        for s, cu in ((-1, E[0]), (1, E[1])):
            p.line([(cu + s * 0.025, EV + 0.025), (cu - s * 0.022, EV), (cu + s * 0.025, EV - 0.025)], 0.014, K)
        p.ellipse(0.5, 0.473, 0.035, 0.04, M)
    elif name == "delighted":
        lids()
        p.chord(0.5, 0.485, 0.075, 0.075, 0, 180, M)
    elif name == "dizzy":
        for s, cu in ((-1, E[0]), (1, E[1])):
            spiral(p, cu, EV, 0.03, 0.011, K, flip=s)
        p.line([(0.46 + 0.08 * i / 40, 0.475 + 0.008 * math.sin(i / 40 * 3 * math.tau)) for i in range(41)], 0.011, K)
    elif name == "surprised":
        for cu in E:
            dot(cu, EV + 0.005, 0.055, 0.072)
        p.ellipse(0.5, 0.468, 0.034, 0.04, M)
    elif name == "content":
        lids(width=0.014)
        omega(0.482)
    elif name == "glum":
        for s, cu in ((-1, E[0]), (1, E[1])):
            p.chord(cu, EV - 0.005, 0.048, 0.05, 0, 180, K)
            p.line([(cu - s * 0.03, EV + 0.04), (cu + s * 0.025, EV + 0.028)], 0.01, K)
        p.arc(0.5, 0.462, 0.05, 0.032, 200, 340, 0.012, K)
    elif name == "grumpy":
        for s, cu in ((-1, E[0]), (1, E[1])):
            dot(cu, EV - 0.006, 0.042, 0.05)
            p.line([(cu + s * 0.035, EV + 0.05), (cu - s * 0.03, EV + 0.03)], 0.013, K)
        p.line([(0.47, 0.475), (0.53, 0.475)], 0.012, K)
    elif name == "wow":
        for cu in E:
            dot(cu, EV + 0.004, 0.058, 0.074)
            p.ellipse(cu - 0.012, EV - 0.016, 0.012, 0.012, Wh)
        p.ellipse(0.5, 0.47, 0.03, 0.036, M)
    face = p.done()
    out = blush.resize((S, S), Image.LANCZOS)
    out.alpha_composite(face)
    return out


STYLES = {
    "juju": juju,
    "mochi": mochi,
    "nova": lambda name: led(lumi.CRISP[name]),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for fid, style in STYLES.items():
        atlas = Image.new("RGBA", (CELL * 4, CELL * 3), (0, 0, 0, 0))
        for i, name in enumerate(lumi.ORDER):
            cell = style(name).resize((CELL, CELL), Image.LANCZOS)
            atlas.alpha_composite(cell, ((i % 4) * CELL, (i // 4) * CELL))
        atlas.save(f"{OUT}/{fid}.png", optimize=True)
        print(f"wrote {OUT}/{fid}.png")


if __name__ == "__main__":
    main()
