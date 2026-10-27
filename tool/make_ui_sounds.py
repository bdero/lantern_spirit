#!/usr/bin/env python3
"""Synthesizes Lantern Spirit's UI, character, and game sounds into assets/sfx.

A sibling of tool/make_sounds.py (the fireworks show sounds). Everything here
is built from oscillators, additive voices, and filtered noise, so the sounds
carry no third-party rights and are fully reproducible (every sound gets its
own fixed random seed).

One palette for the whole app: music-box bells, kalimba and marimba plucks,
soft felt thumps, rubbery boings, airy whooshes, and wordless formant-shaped
coos for the characters. Pitched material sits in C major pentatonic
(C D E G A) so overlapping sounds always harmonize.

Output: 44.1 kHz, 16-bit, mono WAV. Run from anywhere:

    python3 tool/make_ui_sounds.py              # render every sound
    python3 tool/make_ui_sounds.py tap poke     # render only these
    python3 tool/make_ui_sounds.py --list       # list sound names
    python3 tool/make_ui_sounds.py --verify     # check every wav in assets/sfx
"""

import math
import os
import sys
import wave
import zlib

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sfx")

# Written by tool/make_sounds.py. Never overwrite these from here.
PROTECTED = {
    "ambience", "boom_big", "boom_small", "coin", "crackle", "launch",
    "pop", "puff", "sparkle", "squish", "whistle", "whoosh",
}

rng = np.random.default_rng(0)  # reseeded per sound in render()


# ---------------------------------------------------------------------------
# Basics
# ---------------------------------------------------------------------------

_SEMI = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}


def hz(name):
    """Note name like 'C6' or 'A5' to Hz (A4 = 440)."""
    return 440.0 * 2.0 ** ((_SEMI[name[0]] + 12 * (int(name[1:]) - 4)) / 12.0)


def ns(seconds):
    return int(round(SR * seconds))


def T(seconds):
    return np.arange(ns(seconds)) / SR


def buf(seconds):
    return np.zeros(ns(seconds))


def place(dst, src, at, gain=1.0):
    """Mixes src into dst starting at time `at` (seconds)."""
    i = ns(at)
    if i >= len(dst):
        return dst
    src = np.array(src, dtype=np.float64)
    k = min(ns(0.003), len(src) // 4)
    if k > 1:  # always land a placed layer softly, so short layers never click off
        src[-k:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(k) / (k - 1))
    m = min(len(src), len(dst) - i)
    dst[i:i + m] += gain * src[:m]
    return dst


def norm(x):
    m = np.max(np.abs(x))
    return x / m if m > 0 else x


def noise(n):
    return rng.standard_normal(n)


def phase(f):
    """Running phase for a (possibly per-sample) frequency in Hz."""
    return 2.0 * np.pi * np.cumsum(np.asarray(f, dtype=np.float64)) / SR


def ramp_in(t, a):
    """Raised-cosine attack over `a` seconds."""
    return 0.5 - 0.5 * np.cos(np.pi * np.clip(t / max(a, 1e-5), 0.0, 1.0))


def env_ad(t, a, d):
    """Click-free attack then exponential decay (time constant d)."""
    return ramp_in(t, a) * np.exp(-np.maximum(0.0, t - a) / d)


def gate(t, a, r, total=None):
    """Raised-cosine fade in over a, fade out over the last r seconds."""
    total = t[-1] if total is None else total
    out = 0.5 + 0.5 * np.cos(np.pi * np.clip((t - (total - r)) / max(r, 1e-5), 0.0, 1.0))
    return ramp_in(t, a) * out


def swell(t, peak, end, rise=2.0):
    """Rises as a power curve to `peak`, then cosine-falls to zero at `end`."""
    up = np.clip(t / peak, 0.0, 1.0) ** rise
    down = 0.5 + 0.5 * np.cos(np.pi * np.clip((t - peak) / max(end - peak, 1e-5), 0.0, 1.0))
    return up * down


def glide(t, f0, f1, dur, shape=1.0):
    """Exponential (musical) pitch glide from f0 to f1 over dur seconds."""
    return f0 * (f1 / f0) ** (np.clip(t / dur, 0.0, 1.0) ** shape)


def approach(t, f0, f1, tau):
    """Starts at f0 and settles exponentially onto f1."""
    return f1 + (f0 - f1) * np.exp(-t / tau)


def curve(t, pts, log=False):
    """Piecewise-linear (or log-linear, for pitch) curve through (time, value) points."""
    xs = [p[0] for p in pts]
    vs = np.array([p[1] for p in pts], dtype=np.float64)
    if log:
        return np.exp(np.interp(t, xs, np.log(vs)))
    return np.interp(t, xs, vs)


def vibrato(t, rate, depth, delay=0.0):
    """Multiplier for pitch: 1 +/- depth, fading in after `delay`."""
    fade = np.clip((t - delay) / 0.08, 0.0, 1.0) if delay > 0 else 1.0
    return 1.0 + depth * fade * np.sin(2.0 * np.pi * rate * t)


# ---------------------------------------------------------------------------
# Filters
# ---------------------------------------------------------------------------

def _sos(kind, fc, order=2):
    return signal.butter(order, fc, kind, fs=SR, output="sos")


def lp(x, fc, order=2):
    return signal.sosfilt(_sos("lowpass", min(fc, SR * 0.45), order), x)


def hp(x, fc, order=2):
    return signal.sosfilt(_sos("highpass", fc, order), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("bandpass", [lo, min(hi, SR * 0.45)], order), x)


def svf(x, fc, q=0.707, mode="band"):
    """Topology-preserving state-variable filter with per-sample cutoff.

    Stable under fast modulation, which the swept whooshes and the formant
    breath need. Band output is normalized to unity gain at the center.
    """
    n = len(x)
    fc = np.clip(np.broadcast_to(np.asarray(fc, dtype=np.float64), (n,)), 10.0, SR * 0.45)
    g = np.tan(np.pi * fc / SR)
    k = 1.0 / q
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    xs = np.asarray(x, dtype=np.float64).tolist()
    A1, A2, A3 = a1.tolist(), a2.tolist(), a3.tolist()
    low = [0.0] * n
    band = [0.0] * n
    s1 = s2 = 0.0
    for i in range(n):
        v3 = xs[i] - s2
        v1 = A1[i] * s1 + A2[i] * v3
        v2 = s2 + A2[i] * s1 + A3[i] * v3
        s1 = 2.0 * v1 - s1
        s2 = 2.0 * v2 - s2
        low[i] = v2
        band[i] = v1
    low = np.array(low)
    band = np.array(band)
    if mode == "low":
        return low
    if mode == "band":
        return band * k
    return np.asarray(x) - k * band - low


def sweep_noise(seconds, fc, q=1.0):
    """Band-passed noise with a moving center (Hz scalar or per-sample array)."""
    return norm(svf(noise(ns(seconds)), fc, q, "band"))


# ---------------------------------------------------------------------------
# A small shared "room" so every sound sits in the same cozy space
# ---------------------------------------------------------------------------

def _make_ir():
    r = np.random.default_rng(1234)
    t = T(0.45)
    ir = r.standard_normal(len(t)) * np.exp(-t / 0.10)
    ir = hp(lp(ir, 3600), 250)
    pre = ns(0.006)
    ir[:pre] *= np.linspace(0.0, 1.0, pre)
    return ir / np.sqrt(np.sum(ir ** 2))


IR = _make_ir()


def room(x, wet):
    if wet <= 0:
        return x
    return x + wet * signal.fftconvolve(x, IR)[:len(x)]


# ---------------------------------------------------------------------------
# Instruments
# ---------------------------------------------------------------------------

def bell(f, length, decay=0.4, bright=0.5, attack=0.0015, shimmer=0.0):
    """Music-box / glass bell. bright=0 leaves only harmonic partials."""
    t = T(length)
    x = np.zeros_like(t)
    parts = (
        (1.0, 1.0, 1.0),
        (2.0, 0.30, 0.6),
        (3.0, 0.03 + 0.07 * bright, 0.35),
        (4.2, 0.08 * bright, 0.2),
        (5.43, 0.05 * bright, 0.12),
    )
    for ratio, amp, dmul in parts:
        fr = f * ratio
        if amp <= 0 or fr > 15000:
            continue
        x += amp * np.sin(2 * np.pi * fr * t) * np.exp(-t / (decay * dmul))
    if shimmer:
        x += shimmer * np.sin(2 * np.pi * f * 1.0023 * t) * np.exp(-t / decay)
    return x * ramp_in(t, attack)


def kalimba(f, length, decay=0.35):
    """Soft plucked tine: round fundamental plus a brief high 'tink'."""
    t = T(length)
    x = np.sin(2 * np.pi * f * t) * np.exp(-t / decay)
    x += 0.12 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t / (decay * 0.3))
    if 5.9 * f < 15000:
        x += 0.18 * np.sin(2 * np.pi * 5.9 * f * t) * np.exp(-t / 0.012)
    x += 0.15 * norm(lp(noise(len(t)), 1000)) * env_ad(t, 0.0003, 0.004)
    return x * ramp_in(t, 0.001)


def marimba(f, length, decay=0.25):
    """Felt-mallet wooden bar."""
    t = T(length)
    x = np.zeros_like(t)
    for ratio, amp, dmul in ((1.0, 1.0, 1.0), (3.98, 0.25, 0.18), (9.9, 0.05, 0.06)):
        if f * ratio < 9000:  # keep the felt mallet round, never glassy
            x += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / (decay * dmul))
    x += 0.2 * norm(lp(noise(len(t)), 1800)) * env_ad(t, 0.0005, 0.003)
    return x * ramp_in(t, 0.001)


def felt(length, fc=600, decay=0.02, body=(160, 90), body_amp=0.6):
    """Soft felt thump: low-passed noise plus a dropping sine body."""
    t = T(length)
    x = norm(lp(noise(len(t)), fc)) * env_ad(t, 0.001, decay)
    if body:
        f = approach(t, body[0], body[1], 0.02)
        x += body_amp * np.sin(phase(f)) * env_ad(t, 0.001, decay * 1.6)
    return x


def bloop(f0, f1, length, sweep=0.015, decay=0.03, h2=0.15):
    """Rounded sine blip whose pitch settles from f0 to f1 (pops, drops, hops)."""
    t = T(length)
    ph = phase(approach(t, f0, f1, sweep))
    return (np.sin(ph) + h2 * np.sin(2 * ph)) * env_ad(t, 0.001, decay)


def drop(f, length=0.1, decay=0.025):
    """Water droplet: a quick upward 'plip'."""
    return bloop(f, f * 1.8, length, sweep=0.012, decay=decay, h2=0.05)


def pad(freqs, length, attack, release, detune=0.003, harmonics=4, tilt=1.8):
    """Warm sustained chord with a gentle chorus."""
    t = T(length)
    x = np.zeros_like(t)
    for f in freqs:
        for k in range(1, harmonics + 1):
            a = k ** -tilt
            x += a * 0.5 * (np.sin(2 * np.pi * f * k * t) + np.sin(2 * np.pi * f * k * (1 + detune) * t + k))
    return x * gate(t, attack, release)


def grain_cloud(length, count, t0, t1, band=(1500, 5000), decay=(0.001, 0.004), amp=None, skew=1.0):
    """Clusters of tiny noise grains: crunch, crinkle, rain, crackle."""
    n = ns(length)
    out = np.zeros(n)
    edges = np.geomspace(band[0], band[1], 4)
    bank = [norm(bp(noise(n), edges[i], edges[i + 1])) for i in range(3)]
    times = t0 + (t1 - t0) * rng.random(count) ** skew
    for tm in times:
        i = ns(tm)
        dec = rng.uniform(*decay)
        L = min(ns(dec * 6), n - i)
        if L <= 4:
            continue
        seg = bank[rng.integers(3)][i:i + L]
        w = np.exp(-np.arange(L) / (dec * SR))
        a0 = min(8, L)
        w[:a0] *= np.linspace(0.0, 1.0, a0)
        a = rng.uniform(0.3, 1.0) * (amp(tm) if amp else 1.0)
        out[i:i + L] += a * seg * w
    return out


def creak(length, rate0, rate1, fc0, fc1, q=5.0):
    """Stick-slip friction creak (rubber, taffy, elastic), soft and resonant."""
    t = T(length)
    n = len(t)
    rate = glide(t, rate0, rate1, length) * (1 + 0.08 * noise(n).clip(-2, 2))
    cyc = np.cumsum(rate) / SR
    pulses = (np.diff(np.floor(cyc), prepend=0.0) > 0).astype(float)
    imp = pulses * rng.uniform(0.6, 1.0, n)
    fc = glide(t, fc0, fc1, length)
    y = svf(imp, fc, q) + 0.35 * svf(imp, fc * 2.3, q)
    return lp(y, 2500, order=4)


# ---------------------------------------------------------------------------
# Character voices: wordless formant-shaped coos
# ---------------------------------------------------------------------------

# (F1, gain), (F2, gain), (F3, gain) for small-creature vowels.
VOWELS = {
    "oo": ((330, 1.0), (850, 0.35), (2600, 0.08)),
    "oh": ((500, 1.0), (950, 0.5), (2600, 0.1)),
    "ah": ((800, 1.0), (1300, 0.7), (2700, 0.15)),
    "eh": ((580, 1.0), (1900, 0.55), (2700, 0.15)),
    "ee": ((320, 1.0), (2500, 0.5), (3300, 0.25)),
    "ih": ((420, 1.0), (2100, 0.5), (3000, 0.18)),
    "mm": ((260, 1.0), (900, 0.06), (2500, 0.02)),
}
BW = (90.0, 140.0, 220.0)


def vowel_track(t, keys):
    times = [k[0] for k in keys]
    F = np.array([np.interp(t, times, [VOWELS[k[1]][i][0] for k in keys]) for i in range(3)])
    G = np.array([np.interp(t, times, [VOWELS[k[1]][i][1] for k in keys]) for i in range(3)])
    return F, G


def voice(f0, keys=None, F=None, G=None, breath=0.03, size=1.25, tilt=1.1, top=7000.0):
    """Additive voiced coo.

    f0 is a per-sample pitch track. The vowel either comes from keyframes
    [(time, 'oo'), ...] or from explicit formant tracks F, G (3 x n).
    Each harmonic is weighted by the formant envelope at its frequency, so
    pitch glides stay smooth and the result reads as a cute wordless coo.
    """
    f0 = np.asarray(f0, dtype=np.float64)
    n = len(f0)
    t = np.arange(n) / SR
    if keys is not None:
        F, G = vowel_track(t, keys)
    F = F * size
    ph = phase(f0)
    x = np.zeros(n)
    kmax = int(top / max(np.min(f0), 60.0)) + 1
    for k in range(1, min(kmax, 60) + 1):
        fk = k * f0
        a = 0.4 + sum(G[i] / (1.0 + ((fk - F[i]) / (BW[i] * size)) ** 2) for i in range(3))
        a *= k ** -tilt
        a *= np.clip((top - fk) / 1500.0, 0.0, 1.0)
        x += a * np.sin(k * ph)
    x = norm(x)
    if breath > 0:
        b = svf(noise(n), F[1], 1.2)
        x += breath * 0.3 * b / (np.std(b) + 1e-9)
    return x


# ---------------------------------------------------------------------------
# Sound registry
# ---------------------------------------------------------------------------

SOUNDS = {}


def sfx(name, dur, peak_db=-3.0, wet=0.12, loop=None, desc=""):
    """Registers a sound. loop=crossfade seconds for seamless loops."""
    def deco(fn):
        SOUNDS[name] = dict(name=name, fn=fn, dur=dur, peak_db=peak_db, wet=wet, loop=loop, desc=desc)
        return fn
    return deco


# ---- UI -------------------------------------------------------------------

@sfx("toggle", 0.15, -10, wet=0.06, desc="Two-note soft marimba blip (G5 then C6).")
def _toggle():
    x = buf(0.15)
    place(x, marimba(hz("G5"), 0.1, decay=0.035), 0.0, 0.8)
    place(x, marimba(hz("C6"), 0.1, decay=0.04), 0.055)
    return x


# ---- Character ------------------------------------------------------------

@sfx("poke", 0.3, -3, wet=0.08, desc="Rubbery boing with a little squeak.")
def _poke():
    t = T(0.3)
    f = 330 * (1 + 0.6 * np.exp(-t / 0.02)) * (1 + 0.12 * np.exp(-t / 0.09) * np.sin(2 * np.pi * 16 * t))
    ph = phase(f)
    x = (np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.1 * np.sin(3 * ph)) * env_ad(t, 0.002, 0.09)
    x = lp(x, 3000)
    ts = T(0.12)
    fs = curve(ts, [(0, 1300), (0.05, 1760), (0.12, 1500)], log=True)
    phs = phase(fs)
    squeak = (np.sin(phs) + 0.2 * np.sin(2 * phs)) * env_ad(ts, 0.006, 0.035)
    place(x, squeak, 0.012, 0.3)
    x += 0.3 * felt(0.3, fc=500, decay=0.01, body=None)
    return x


@sfx("stretch", 0.6, -7, wet=0.08, desc="Rubbery taffy stretch creak, pitch rising.")
def _stretch():
    t = T(0.6)
    f = glide(t, 200, 420, 0.6) * vibrato(t, 7, 0.02)
    tone = lp(np.tanh(1.5 * np.sin(phase(f))), 1500)
    x = 0.6 * tone + 0.5 * norm(creak(0.6, 30, 90, 700, 1500, q=5))
    return x * gate(t, 0.08, 0.1) * (0.6 + 0.4 * t / 0.6)


@sfx("snap_back", 0.5, -4, wet=0.1, desc="Wobbly 'boing-oing' sproing as the head springs back.")
def _snap_back():
    x = buf(0.5)
    tc = T(0.04)
    chirp = np.sin(phase(glide(tc, 300, 1200, 0.03))) * env_ad(tc, 0.001, 0.012)
    place(x, chirp, 0.0, 0.4)
    t = T(0.48)
    f0 = 392 * (1 + 0.25 * np.exp(-t / 0.12) * np.sin(2 * np.pi * 13 * t))
    spr = voice(f0, [(0, "oo"), (0.04, "ee"), (0.08, "oo"), (0.12, "ih"), (0.17, "oo"), (0.23, "eh"), (0.3, "oo")],
                breath=0.0, size=1.0, tilt=1.3, top=5000.0)
    spr *= env_ad(t, 0.004, 0.15)
    place(x, lp(spr, 3500), 0.02)
    return x


@sfx("hop", 0.15, -6, wet=0.06, desc="Small soft upward jump blip.")
def _hop():
    t = T(0.15)
    ph = phase(glide(t, 420, 880, 0.06, 0.6))
    x = (np.sin(ph) + 0.12 * np.sin(2 * ph)) * env_ad(t, 0.003, 0.04)
    x += 0.2 * felt(0.15, fc=700, decay=0.008, body=None)
    return x


@sfx("land", 0.25, -5, wet=0.1, desc="Soft felt thump with a tiny bell jingle.")
def _land():
    x = felt(0.25, fc=500, decay=0.03, body=(140, 80), body_amp=0.8)
    place(x, bell(hz("G6"), 0.2, decay=0.06, bright=0.3), 0.02, 0.15)
    place(x, bell(hz("C7"), 0.2, decay=0.06, bright=0.3), 0.045, 0.12)
    return x


@sfx("chirp_happy", 0.35, -6, wet=0.1, desc="Happy wordless coo, bouncing upward.")
def _chirp_happy():
    t = T(0.35)
    f0 = curve(t, [(0, 660), (0.05, 880), (0.12, 1050), (0.2, 990), (0.33, 1180)], log=True) * vibrato(t, 9, 0.015, 0.1)
    v = voice(f0, [(0, "oo"), (0.08, "ee"), (0.2, "ih"), (0.33, "ee")], breath=0.05)
    dip = 1 - 0.6 * np.exp(-(((t - 0.16) / 0.02) ** 2))
    return v * gate(t, 0.02, 0.06, 0.34) * dip


@sfx("chirp_curious", 0.4, -6, wet=0.1, desc="Curious 'hmm?' coo rising at the end.")
def _chirp_curious():
    t = T(0.4)
    f0 = curve(t, [(0, 620), (0.12, 580), (0.22, 640), (0.38, 1000)], log=True)
    v = voice(f0, [(0, "mm"), (0.12, "oo"), (0.26, "oh"), (0.38, "ee")], breath=0.05)
    return v * gate(t, 0.03, 0.05, 0.39)


@sfx("chirp_sad", 0.5, -7, wet=0.12, desc="Sad little descending coo with a wobble.")
def _chirp_sad():
    t = T(0.5)
    f0 = curve(t, [(0, 820), (0.08, 860), (0.45, 500)], log=True) * (1 + (0.01 + 0.03 * t / 0.5) * np.sin(2 * np.pi * 6 * t))
    v = voice(f0, [(0, "oo"), (0.2, "oh"), (0.45, "oo")], breath=0.12)
    return v * gate(t, 0.04, 0.12, 0.49)


@sfx("giggle", 0.5, -6, wet=0.1, desc="Three quick rising 'hee' coos.")
def _giggle():
    x = buf(0.5)
    for i, name in enumerate(("G5", "A5", "C6")):
        t = T(0.13)
        f0 = hz(name) * curve(t, [(0, 0.97), (0.05, 1.06), (0.13, 1.0)])
        v = voice(f0, [(0, "ih"), (0.06, "ee")], breath=0.15)
        place(x, v * gate(t, 0.01, 0.06), 0.01 + 0.15 * i, 0.8 + 0.1 * i)
    return x


@sfx("yawn", 0.9, -6, wet=0.12, desc="Slow sleepy descending coo, breathy.")
def _yawn():
    t = T(0.9)
    f0 = curve(t, [(0, 520), (0.2, 700), (0.35, 690), (0.8, 330), (0.9, 320)], log=True) * vibrato(t, 5, 0.015, 0.3)
    v = voice(f0, [(0, "oh"), (0.2, "ah"), (0.5, "ah"), (0.75, "oh"), (0.9, "oo")], breath=0.25)
    return v * gate(t, 0.15, 0.25, 0.89)


@sfx("snore", 1.6, -10, wet=0.08, loop=0.2, desc="One soft breathy snore cycle (seamless loop).")
def _snore():
    total = 1.8  # 1.6 loop + 0.2 crossfade
    t = T(total)
    n = len(t)
    x = np.zeros(n)
    # Inhale 0.25 to 0.85: soft fluttery "snrk".
    ti = T(0.6)
    flutter = 0.55 + 0.45 * np.sin(2 * np.pi * 32 * ti)
    inhale = norm(bp(noise(len(ti)), 250, 1400)) * flutter * swell(ti, 0.4, 0.6, 1.5)
    inhale += 0.25 * voice(np.full(len(ti), 110.0), [(0, "oh")], breath=0.0, size=1.0) * swell(ti, 0.4, 0.6, 1.5)
    place(x, inhale, 0.25, 0.8)
    # Exhale 0.95 to 1.55: airy "pwuuu" with a faint whistle.
    te = T(0.6)
    exhale = norm(svf(noise(len(te)), 700, 1.5)) * swell(te, 0.15, 0.6, 1.2)
    exhale += 0.12 * np.sin(phase(glide(te, 880, 784, 0.6))) * swell(te, 0.2, 0.6, 1.5)
    place(x, exhale, 0.95, 0.6)
    x += 0.02 * norm(lp(noise(n), 800))  # quiet room-tone floor keeps the loop alive
    return x


@sfx("soft_sweep", 1.2, -14, wet=0.25, desc="A quiet, soft sweep of air with a faint warm chord, for the app tilting into 3D and folding back.")
def _soft_sweep():
    t = T(1.2)
    # Low, breathy air: band-passed noise drifting gently up and back down,
    # kept well under 1.5 kHz so it never hisses.
    center = 350 + 650 * np.sin(np.pi * np.clip(t / 1.2, 0, 1)) ** 2
    air = lp(sweep_noise(1.2, center, 0.7), 1500) * swell(t, 0.5, 1.2, 1.6)
    chord = pad([hz("C4"), hz("G4"), hz("E5")], 1.2, 0.35, 0.6, harmonics=2, tilt=2.4)
    return air + 0.12 * chord


@sfx("heart", 0.35, -12, wet=0.12, desc="A tiny bright ping as a heart floats up.")
def _heart():
    return kalimba(hz("E6"), 0.35, decay=0.12) + 0.4 * kalimba(hz("G6"), 0.35, decay=0.08)


@sfx("sneeze_in", 0.9, -5, wet=0.12, desc="Two rising breathy inhales: 'ah... ah...'.")
def _sneeze_in():
    x = buf(0.9)
    for at, length, f_a, f_b, amp in ((0.02, 0.35, 600, 760, 0.7), (0.45, 0.42, 700, 980, 1.0)):
        t = T(length)
        f0 = glide(t, f_a, f_b, length, 0.8)
        v = voice(f0, [(0, "ah"), (length, "ah")], breath=0.6)
        air = sweep_noise(length, glide(t, 1200, 2400, length), 1.0)
        env = swell(t, length - 0.07, length, 1.6)
        place(x, (v + 0.3 * air) * env, at, amp)
    return x


@sfx("sneeze_out", 0.35, -3, wet=0.1, desc="Cute 'choo!' burst with a pop.")
def _sneeze_out():
    x = buf(0.35)
    t = T(0.35)
    ch = norm(svf(hp(noise(len(t)), 2500), 4000, 1.0)) * env_ad(t, 0.003, 0.03)
    x += 0.5 * ch
    tv = T(0.3)
    f0 = curve(tv, [(0, 1050), (0.04, 980), (0.2, 760), (0.3, 740)], log=True)
    v = voice(f0, [(0, "ih"), (0.03, "oo")], breath=0.1) * env_ad(tv, 0.008, 0.08)
    place(x, v, 0.025)
    place(x, bloop(900, 200, 0.06, sweep=0.006, decay=0.02), 0.02, 0.4)
    place(x, norm(lp(noise(ns(0.15)), 2000)) * env_ad(T(0.15), 0.002, 0.04), 0.03, 0.25)
    return x


@sfx("hat_pop", 0.2, -6, wet=0.1, desc="A round, cork-like pop as the hat flies off.")
def _hat_pop():
    t = T(0.2)
    x = 0.8 * bloop(400, 1200, 0.2, sweep=0.012, decay=0.025)
    x += 0.35 * bloop(200, 120, 0.2, sweep=0.02, decay=0.03)
    return x


@sfx("hat_land", 0.2, -7, wet=0.08, desc="Soft cloth plop.")
def _hat_land():
    t = T(0.2)
    x = norm(lp(noise(len(t)), 700)) * env_ad(t, 0.006, 0.035)
    x += 0.5 * np.sin(phase(approach(t, 170, 110, 0.03))) * env_ad(t, 0.004, 0.04)
    x += 0.1 * norm(bp(noise(len(t)), 1500, 4000)) * env_ad(t, 0.002, 0.015)
    return x


@sfx("dizzy", 0.9, -7, wet=0.15, desc="Wobbly cartoon spin warble with circling star bells.")
def _dizzy():
    t = T(0.9)
    base = glide(t, hz("G5"), hz("C5"), 0.9)
    x = np.zeros_like(t)
    for det, off in ((1.0, 0.0), (1.015, 1.7)):
        f = base * det * (1 + 0.06 * np.sin(2 * np.pi * 9 * t + off))
        ph = phase(f)
        x += np.sin(ph) + 0.11 * np.sin(3 * ph)
    x *= (0.75 + 0.25 * np.sin(2 * np.pi * 4.5 * t)) * gate(t, 0.03, 0.15)
    x = lp(x, 4000) * 0.5
    for at, name in ((0.1, "E7"), (0.3, "C7"), (0.5, "A6"), (0.7, "G6")):
        place(x, bell(hz(name), 0.2, decay=0.08, bright=0.2), at, 0.15)
    return x


@sfx("shy", 0.25, -9, wet=0.1, desc="Tiny embarrassed 'eep' squeak.")
def _shy():
    t = T(0.25)
    f0 = curve(t, [(0, 1100), (0.06, 1320), (0.2, 1180)], log=True)
    v = voice(f0, [(0, "ee"), (0.2, "ih")], breath=0.1)
    return v * gate(t, 0.015, 0.08, 0.24)


@sfx("wake", 0.4, -5, wet=0.2, desc="Bright little two-bell wake chime (E6, A6).")
def _wake():
    x = buf(0.4)
    place(x, bell(hz("E6"), 0.4, decay=0.22, bright=0.4, shimmer=0.2), 0.0, 0.8)
    place(x, bell(hz("A6"), 0.32, decay=0.25, bright=0.4, shimmer=0.2), 0.09)
    return x


# ---- Life moments ---------------------------------------------------------

@sfx("notify", 0.5, -4, wet=0.2, desc="Soft notification ding (E6 over C6).")
def _notify():
    x = bell(hz("E6"), 0.5, decay=0.25, bright=0.35, shimmer=0.25)
    x += 0.4 * bell(hz("C6"), 0.5, decay=0.2, bright=0.2)
    return x


@sfx("deliver", 0.6, -4, wet=0.2, desc="Warm chime landing on a card (C major pluck chord).")
def _deliver():
    x = 0.2 * felt(0.6, fc=600, decay=0.015, body=(180, 110))
    for at, name, a in ((0.0, "C5", 0.35), (0.01, "C6", 0.8), (0.025, "E6", 0.7)):
        place(x, kalimba(hz(name), 0.58, decay=0.3), at, a)
    place(x, bell(hz("G6"), 0.55, decay=0.25, bright=0.3), 0.04, 0.5)
    return x


def _bite(body_hz):
    t = T(0.2)
    x = 0.5 * np.sin(phase(approach(t, body_hz, body_hz * 0.5, 0.03))) * env_ad(t, 0.002, 0.03)
    x += 0.4 * norm(lp(noise(len(t)), 800)) * env_ad(t, 0.001, 0.02)
    snap = grain_cloud(0.2, 4, 0.0, 0.006, band=(1800, 6000), decay=(0.002, 0.004))
    crunch = grain_cloud(0.2, int(rng.integers(26, 38)), 0.003, 0.09, band=(1200, 5500),
                         decay=(0.0008, 0.003), amp=lambda tm: math.exp(-tm / 0.05), skew=1.6)
    after = grain_cloud(0.2, int(rng.integers(6, 10)), 0.1, 0.15, band=(1000, 4000),
                        decay=(0.0008, 0.002), amp=lambda tm: 0.35)
    g = snap * 1.2 + crunch + after
    x += 0.8 * g / (np.max(np.abs(g)) + 1e-9)
    return lp(x, 6500)


@sfx("bite_1", 0.2, -4, wet=0.05, desc="Crunchy chomp of a crisp wafer (variant 1).")
def _bite_1():
    return _bite(180)


@sfx("bite_2", 0.2, -4, wet=0.05, desc="Crunchy chomp of a crisp wafer (variant 2).")
def _bite_2():
    return _bite(165)


@sfx("bite_3", 0.2, -4, wet=0.05, desc="Crunchy chomp of a crisp wafer (variant 3).")
def _bite_3():
    return _bite(195)


@sfx("gulp", 0.3, -4, wet=0.08, desc="Cartoon 'gl-ulp' gulp.")
def _gulp():
    x = buf(0.3)
    place(x, bloop(180, 420, 0.1, sweep=0.03, decay=0.04, h2=0.2), 0.0, 0.7)
    place(x, norm(bp(noise(ns(0.05)), 300, 800)) * env_ad(T(0.05), 0.002, 0.01), 0.0, 0.2)
    place(x, bloop(260, 700, 0.16, sweep=0.035, decay=0.05, h2=0.2), 0.12)
    return lp(x, 2500)


@sfx("belly_rub", 1.2, -7, wet=0.1, desc="Content humming coo over soft rhythmic pats.")
def _belly_rub():
    t = T(1.2)
    f0 = curve(t, [(0, 440), (0.25, 523.25), (0.6, 587.33), (0.9, 523.25), (1.15, 440)], log=True) * vibrato(t, 5.5, 0.015, 0.2)
    hum = voice(f0, [(0, "mm"), (0.6, "oo"), (1.2, "mm")], breath=0.05) * gate(t, 0.15, 0.25)
    x = 0.8 * hum
    for at in (0.1, 0.38, 0.66, 0.94):
        place(x, felt(0.12, fc=600, decay=0.018, body=(150, 100), body_amp=0.5), at + rng.uniform(-0.01, 0.01), 0.45)
    return x


@sfx("burp", 0.35, -5, wet=0.08, desc="Tiny polite cute burp.")
def _burp():
    t = T(0.35)
    f0 = curve(t, [(0, 300), (0.05, 330), (0.2, 240), (0.35, 230)], log=True)
    v = voice(f0, [(0, "oh"), (0.1, "ah"), (0.2, "oh")], breath=0.08, size=1.15)
    v *= (0.6 + 0.4 * np.sin(2 * np.pi * 38 * t)) * gate(t, 0.012, 0.1, 0.3)
    place(v, bloop(900, 1100, 0.04, sweep=0.005, decay=0.01), 0.28, 0.15)
    return v


@sfx("spark_escape", 0.4, -8, wet=0.15, desc="The spark getting away: a quick descending zip.")
def _spark_escape():
    t = T(0.4)
    f = glide(t, 2100, 520, 0.32, 0.6) * vibrato(t, 30, 0.01)
    ph = phase(f)
    x = 0.7 * (np.sin(ph) + 0.12 * np.sin(2 * ph)) * gate(t, 0.005, 0.12, 0.34)
    x += 0.3 * norm(grain_cloud(0.4, 25, 0.02, 0.3, band=(2500, 7000), decay=(0.0005, 0.002),
                                amp=lambda tm: math.exp(-tm / 0.12)))
    return lp(x, 9000)


@sfx("snow_build", 0.3, -7, wet=0.08, desc="Soft snow packing crunch.")
def _snow_build():
    t = T(0.3)
    g = grain_cloud(0.3, 160, 0.0, 0.25, band=(700, 2500), decay=(0.002, 0.007),
                    amp=lambda tm: math.sin(math.pi * min(tm / 0.25, 1.0)) ** 0.7)
    x = 0.8 * norm(g) + 0.3 * norm(lp(noise(len(t)), 300)) * swell(t, 0.1, 0.28)
    return lp(x, 4000)


@sfx("snow_melt", 1.0, -6, wet=0.2, desc="Gentle descending drips, melting away.")
def _snow_melt():
    t = T(1.0)
    x = np.zeros_like(t)
    for at, name, a in ((0.12, "G6", 1.0), (0.38, "E6", 0.85), (0.62, "C6", 0.7), (0.85, "A5", 0.6)):
        place(x, drop(hz(name), 0.12), at, a * 0.6)
    return x


@sfx("refresh_pull", 0.4, -7, wet=0.08, desc="Elastic creak while pulling to refresh.")
def _refresh_pull():
    t = T(0.4)
    tone = lp(np.tanh(1.4 * np.sin(phase(glide(t, 180, 300, 0.4)))), 1400)
    x = 0.4 * tone + 0.6 * norm(creak(0.4, 25, 60, 600, 1100, q=5))
    return x * gate(t, 0.05, 0.08)


@sfx("refresh", 0.5, -4, wet=0.15, desc="Release boing plus a small chime.")
def _refresh():
    x = buf(0.5)
    tc = T(0.03)
    place(x, np.sin(phase(glide(tc, 260, 700, 0.025))) * env_ad(tc, 0.001, 0.01), 0.0, 0.3)
    t = T(0.48)
    f = 392 * (1 + 0.2 * np.exp(-t / 0.1) * np.sin(2 * np.pi * 12 * t))
    ph = phase(f)
    place(x, (np.sin(ph) + 0.3 * np.sin(2 * ph)) * env_ad(t, 0.003, 0.12), 0.015, 0.8)
    place(x, bell(hz("G6"), 0.35, decay=0.18, bright=0.3), 0.1, 0.3)
    place(x, bell(hz("C7"), 0.35, decay=0.2, bright=0.3), 0.13, 0.5)
    return x


@sfx("scroll_ride", 0.8, -6, wet=0.12, desc="'Wheee' swoop.")
def _scroll_ride():
    t = T(0.8)
    f0 = curve(t, [(0, 600), (0.25, 1050), (0.45, 1180), (0.75, 880), (0.8, 870)], log=True) * vibrato(t, 7, 0.015, 0.2)
    v = voice(f0, [(0, "ih"), (0.1, "ee"), (0.8, "ee")], breath=0.02)
    return v * gate(t, 0.08, 0.18)


@sfx("rain_loop", 4.0, -10, wet=0.15, loop=0.6, desc="Soft rain bed with patters and plips (seamless loop).")
def _rain_loop():
    total = 4.6
    t = T(total)
    n = len(t)
    bed = norm(hp(lp(noise(n), 4500), 400)) * (0.85 + 0.15 * np.sin(2 * np.pi * 0.31 * t))
    patter = norm(grain_cloud(total, int(60 * total), 0.0, total - 0.01, band=(2000, 6500),
                              decay=(0.0006, 0.0025), amp=lambda tm: rng.lognormal(-0.6, 0.5)))
    x = 0.35 * bed + 0.5 * patter
    k = 0.05
    while k < total - 0.12:
        place(x, drop(rng.uniform(1500, 3000), 0.1, decay=0.02), k, rng.uniform(0.06, 0.15))
        k += rng.exponential(0.33)
    return lp(x, 7000)


@sfx("shades", 0.4, -5, wet=0.18, desc="Sunglasses clink plus a cool little shimmer.")
def _shades():
    x = buf(0.4)
    place(x, bell(hz("E7"), 0.1, decay=0.03, bright=1.0), 0.0, 0.6)
    place(x, bell(hz("G7"), 0.1, decay=0.025, bright=1.0), 0.03, 0.45)
    t = T(0.32)
    sh = np.zeros_like(t)
    for f in (hz("A6"), hz("A6") * 1.004, hz("E6")):
        sh += np.sin(2 * np.pi * f * t)
    sh *= (0.6 + 0.4 * np.sin(2 * np.pi * 12 * t)) * swell(t, 0.08, 0.32, 1.2)
    place(x, sh, 0.07, 0.12)
    for i, name in enumerate(("G6", "A6", "C7", "E7")):
        place(x, bell(hz(name), 0.2, decay=0.06, bright=0.2), 0.08 + 0.03 * i, 0.2 + 0.03 * i)
    return x


@sfx("search_found", 0.6, -4, wet=0.22, desc="Sparkle arpeggio landing on a C7 bell.")
def _search_found():
    x = buf(0.6)
    for i, name in enumerate(("C6", "E6", "G6", "A6")):
        place(x, kalimba(hz(name), 0.3, decay=0.12), 0.045 * i, 0.4 + 0.05 * i)
    place(x, bell(hz("C7"), 0.42, decay=0.28, bright=0.35, shimmer=0.2), 0.19)
    place(x, bell(hz("G6"), 0.42, decay=0.22, bright=0.2), 0.19, 0.4)
    return x


@sfx("trick_bubble", 0.6, -4, wet=0.12, desc="Bubble blow and wobble ending in a soft blub.")
def _trick_bubble():
    t = T(0.6)
    blow = sweep_noise(0.6, glide(t, 600, 1200, 0.25), 1.0) * swell(t, 0.12, 0.28, 1.2)
    x = 0.3 * blow
    tw = T(0.42)
    f = glide(tw, 300, 520, 0.42) * (1 + 0.06 * np.sin(2 * np.pi * 9 * tw))
    ph = phase(f)
    wob = (np.sin(ph) + 0.2 * np.sin(2 * ph)) * (0.7 + 0.3 * np.sin(2 * np.pi * 9 * tw)) * swell(tw, 0.32, 0.42, 1.0)
    place(x, wob, 0.05, 0.7)
    place(x, bloop(600, 1400, 0.1, sweep=0.012, decay=0.02), 0.46, 0.5)
    return x


@sfx("trick_split", 0.6, -4, wet=0.15, desc="Splitting into minis: three rising pops.")
def _trick_split():
    x = buf(0.6)
    for at, name in ((0.05, "G5"), (0.2, "C6"), (0.35, "E6")):
        f = hz(name)
        place(x, bloop(f, 2 * f, 0.1, sweep=0.015, decay=0.03), at, 0.8)
        place(x, kalimba(2 * f, 0.2, decay=0.08), at + 0.01, 0.3)
    place(x, bell(hz("C7"), 0.15, decay=0.06, bright=0.2), 0.45, 0.15)
    return x


@sfx("trick_bloom", 0.7, -4, wet=0.25, desc="A flower blooming: a soft rising glide opening into a chime.")
def _trick_bloom():
    t = T(0.7)
    x = 0.3 * np.sin(phase(glide(t, 300, 1200, 0.45, 1.3))) * swell(t, 0.38, 0.6, 2.0)
    for at, name in ((0.1, "C5"), (0.18, "G5"), (0.26, "C6")):
        place(x, kalimba(hz(name), 0.3, decay=0.15), at, 0.3)
    for name in ("C6", "E6", "G6"):
        place(x, bell(hz(name), 0.3, decay=0.25, bright=0.35), 0.38, 0.35)
    return x


@sfx("trick_holo", 0.7, -5, wet=0.2, desc="Soft sci-fi hologram flicker-in settling on a chord.")
def _trick_holo():
    t = T(0.7)
    # A high flickering tone in place of a fizz.
    flick = 0.5 + 0.5 * np.sin(2 * np.pi * 30 * t) ** 2
    fizz = np.sin(2 * np.pi * hz("C7") * t) * flick * swell(t, 0.4, 0.68, 1.5)
    f = glide(t, 261.63, 523.25, 0.35)
    tone = np.zeros_like(t)
    for d in (0.995, 1.0, 1.005):
        ph = phase(f * d)
        tone += np.sin(ph + 0.6 * np.sin(3 * ph)) + 0.3 * np.sin(2 * ph)
    tone = lp(tone, 2500) * swell(t, 0.35, 0.68, 1.2)
    x = 0.12 * fizz + 0.3 * norm(tone)
    place(x, bell(hz("C6"), 0.33, decay=0.2, bright=0.3), 0.35, 0.35)
    place(x, bell(hz("G6"), 0.33, decay=0.2, bright=0.3), 0.37, 0.3)
    return x


# ---- Errand, room, map, booth -------------------------------------------

@sfx("press", 0.15, -6, wet=0.05, desc="Big soft button press click (down and release).")
def _press():
    t = T(0.15)
    click = norm(svf(hp(noise(len(t)), 2000), 3500, 1.5)) * env_ad(t, 0.0003, 0.002)
    x = 0.5 * click
    x += 0.8 * np.sin(phase(approach(t, 200, 120, 0.02))) * env_ad(t, 0.001, 0.03)
    x += 0.5 * norm(lp(noise(len(t)), 900)) * env_ad(t, 0.001, 0.012)
    place(x, click, 0.06, 0.25)
    return lp(x, 6000)


@sfx("key_get", 0.8, -3, wet=0.25, desc="Magical key get: rising bell arpeggio and a key jingle.")
def _key_get():
    x = buf(0.8)
    for i, name in enumerate(("C6", "E6", "G6", "C7")):
        place(x, bell(hz(name), 0.6, decay=0.3 + 0.05 * i, bright=0.4, shimmer=0.15), 0.07 * i, 0.6 + 0.13 * i)
    for _ in range(6):
        at = rng.uniform(0.25, 0.6)
        tt = T(0.08)
        f = rng.uniform(3000, 5000)
        clink = sum(a * np.sin(2 * np.pi * f * r * tt) for r, a in ((1, 1), (1.47, 0.5), (2.09, 0.3))) * env_ad(tt, 0.0005, 0.015)
        place(x, clink, at, 0.08)
    return x


@sfx("lamp", 0.1, -12, wet=0.05, desc="Small lamp switch click.")
def _lamp():
    t = T(0.1)
    x = norm(svf(noise(len(t)), 2800, 2.0)) * env_ad(t, 0.0003, 0.0015)
    x += 0.3 * np.sin(2 * np.pi * 1600 * t) * env_ad(t, 0.0005, 0.006)
    x += 0.3 * norm(lp(noise(len(t)), 600)) * env_ad(t, 0.0005, 0.004)
    return x


@sfx("party", 0.9, -3, wet=0.22, desc="Party popper pop with a confetti tinkle.")
def _party():
    t = T(0.9)
    x = norm(lp(noise(len(t)), 3000)) * env_ad(t, 0.0005, 0.012)
    x += 0.6 * np.sin(phase(approach(t, 300, 120, 0.02))) * env_ad(t, 0.001, 0.03)
    x += 0.2 * norm(svf(noise(len(t)), 4000, 1.0)) * env_ad(t, 0.002, 0.05)
    notes = ("C6", "D6", "E6", "G6", "A6", "C7", "D7", "E7")
    for _ in range(14):
        at = 0.06 + 0.7 * rng.random() ** 1.6
        name = notes[rng.integers(len(notes))]
        place(x, bell(hz(name), 0.2, decay=rng.uniform(0.06, 0.12), bright=0.3), at, rng.uniform(0.15, 0.35) * (1 - at))
    paper = norm(bp(noise(len(t)), 1800, 4000)) * norm(lp(np.abs(noise(len(t))), 30)) * env_ad(t, 0.05, 0.25)
    x += 0.06 * paper
    return x


@sfx("map_step", 0.12, -12, wet=0.05, desc="Tiny footstep hop on cobbles.")
def _map_step():
    x = felt(0.12, fc=900, decay=0.012, body=(180, 130), body_amp=0.4)
    t = T(0.12)
    x += 0.25 * np.sin(2 * np.pi * 1100 * t) * env_ad(t, 0.0005, 0.012)
    return x


@sfx("arrive", 0.7, -3, wet=0.25, desc="Arrival chime: rolled G5 C6 E6 G6 bells.")
def _arrive():
    x = buf(0.7)
    place(x, kalimba(hz("C5"), 0.6, decay=0.3), 0.0, 0.3)
    for i, name in enumerate(("G5", "C6", "E6", "G6")):
        place(x, bell(hz(name), 0.65 - 0.05 * i, decay=0.3, bright=0.35, shimmer=0.15), 0.05 * i, 0.6 + 0.1 * i)
    return x


@sfx("countdown", 0.15, -8, wet=0.08, desc="One soft countdown beep (C6).")
def _countdown():
    t = T(0.15)
    f = hz("C6")
    return (np.sin(2 * np.pi * f * t) + 0.15 * np.sin(4 * np.pi * f * t)) * env_ad(t, 0.004, 0.05)


@sfx("countdown_go", 0.25, -6, wet=0.1, desc="Higher 'go' beep (G6 over G5).")
def _countdown_go():
    t = T(0.25)
    f = hz("G6")
    x = np.sin(2 * np.pi * f * t) + 0.12 * np.sin(4 * np.pi * f * t) + 0.3 * np.sin(np.pi * f * t)
    return x * env_ad(t, 0.004, 0.09)


@sfx("shutter", 0.45, -5, wet=0.1, desc="Camera shutter double click with a soft rising flash whine.")
def _shutter():
    x = buf(0.45)
    tc = T(0.05)
    click = norm(svf(noise(len(tc)), 3000, 1.5)) * env_ad(tc, 0.0003, 0.003)
    click += 0.2 * np.sin(2 * np.pi * 1800 * tc) * env_ad(tc, 0.0005, 0.008)
    click += 0.4 * norm(lp(noise(len(tc)), 400)) * env_ad(tc, 0.0005, 0.01)
    place(x, click, 0.0, 0.8)
    place(x, click, 0.06, 0.6)
    tw = T(0.37)
    whine = np.sin(phase(glide(tw, 1400, 3600, 0.37, 0.7))) * gate(tw, 0.05, 0.08)
    place(x, whine, 0.08, 0.12)
    return x


# ---- Games ----------------------------------------------------------------

@sfx("star_catch", 0.35, -4, wet=0.15, desc="Bright clean C6 twinkle (the game pitches it up per combo).")
def _star_catch():
    x = bell(hz("C6"), 0.35, decay=0.14, bright=0.0, attack=0.001)
    t = T(0.35)
    x += 0.15 * np.sin(2 * np.pi * hz("C7") * t) * env_ad(t, 0.001, 0.05)
    return x


@sfx("star_miss", 0.3, -6, wet=0.1, desc="Soft low plunk (C4).")
def _star_miss():
    t = T(0.3)
    f = approach(t, hz("C4") * 1.03, hz("C4"), 0.02)
    ph = phase(f)
    x = (np.sin(ph) + 0.15 * np.sin(3.98 * ph)) * env_ad(t, 0.001, 0.08)
    x += 0.3 * felt(0.3, fc=400, decay=0.02, body=None)
    return lp(x, 1500)


@sfx("combo", 0.5, -4, wet=0.18, desc="Rising C6 E6 G6 arpeggio.")
def _combo():
    x = buf(0.5)
    for i, name in enumerate(("C6", "E6", "G6")):
        place(x, kalimba(hz(name), 0.4, decay=0.2 + 0.04 * i), 0.07 * i, 0.5 + 0.1 * i)
        place(x, bell(hz(name), 0.4, decay=0.2 + 0.04 * i, bright=0.2), 0.07 * i, 0.3 + 0.1 * i)
    return x


@sfx("banner", 1.0, -4, wet=0.3, desc="Level banner swell: warm chord, a rising glide, sparkle.")
def _banner():
    t = T(1.0)
    chord = pad([hz("C5"), hz("E5"), hz("G5"), hz("C6")], 1.0, 0.35, 0.4)
    chord += 0.4 * pad([hz("C4")], 1.0, 0.35, 0.4)
    x = 0.5 * norm(chord) * (0.6 + 0.4 * swell(t, 0.4, 1.0, 1.0))
    x += 0.12 * np.sin(phase(glide(t, hz("C5"), hz("C6"), 0.4, 0.8))) * swell(t, 0.4, 0.9, 1.5)
    for at, name in ((0.3, "G6"), (0.38, "C7"), (0.46, "E7")):
        place(x, bell(hz(name), 0.5, decay=0.15, bright=0.3), at, 0.3)
    return x


@sfx("thrust_loop", 2.0, -6, wet=0.0, loop=0.4, desc="Warm airy jet burner (seamless loop).")
def _thrust_loop():
    total = 2.4
    t = T(total)
    n = len(t)
    flicker = 0.85 + 0.15 * norm(lp(noise(n), 8))
    body = norm(lp(noise(n), 1000)) + 0.7 * norm(svf(noise(n), 350, 0.7))
    rumble = np.sin(2 * np.pi * 70 * t) + 0.5 * np.sin(2 * np.pi * 105 * t + 1)
    rumble *= 0.75 + 0.25 * norm(lp(noise(n), 6))
    hiss = norm(svf(noise(n), 2500, 0.7))
    x = flicker * (0.8 * norm(body) + 0.15 * hiss) + 0.25 * rumble
    return lp(x, 3000)


@sfx("zap", 0.4, -5, wet=0.12, desc="Soft electric zap from a storm cloud.")
def _zap():
    t = T(0.4)
    fc = glide(t, 880, 220, 0.25)
    ph = phase(fc)
    tone = np.sin(ph + 1.5 * np.sin(2 * np.pi * 110 * t))
    gatez = 0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 45 * t + 3 * norm(lp(noise(len(t)), 20))))
    gatez = lp(gatez, 400)
    x = 0.7 * tone * gatez * env_ad(t, 0.003, 0.12)
    x += 0.25 * norm(grain_cloud(0.4, 30, 0.0, 0.22, band=(3000, 7000), decay=(0.0005, 0.002),
                                 amp=lambda tm: math.exp(-tm / 0.1)))
    x += 0.5 * norm(svf(noise(len(t)), 2000, 1.0)) * env_ad(t, 0.0005, 0.004)
    return lp(x, 4000)


@sfx("boing", 0.45, -3, wet=0.12, desc="Big bouncy cloud boing (jaw-harp style 'boyoyoing').")
def _boing():
    t = T(0.45)
    damp = np.exp(-t / 0.15)
    osc = np.cos(2 * np.pi * 9 * t)
    f0 = approach(t, 147, 196, 0.03) * (1 + 0.04 * np.exp(-t / 0.2) * np.sin(2 * np.pi * 9 * t))
    F = np.array([450 + 150 * damp * osc, 1100 + 900 * damp * osc, np.full(len(t), 2700.0)])
    G = np.array([np.ones(len(t)), np.full(len(t), 0.7), np.full(len(t), 0.15)])
    x = voice(f0, F=F, G=G, breath=0.0, size=1.0, tilt=1.2, top=5000.0) * env_ad(t, 0.004, 0.18)
    x += 0.3 * np.sin(phase(approach(t, 140, 90, 0.02))) * env_ad(t, 0.002, 0.03)
    return lp(x, 4500)


@sfx("glow_pickup", 0.4, -6, wet=0.2, desc="Warm lantern pickup: G5 to C6 pluck with a glow swell.")
def _glow_pickup():
    t = T(0.4)
    x = 0.25 * norm(pad([hz("C5"), hz("G5")], 0.4, 0.05, 0.25, harmonics=2)) * swell(t, 0.12, 0.38, 1.0)
    place(x, kalimba(hz("G5"), 0.35, decay=0.2), 0.0, 0.7)
    place(x, kalimba(hz("C6"), 0.34, decay=0.22), 0.06, 0.9)
    place(x, bell(hz("E7"), 0.2, decay=0.07, bright=0.2), 0.08, 0.1)
    return x


@sfx("moon_fanfare", 2.0, -3, wet=0.3, desc="Short magical fanfare on reaching the moon.")
def _moon_fanfare():
    x = buf(2.0)
    for i, name in enumerate(("G5", "C6", "E6", "G6")):
        place(x, kalimba(hz(name), 0.5, decay=0.25), 0.12 * i, 0.5)
        place(x, bell(hz(name), 0.5, decay=0.25, bright=0.3), 0.12 * i, 0.35)
    place(x, felt(0.2, fc=500, decay=0.02, body=(150, 90)), 0.5, 0.25)
    for name in ("C6", "E6", "G6", "C7"):
        place(x, bell(hz(name), 1.45, decay=0.7, bright=0.35, shimmer=0.2), 0.55, 0.4)
    horn = pad([hz("C4"), hz("G4"), hz("C5"), hz("E5")], 1.5, 0.25, 0.7, harmonics=5, tilt=1.4)
    place(x, norm(horn), 0.5, 0.3)
    notes = ("C7", "D7", "E7", "G7", "A7")
    for _ in range(10):
        place(x, bell(hz(notes[rng.integers(5)]), 0.2, decay=0.07, bright=0.2), rng.uniform(0.6, 1.6), 0.12)
    return x


@sfx("results", 1.2, -4, wet=0.25, desc="Gentle results jingle resolving to a C major chord.")
def _results():
    x = buf(1.2)
    for i, name in enumerate(("G5", "C6", "E6", "D6")):
        place(x, kalimba(hz(name), 0.4, decay=0.2), 0.13 * i, 0.6)
    for name in ("C6", "E6", "G6"):
        place(x, kalimba(hz(name), 0.6, decay=0.35), 0.6, 0.45)
        place(x, bell(hz(name), 0.6, decay=0.3, bright=0.2), 0.6, 0.25)
    place(x, pad([hz("C5")], 1.1, 0.3, 0.4), 0.05, 0.08)
    return x


@sfx("game_start", 0.5, -4, wet=0.15, desc="'3-2-1 go' start sting: three ticks into a bright chord.")
def _game_start():
    x = buf(0.5)
    for i in range(3):
        place(x, marimba(hz("G5"), 0.08, decay=0.03), 0.09 * i, 0.55)
    t = T(0.12)
    place(x, sweep_noise(0.12, glide(t, 800, 3000, 0.1), 1.0) * swell(t, 0.09, 0.12), 0.18, 0.15)
    place(x, kalimba(hz("C6"), 0.23, decay=0.15), 0.27, 0.6)
    place(x, bell(hz("G6"), 0.23, decay=0.15, bright=0.3), 0.27, 0.5)
    place(x, bell(hz("C7"), 0.23, decay=0.18, bright=0.3, shimmer=0.2), 0.27, 0.7)
    return x


# ---------------------------------------------------------------------------
# Gentle UI and interaction sounds: tones only, no noise. Soft pitched
# bloops, wooden marimba and bell notes, and smooth glides; nothing that
# hisses or rustles (an FFT audit flagged the old swishes as noise).
# ---------------------------------------------------------------------------

@sfx("tap", 0.08, -14, wet=0.03, desc="A tiny round blip on C6.")
def _tap():
    return bloop(hz("C6") * 1.06, hz("C6"), 0.08, sweep=0.004, decay=0.02, h2=0.05)


@sfx("open", 0.4, -9, wet=0.18, desc="A soft rising bloop that blooms into two quiet bells (E6, G6).")
def _open():
    t = T(0.4)
    x = 0.8 * bloop(hz("G4"), hz("C5"), 0.4, sweep=0.05, decay=0.09, h2=0.08)
    place(x, bell(hz("E6"), 0.3, decay=0.14, bright=0.1), 0.06, 0.32)
    place(x, bell(hz("G6"), 0.25, decay=0.12, bright=0.1), 0.13, 0.26)
    return x


@sfx("close", 0.35, -10, wet=0.15, desc="A soft falling bloop settling on two wooden notes (E5, C5).")
def _close():
    x = 0.8 * bloop(hz("C5"), hz("G4"), 0.35, sweep=0.05, decay=0.08, h2=0.08)
    place(x, marimba(hz("E5"), 0.2, decay=0.06), 0.03, 0.35)
    place(x, marimba(hz("C5"), 0.2, decay=0.07), 0.1, 0.3)
    return x


@sfx("dissolve", 0.6, -9, wet=0.25, desc="A gentle shimmering pentatonic swell for a cross-dissolve.")
def _dissolve():
    t = T(0.6)
    x = np.zeros_like(t)
    for name in ("C6", "E6", "G6", "C7"):
        f = hz(name)
        trem = 0.75 + 0.25 * np.sin(2 * np.pi * rng.uniform(5, 8) * t + rng.uniform(0, 6.28))
        x += trem * (np.sin(2 * np.pi * f * t) + 0.15 * np.sin(2 * np.pi * 2 * f * t + 1))
    x = 0.22 * x * swell(t, 0.35, 0.6)
    for at, name in ((0.12, "E7"), (0.22, "A6"), (0.3, "G7"), (0.4, "C7")):
        place(x, bell(hz(name), 0.2, decay=0.07, bright=0.1), at, 0.1)
    return x


@sfx("card_flip", 0.2, -12, wet=0.08, desc="Two quick soft wooden ticks.")
def _card_flip():
    x = buf(0.2)
    place(x, marimba(hz("E6"), 0.1, decay=0.018), 0.0, 0.8)
    place(x, marimba(hz("A6"), 0.1, decay=0.015), 0.045, 0.5)
    return x


@sfx("swap", 0.6, -7, wet=0.25, desc="A round magical 'bwoop' rising into a chime, for switching friends.")
def _swap():
    t = T(0.6)
    f = glide(t, 280, 620, 0.22, 0.8) * vibrato(t, 9, 0.012)
    x = 0.7 * np.sin(phase(f)) * env_ad(t, 0.01, 0.16)
    for at, name, a in ((0.08, "C6", 0.4), (0.14, "G6", 0.4), (0.2, "C7", 0.45)):
        place(x, bell(hz(name), 0.4, decay=0.2, bright=0.15), at, a)
    return x


@sfx("hat_equip", 0.35, -8, wet=0.15, desc="A soft low plop as the hat goes on, and a twinkle.")
def _hat_equip():
    x = 0.8 * bloop(hz("G4"), hz("C4"), 0.35, sweep=0.03, decay=0.05, h2=0.1)
    place(x, bell(hz("E7"), 0.25, decay=0.1, bright=0.1), 0.08, 0.22)
    place(x, bell(hz("G7"), 0.2, decay=0.09, bright=0.1), 0.13, 0.18)
    return x


@sfx("catch", 0.2, -8, wet=0.08, desc="A quick soft pluck as something lands in hand.")
def _catch():
    x = 0.8 * kalimba(hz("C5"), 0.2, decay=0.07)
    place(x, bloop(hz("G5"), hz("C6"), 0.1, sweep=0.01, decay=0.02, h2=0.05), 0.0, 0.3)
    return x


@sfx("throw", 0.3, -9, wet=0.08, desc="A smooth falling glide, a toss.")
def _throw():
    t = T(0.3)
    f = glide(t, 950, 420, 0.22, 1.2)
    return 0.8 * np.sin(phase(f)) * swell(t, 0.05, 0.3, 1.3)


@sfx("tumble", 0.7, -8, wet=0.12, desc="A round warbling roll, 'whup-whup-whup', all tone.")
def _tumble():
    t = T(0.7)
    f = glide(t, 620, 380, 0.7, 1.0) * vibrato(t, 7, 0.08)
    whups = 0.55 + 0.45 * np.sin(2 * np.pi * 6.5 * t - np.pi / 2) ** 2
    return 0.7 * np.sin(phase(f)) * whups * swell(t, 0.08, 0.7, 1.4)


@sfx("butterfly", 0.8, -14, wet=0.12, desc="A faint, high, fluttering shimmer of wings.")
def _butterfly():
    t = T(0.8)
    flutter = 0.5 + 0.5 * np.sin(2 * np.pi * 24 * t) ** 2
    x = 0.4 * np.sin(2 * np.pi * hz("E6") * t) * flutter * swell(t, 0.3, 0.8)
    place(x, bell(hz("A7"), 0.2, decay=0.08, bright=0.1), 0.25, 0.12)
    return x


@sfx("pet_stroke", 0.28, -18, wet=0.04, desc="A very soft low glide, a hand stroking the head.")
def _pet_stroke():
    t = T(0.28)
    f = glide(t, 300, 420, 0.28, 1.0)
    return 0.6 * np.sin(phase(f)) * swell(t, 0.1, 0.28, 1.5)


@sfx("umbrella", 0.3, -7, wet=0.1, desc="A soft round 'fwump' as the umbrella opens.")
def _umbrella():
    x = 0.8 * bloop(220, 140, 0.3, sweep=0.04, decay=0.06, h2=0.1)
    place(x, bloop(hz("G5"), hz("C6"), 0.12, sweep=0.01, decay=0.03, h2=0.05), 0.04, 0.3)
    return x


@sfx("room_open", 0.6, -7, wet=0.2, desc="Two warm wooden notes and a soft glow of chord, into the cozy room.")
def _room_open():
    t = T(0.6)
    x = 0.12 * pad([hz("C4"), hz("E4"), hz("G4")], 0.6, 0.15, 0.4, harmonics=2, tilt=2.2)
    place(x, marimba(hz("C4"), 0.4, decay=0.12), 0.0, 0.6)
    place(x, marimba(hz("G4"), 0.4, decay=0.12), 0.09, 0.5)
    return x


@sfx("spark_zip", 0.35, -9, wet=0.12, desc="A spark zipping past: a quick bright rising glide.")
def _spark_zip():
    t = T(0.35)
    f = glide(t, 900, 2600, 0.25, 1.4)
    x = 0.5 * np.sin(phase(f)) * swell(t, 0.08, 0.35, 1.6) * (0.75 + 0.25 * np.sin(2 * np.pi * 30 * t))
    place(x, bell(hz("E7"), 0.15, decay=0.05, bright=0.1), 0.18, 0.15)
    return x


# ---------------------------------------------------------------------------
# Rendering and output
# ---------------------------------------------------------------------------

# Sounds meant to have texture (rain, a crunch, a breath, a burner); every
# other sound has any faint bed of noise gated out of it.
TEXTURAL = {"rain_loop", "bite_1", "bite_2", "bite_3", "snore", "thrust_loop", "sneeze_in", "sneeze_out", "snow_build", "burp"}


def gate_noise(x, depth_db=40.0, knee_db=12.0):
    """A gentle spectral gate: in each short frame, bins far below that
    frame's strongest are turned down (to -20 dB at most), so tones stay and
    a quiet hiss under them goes."""
    if len(x) < 1024:
        return x
    f, t, Z = signal.stft(x, fs=SR, nperseg=1024, noverlap=768)
    mag = np.abs(Z) + 1e-12
    db = 20 * np.log10(mag)
    top = db.max(axis=0, keepdims=True)
    under = (top - depth_db) - db
    gain = 10 ** (-np.clip(under / knee_db, 0, 1))
    _, y = signal.istft(Z * gain, fs=SR, nperseg=1024, noverlap=768)
    return y[: len(x)] if len(y) >= len(x) else np.pad(y, (0, len(x) - len(y)))


def finish(spec, x):
    """Room, DC removal, gentle top-end rounding, fades or loop, normalize."""
    dur, loop = spec["dur"], spec["loop"]
    target = ns(dur) + (ns(loop) if loop else 0)
    x = np.asarray(x, dtype=np.float64)
    x = np.pad(x, (0, max(0, target - len(x))))[:target]
    x = room(x, spec["wet"])
    x = hp(x, 30.0)
    x = lp(x, 15000.0)
    if spec["name"] not in TEXTURAL:
        x = gate_noise(x)
    if loop:
        F = ns(loop)
        n = len(x) - F
        w = np.linspace(0.0, 1.0, F)
        fade_in, fade_out = np.sin(0.5 * np.pi * w), np.cos(0.5 * np.pi * w)  # equal power
        y = x[:n].copy()
        y[:F] = x[:F] * fade_in + x[n:] * fade_out
        x = y - np.mean(y)
    else:
        fi = ns(0.0015)
        fo = ns(min(max(0.12 * dur, 0.004), 0.2))
        x[:fi] *= ramp_in(np.arange(fi) / SR, fi / SR)
        x[-fo:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(fo) / (fo - 1))
    if not np.all(np.isfinite(x)):
        raise ValueError("non-finite samples")
    return norm(x) * 10 ** (spec["peak_db"] / 20.0)


def write_wav(path, x):
    pcm = np.clip(np.round(x * 32767.0), -32767, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def render(name):
    global rng
    if name in PROTECTED:
        raise SystemExit(f"refusing to overwrite {name}.wav (owned by tool/make_sounds.py)")
    spec = SOUNDS[name]
    rng = np.random.default_rng(zlib.crc32(name.encode()))
    x = finish(spec, spec["fn"]())
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{name}.wav")
    write_wav(path, x)
    print(f"wrote {os.path.relpath(path)}  {len(x) / SR:.2f}s  peak {spec['peak_db']:+.0f} dBFS")


def verify():
    """Checks every wav in assets/sfx: format, peak, length, DC, and end clicks."""
    ok = True
    print(f"{'file':<22}{'secs':>6}{'peak':>8}{'rms':>8}{'centroid':>10}  notes")
    for fn in sorted(os.listdir(OUT)):
        if not fn.endswith(".wav"):
            continue
        name = fn[:-4]
        with wave.open(os.path.join(OUT, fn), "rb") as w:
            fmt = (w.getnchannels(), w.getsampwidth(), w.getframerate())
            x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0
        notes = []
        if fmt != (1, 2, SR):
            notes.append(f"BAD FORMAT {fmt}")
        peak = np.max(np.abs(x))
        peak_db = 20 * np.log10(max(peak, 1e-9))
        rms_db = 20 * np.log10(max(np.sqrt(np.mean(x ** 2)), 1e-9))
        mag = np.abs(np.fft.rfft(x))
        centroid = float(np.sum(np.fft.rfftfreq(len(x), 1 / SR) * mag) / (np.sum(mag) + 1e-12))
        if peak >= 0.999:
            notes.append("CLIPPING")
        if abs(np.mean(x)) > 0.002:
            notes.append(f"DC {np.mean(x):+.4f}")
        spec = SOUNDS.get(name)
        if spec:
            if abs(len(x) - ns(spec["dur"])) > 1:
                notes.append(f"LENGTH {len(x) / SR:.3f} != {spec['dur']}")
            if peak_db > -2.5:
                notes.append("TOO HOT")
            if spec["loop"]:
                step = np.median(np.abs(np.diff(x))) + 1e-9
                wrap = abs(x[0] - x[-1])
                notes.append(f"loop wrap/step {wrap / step:.1f}")
                if wrap > 8 * step + 0.002:
                    notes.append("LOOP SEAM")
            elif abs(x[0]) > 0.002 or abs(x[-1]) > 0.002:
                notes.append("END CLICK")
        else:
            notes.append("(make_sounds.py)")
        bad = any(s.isupper() and not s.startswith("(") for s in (n.split()[0] for n in notes))
        ok &= not bad
        print(f"{fn:<22}{len(x) / SR:6.2f}{peak_db:8.1f}{rms_db:8.1f}{centroid:10.0f}  {' '.join(notes)}")
    print("all good" if ok else "PROBLEMS FOUND")
    return ok


def main(argv):
    if "--list" in argv:
        for name, spec in SOUNDS.items():
            print(f"{name:<16}{spec['dur']:5.2f}s  {spec['desc']}")
        return 0
    if "--verify" in argv:
        return 0 if verify() else 1
    names = [a for a in argv if not a.startswith("-")] or list(SOUNDS)
    unknown = [n for n in names if n not in SOUNDS]
    if unknown:
        raise SystemExit(f"unknown sound(s): {', '.join(unknown)}")
    for name in names:
        render(name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
