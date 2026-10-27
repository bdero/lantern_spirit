#!/usr/bin/env python3
"""Synthesizes the app's sound effects into assets/sfx/*.wav.

Everything is generated from oscillators and filtered noise, so the sounds
carry no third-party rights. Run from the package root:

    python3 tool/make_sounds.py
"""

import math
import os
import struct
import wave

import numpy as np

SR = 44100
OUT = "assets/sfx"
rng = np.random.default_rng(7)


def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def lowpass(x, cutoff):
    """One-pole low-pass, cutoff in Hz (scalar or per-sample array)."""
    c = np.broadcast_to(np.asarray(cutoff, dtype=np.float64), x.shape)
    a = 1.0 - np.exp(-2.0 * np.pi * c / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def env(t, attack, decay):
    return np.minimum(1.0, t / max(attack, 1e-4)) * np.exp(-np.maximum(0.0, t - attack) / decay)


# Drawn but no longer written: never played, and mostly noise. They are
# still drawn so every sound after them stays the same.
RETIRED = {"whoosh", "puff", "boom_big", "boom_small", "launch"}


def write(name, x, peak=0.9):
    if name in RETIRED:
        return
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1.0
    x = x / m * peak
    # 5 ms fades to avoid clicks.
    f = int(SR * 0.005)
    x[:f] *= np.linspace(0, 1, f)
    x[-f:] *= np.linspace(1, 0, f)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(f"{OUT}/{name}.wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(v * 32767)) for v in x))
    print(f"wrote {OUT}/{name}.wav ({len(x) / SR:.2f}s)")


def noise(n):
    return rng.standard_normal(n)


# (A rising shell whistle used to be drawn here; the shells are too far off
# to hear it. Its noise is still drawn so every sound below stays the same.)
noise(int(SR * 1.9))

# Mortar launch: a dull low thud.
t = t_axis(0.45)
launch = lowpass(noise(len(t)), 900) * env(t, 0.003, 0.06) + np.sin(2 * np.pi * (90 - 60 * t) * t) * env(t, 0.002, 0.09)
write("launch", launch, 0.6)


def boom(seconds, body_hz, tail):
    t = t_axis(seconds)
    sub = np.sin(2 * np.pi * (body_hz * np.exp(-t * 3) + 28) * t) * env(t, 0.004, 0.35)
    crack = highpass(noise(len(t)), 600) * env(t, 0.001, 0.035)
    rumble = lowpass(noise(len(t)), 220 + 900 * np.exp(-t * 6)) * env(t, 0.01, tail)
    return sub * 0.9 + crack * 0.35 + rumble * 1.4


write("boom_big", boom(3.2, 70, 1.1), 0.95)
write("boom_small", boom(1.6, 95, 0.45), 0.8)

# Crackle: sparse sharp clicks thinning out.
t = t_axis(1.8)
cr = np.zeros(len(t))
k = 0.0
while k < 1.7:
    i = int(k * SR)
    n = int(SR * 0.004)
    cr[i:i + n] += highpass(noise(n), 2500) * np.exp(-np.arange(n) / (SR * 0.0008)) * rng.uniform(0.4, 1)
    k += rng.exponential(0.012 + k * 0.03)
write("crackle", cr, 0.55)


def chime(notes, seconds, decay):
    t = t_axis(seconds)
    x = np.zeros(len(t))
    for start, hz in notes:
        tt = np.maximum(0, t - start)
        on = (t >= start).astype(float)
        for h, a in ((1, 1.0), (2.76, 0.35), (5.4, 0.12)):
            x += np.sin(2 * np.pi * hz * h * tt) * a * np.exp(-tt / (decay / h)) * on
    return x


write("sparkle", chime([(0, 1318.5), (0.06, 1760.0), (0.12, 2637.0)], 1.0, 0.45), 0.5)
write("coin", chime([(0, 987.8), (0.09, 1318.5)], 0.9, 0.35), 0.5)

# Poke and UI pop: a soft rounded boop.
t = t_axis(0.22)
pop = np.sin(2 * np.pi * np.cumsum(520 * np.exp(-t * 7) + 220) / SR) * env(t, 0.004, 0.06)
write("pop", pop, 0.6)

# Squish for the soft body: a low wobble.
t = t_axis(0.45)
squish = np.sin(2 * np.pi * np.cumsum(180 + 60 * np.sin(2 * np.pi * 11 * t)) / SR) * env(t, 0.01, 0.12)
squish += lowpass(noise(len(t)), 400) * env(t, 0.005, 0.05) * 0.3
write("squish", squish, 0.5)

# Whoosh for the dive through the card.
t = t_axis(1.1)
sweep = 300 + 3500 * np.sin(np.pi * t / t[-1]) ** 2
whoosh = lowpass(noise(len(t)), sweep) * np.sin(np.pi * t / t[-1]) ** 1.5
write("whoosh", whoosh, 0.45)

# A puff of glow for Sky Lift.
t = t_axis(0.35)
puff = lowpass(highpass(noise(len(t)), 300), 2200) * env(t, 0.01, 0.08)
write("puff", puff, 0.45)

# ---------------------------------------------------------------------------
# Distant shell bursts, heard from across the lagoon. Each is its own event,
# played when the shell breaks (after the sound's travel time), never mixed
# with the launch. Air soaks up the highs over distance, so the crack is
# muffled; the far shore throws back a few slapback echoes; and a low rumble
# rolls on after. Several variants so a busy finale never repeats itself.
# A separate random stream, so adding these leaves every sound above as it
# was.
brng = np.random.default_rng(1915)


def bnoise(n):
    return brng.standard_normal(n)


def distant_burst(seconds, thump_hz, crack_cut, echoes, rumble_len, crackle=0.0):
    t = t_axis(seconds)
    n = len(t)
    # The crack: a short, broad burst, low-passed by distance.
    crack = lowpass(bnoise(n), crack_cut) * env(t, 0.0015, 0.018)
    crack += lowpass(bnoise(n), crack_cut * 0.45) * env(t, 0.004, 0.06) * 0.8
    # The thump: a falling low sine, felt more than heard.
    f = thump_hz * np.exp(-t * 5) + 32
    thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(t, 0.003, 0.22)
    x = crack * 1.0 + thump * 0.9
    # Slapback off the far shore and the castle: quieter, darker, later.
    for delay, gain, cut in echoes:
        d = int(delay * SR)
        e = lowpass(np.concatenate([np.zeros(d), crack[: n - d]]), cut)
        x += e * gain
    # The rolling rumble: very low noise, swelling slightly, then dying away.
    roll = lowpass(lowpass(bnoise(n), 140), 140)
    swell = (1 + 0.5 * np.sin(2 * np.pi * brng.uniform(0.6, 1.1) * t + brng.uniform(0, 6))) * 0.5
    x += roll * env(t, 0.06, rumble_len) * swell * 4.5
    # A few faint crackles riding the tail, for the glittery shells.
    if crackle > 0:
        k = 0.25
        while k < seconds - 0.3:
            i = int(k * SR)
            m = int(SR * 0.003)
            x[i:i + m] += lowpass(bnoise(m), 3500) * np.exp(-np.arange(m) / (SR * 0.0007)) * brng.uniform(0.2, 0.6) * crackle
            k += brng.exponential(0.03 + k * 0.02)
    return x


def burst_variant(big):
    if big:
        return distant_burst(
            seconds=brng.uniform(3.0, 3.6),
            thump_hz=brng.uniform(55, 75),
            crack_cut=brng.uniform(1800, 2600),
            echoes=[(brng.uniform(0.18, 0.28), 0.35, 1200), (brng.uniform(0.5, 0.7), 0.2, 800), (brng.uniform(0.95, 1.2), 0.1, 500)],
            rumble_len=brng.uniform(0.9, 1.3),
            crackle=brng.uniform(0.0, 0.5),
        )
    return distant_burst(
        seconds=brng.uniform(1.8, 2.2),
        thump_hz=brng.uniform(80, 100),
        crack_cut=brng.uniform(2200, 3200),
        echoes=[(brng.uniform(0.15, 0.22), 0.3, 1400), (brng.uniform(0.45, 0.6), 0.14, 900)],
        rumble_len=brng.uniform(0.45, 0.65),
    )


for i in range(1, 4):
    write(f"burst_big_{i}", burst_variant(True), 0.95)
for i in range(1, 3):
    write(f"burst_small_{i}", burst_variant(False), 0.8)

# The launch, heard from far off: a soft hollow mortar "pomp", no whistle.
t = t_axis(0.5)
pomp = np.sin(2 * np.pi * np.cumsum(140 * np.exp(-t * 9) + 60) / SR) * env(t, 0.004, 0.07)
pomp += lowpass(bnoise(len(t)), 500) * env(t, 0.002, 0.03) * 0.5
pomp = lowpass(pomp, 900)
write("mortar", pomp, 0.5)
