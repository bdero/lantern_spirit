"""Scores every wav for how much of it is noise rather than tone.

    python3 tool/audit_sounds.py assets/sfx

Per file, over its loud frames: spectral flatness (1 = white noise, near 0
= pure tones), the share of energy above 4 kHz (hiss), and the spectral
centroid. Prints a table sorted noisiest first.
"""
import glob, sys, wave
import numpy as np

def load(p):
    w = wave.open(p)
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768
    return x, w.getframerate()

rows = []
for p in sorted(glob.glob(sys.argv[1] + '/*.wav')):
    x, sr = load(p)
    n = 2048
    hop = 512
    if len(x) < n:
        x = np.pad(x, (0, n - len(x)))
    win = np.hanning(n)
    frames = [x[i:i + n] * win for i in range(0, len(x) - n + 1, hop)]
    specs = np.abs(np.fft.rfft(frames, axis=1)) ** 2
    energy = specs.sum(axis=1)
    loud = energy > energy.max() * 0.05
    S = specs[loud] + 1e-12
    freqs = np.fft.rfftfreq(n, 1 / sr)
    band = (freqs > 100) & (freqs < 12000)
    flat = np.exp(np.mean(np.log(S[:, band]), axis=1)) / np.mean(S[:, band], axis=1)
    hiss = S[:, freqs > 4000].sum(axis=1) / S.sum(axis=1)
    cent = (S * freqs).sum(axis=1) / S.sum(axis=1)
    # Tonality: the share of each frame's energy in its strongest 3% of
    # bins. Tones pile into a few bins; noise spreads across all of them.
    k = max(1, int(S.shape[1] * 0.03))
    top = np.sort(S, axis=1)[:, -k:].sum(axis=1)
    tonal = top / S.sum(axis=1)
    # Weight by each frame's energy.
    wgt = energy[loud] / energy[loud].sum()
    # Noise floor: how far the median bin sits below the strongest, in dB,
    # between 1 and 10 kHz where hiss is heard. Tones leave the median far
    # down (-60 dB or lower); a bed of noise lifts it, even a quiet one.
    hear = (freqs > 1000) & (freqs < 10000)
    db = 10 * np.log10(S)
    floor = np.median(db[:, hear], axis=1) - db.max(axis=1)
    # Noise share: the energy-weighted share of frames' energy outside their
    # tonal peaks, over the whole sound (quiet noisy tails count too).
    rows.append((p.split('/')[-1][:-4], float((flat * wgt).sum()), float((hiss * wgt).sum()), float((cent * wgt).sum()), float(1 - (tonal * wgt).sum()), float((floor * wgt).sum())))

rows.sort(key=lambda r: -r[5])
print(f"{'sound':16s} {'floor':>7s} {'noise':>6s} {'flat':>6s} {'hiss>4k':>8s}  verdict")
for name, flat, hiss, cent, noise, floor in rows:
    noisy = floor > -50 or noise > 0.35 or flat > 0.12 or hiss > 0.25
    print(f"{name:16s} {floor:6.0f}dB {noise:6.2f} {flat:6.3f} {hiss:8.2f}  {'NOISY' if noisy else ''}")
