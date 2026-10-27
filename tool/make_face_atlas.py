#!/usr/bin/env python3
"""Writes assets/face_atlas.png, the Lantern Spirit expression sheet.

A 4x3 grid of 512px cells. Each cell is the face sprite as it maps onto the
head's face cap (the canvas spans FACE_K head radii either side of center):

    0 sleepy    1 awake   2 curious   3 poked
    4 delighted 5 dizzy   6 blink     7 surprised
    8 content   9 glum   10 grumpy   11 wow

Run from the package root:  python3 tool/make_face_atlas.py
"""
import math
from PIL import Image, ImageDraw, ImageFilter

FRAMES = {}
CRISP = {}  # each expression before the glow, for tool/make_friend_faces.py
S, SS = 1024, 4
W = (255, 250, 232, 255)


def canvas():
    return Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))


def P(u, v):
    return (u * S * SS, (1 - v) * S * SS)


def box(cu, cv, w, h):
    x0, y0 = P(cu - w / 2, cv + h / 2)
    x1, y1 = P(cu + w / 2, cv - h / 2)
    return [x0, y0, x1, y1]


def lw(t):
    return int(t * S * SS)


def poly(d, pts, width):
    d.line([P(u, v) for u, v in pts], fill=W, width=lw(width), joint="curve")
    r = lw(width) / 2
    for u, v in (pts[0], pts[-1]):
        x, y = P(u, v)
        d.ellipse([x - r, y - r, x + r, y + r], fill=W)


def save(img, name):
    img = img.resize((S, S), Image.LANCZOS)
    CRISP[name] = img
    g = img.filter(ImageFilter.GaussianBlur(16))
    g.putalpha(g.split()[3].point(lambda x: min(255, int(x * 1.7))))
    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    base.alpha_composite(g)
    base.alpha_composite(img)
    FRAMES[name] = base


EY, EX = 0.56, 0.12  # eye height, half spacing

# awake: soft tall eyes + small smile
im = canvas(); d = ImageDraw.Draw(im)
for s in (-1, 1):
    d.ellipse(box(0.5 + s * EX, EY, 0.085, 0.15), fill=W)
d.arc(box(0.5, 0.43, 0.10, 0.07), 20, 160, fill=W, width=lw(0.018))
save(im, "awake")

# sleepy: closed lid curves + tiny relaxed mouth
im = canvas(); d = ImageDraw.Draw(im)
for s in (-1, 1):
    d.arc(box(0.5 + s * EX, EY - 0.01, 0.11, 0.06), 15, 165, fill=W, width=lw(0.02))
d.ellipse(box(0.5, 0.43, 0.035, 0.028), fill=W)
save(im, "sleepy")

# curious: eyes glance to the viewer's left, one a touch bigger, little "o"
im = canvas(); d = ImageDraw.Draw(im)
d.ellipse(box(0.5 - EX - 0.035, EY + 0.005, 0.095, 0.165), fill=W)
d.ellipse(box(0.5 + EX - 0.035, EY - 0.005, 0.08, 0.14), fill=W)
d.ellipse(box(0.47, 0.43, 0.045, 0.05), outline=W, width=lw(0.016))
save(im, "curious")

# poked: squeezed > < eyes + wobbly open mouth
im = canvas(); d = ImageDraw.Draw(im)
for s in (-1, 1):
    cu = 0.5 + s * EX
    poly(d, [(cu + s * 0.045, EY + 0.045), (cu - s * 0.045, EY), (cu + s * 0.045, EY - 0.045)], 0.022)
d.ellipse(box(0.5, 0.425, 0.07, 0.06), fill=W)
save(im, "poked")

# delighted: happy upturned arcs + open smile
im = canvas(); d = ImageDraw.Draw(im)
for s in (-1, 1):
    d.arc(box(0.5 + s * EX, EY - 0.025, 0.12, 0.11), 200, 340, fill=W, width=lw(0.026))
d.chord(box(0.5, 0.45, 0.14, 0.12), 0, 180, fill=W)
save(im, "delighted")

# dizzy: spiral eyes + wavy mouth
im = canvas(); d = ImageDraw.Draw(im)
for s in (-1, 1):
    cu, pts = 0.5 + s * EX, []
    for i in range(140):
        t = i / 139 * 1.75 * math.tau
        r = 0.008 + 0.058 * i / 139
        pts.append((cu + s * r * math.cos(t), EY + r * math.sin(t)))
    poly(d, pts, 0.024)
pts = [(0.44 + 0.12 * i / 60, 0.43 + 0.014 * math.sin(i / 60 * 3 * math.tau)) for i in range(61)]
poly(d, pts, 0.016)
save(im, "dizzy")


# blink: awake mouth with closed lids
im = canvas(); d = ImageDraw.Draw(im)
for s in (-1, 1):
    d.arc(box(0.5 + s * EX, EY + 0.005, 0.10, 0.05), 15, 165, fill=W, width=lw(0.022))
d.arc(box(0.5, 0.43, 0.10, 0.07), 20, 160, fill=W, width=lw(0.018))
save(im, "blink")

# surprised: big round eyes, round open mouth
im = canvas(); d = ImageDraw.Draw(im)
for s in (-1, 1):
    d.ellipse(box(0.5 + s * EX, EY + 0.01, 0.11, 0.17), fill=W)
d.ellipse(box(0.5, 0.42, 0.06, 0.075), fill=W)
save(im, "surprised")

# ---- expressions for the emotion pad and the fireworks
# content: soft closed happy eyes, small smile
im = canvas(); d = ImageDraw.Draw(im)
for s in (-1, 1):
    d.arc(box(0.5 + s * EX, EY - 0.02, 0.10, 0.07), 205, 335, fill=W, width=lw(0.02))
d.arc(box(0.5, 0.445, 0.08, 0.05), 20, 160, fill=W, width=lw(0.016))
save(im, "content")

# glum: droopy half eyes, small frown
im = canvas(); d = ImageDraw.Draw(im)
for s in (-1, 1):
    cu = 0.5 + s * EX
    d.chord(box(cu, EY - 0.015, 0.085, 0.11), 0, 180, fill=W)
    poly(d, [(cu - s * 0.05, EY + 0.055), (cu + s * 0.045, EY + 0.035)], 0.014)
d.arc(box(0.5, 0.405, 0.08, 0.05), 200, 340, fill=W, width=lw(0.016))
save(im, "glum")

# grumpy: angled brows over flat eyes, wobbly mouth
im = canvas(); d = ImageDraw.Draw(im)
for s in (-1, 1):
    cu = 0.5 + s * EX
    d.ellipse(box(cu, EY - 0.01, 0.075, 0.09), fill=W)
    poly(d, [(cu + s * 0.05, EY + 0.075), (cu - s * 0.045, EY + 0.045)], 0.02)
pts = [(0.455 + 0.09 * i / 40, 0.43 + 0.008 * math.sin(i / 40 * 2 * math.tau)) for i in range(41)]
poly(d, pts, 0.016)
save(im, "grumpy")

# wow: big shining eyes with highlights, small open mouth
im = canvas(); d = ImageDraw.Draw(im)
for s in (-1, 1):
    cu = 0.5 + s * EX
    d.ellipse(box(cu, EY + 0.01, 0.11, 0.175), fill=W)
    d.ellipse(box(cu + 0.022, EY + 0.05, 0.03, 0.04), fill=(120, 160, 255, 255))
d.ellipse(box(0.5, 0.415, 0.05, 0.06), fill=W)
save(im, "wow")

ORDER = ["sleepy", "awake", "curious", "poked", "delighted", "dizzy", "blink", "surprised",
         "content", "glum", "grumpy", "wow"]
CELL = 512
atlas = Image.new("RGBA", (CELL * 4, CELL * 3), (0, 0, 0, 0))
for i, name in enumerate(ORDER):
    atlas.alpha_composite(FRAMES[name].resize((CELL, CELL), Image.LANCZOS), ((i % 4) * CELL, (i // 4) * CELL))
atlas.save("assets/face_atlas.png", optimize=True)
print("wrote assets/face_atlas.png")
