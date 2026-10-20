"""Synthesizes every sound in Little Bot, Big World: sound effects, ambience beds,
loops and the music tracks. Original, procedural, no samples.

Run:  python tools/audio/generate_audio.py
Needs numpy. Music/ambience/loops are encoded to OGG with ffmpeg if available
(otherwise written as WAV); short sound effects are WAV.
"""
import math
import os
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
MUSIC_DIR = os.path.join(ROOT, "assets", "audio", "music")
AMB_DIR = os.path.join(ROOT, "assets", "audio", "ambient")
RNG = np.random.default_rng(1234)


def find_ffmpeg():
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    base = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "WinGet", "Packages")
    if os.path.isdir(base):
        for root, _dirs, files in os.walk(base):
            if "ffmpeg.exe" in files:
                return os.path.join(root, "ffmpeg.exe")
    return None


FFMPEG = find_ffmpeg()

# ---------------------------------------------------------------------------------------
# DSP helpers
# ---------------------------------------------------------------------------------------


def secs(n):
    return int(n * SR)


def tt(d):
    return np.arange(secs(d)) / SR


def phase_from_freq(freq):
    return 2 * np.pi * np.cumsum(freq) / SR


def osc_sine(freq, d=None):
    if np.isscalar(freq):
        return np.sin(2 * np.pi * freq * tt(d))
    return np.sin(phase_from_freq(freq))


def glide(f0, f1, d, curve=1.0):
    x = np.linspace(0, 1, secs(d)) ** curve
    return f0 * (f1 / f0) ** x


def env_exp(n, attack=0.005, decay=0.3):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-4))


def env_adsr(n, a, d, s, r, hold=None):
    t = np.arange(n) / SR
    total = n / SR
    hold = total - r if hold is None else hold
    e = np.where(t < a, t / max(a, 1e-4), 0.0)
    dec = (t >= a) & (t < a + d)
    e = np.where(dec, 1 - (1 - s) * (t - a) / max(d, 1e-4), e)
    sus = (t >= a + d) & (t < hold)
    e = np.where(sus, s, e)
    rel = t >= hold
    e = np.where(rel, s * np.clip(1 - (t - hold) / max(r, 1e-4), 0, 1), e)
    return e


def noise(n):
    return RNG.uniform(-1, 1, n)


def spectral(x, fn):
    """Apply a frequency-domain gain curve fn(freqs) -> gains."""
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    spec *= fn(freqs)
    return np.fft.irfft(spec, len(x))


def bandpass(x, lo, hi, soft=1.0):
    def g(f):
        lo_g = 1 / (1 + (lo / np.maximum(f, 1)) ** (2 * soft)) if lo > 0 else 1
        hi_g = 1 / (1 + (f / hi) ** (2 * soft)) if hi > 0 else 1
        return lo_g * hi_g
    return spectral(x, g)


def lowpass(x, hi, soft=1.0):
    return bandpass(x, 0, hi, soft)


def highpass(x, lo, soft=1.0):
    return bandpass(x, lo, 0, soft)


def pink(n):
    return spectral(noise(n), lambda f: 1 / np.sqrt(np.maximum(f, 20)))


def brown(n):
    return spectral(noise(n), lambda f: 1 / np.maximum(f, 15))


def convolve(x, ir):
    n = len(x) + len(ir) - 1
    size = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:n]


_IR_CACHE = {}


def reverb_ir(decay, brightness=5000.0, stereo_seed=0):
    key = (decay, brightness, stereo_seed)
    if key not in _IR_CACHE:
        rng = np.random.default_rng(99 + stereo_seed)
        n = secs(decay * 1.2)
        t = np.arange(n) / SR
        ir = rng.uniform(-1, 1, n) * np.exp(-t * 6.9 / decay)
        ir = lowpass(ir, brightness)
        ir[: secs(0.012)] *= np.linspace(0, 1, secs(0.012))
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
        _IR_CACHE[key] = ir
    return _IR_CACHE[key]


def reverb(x, decay=1.8, wet=0.25, brightness=5000.0, seed=0):
    wet_sig = convolve(x, reverb_ir(decay, brightness, seed))
    out = np.zeros(len(wet_sig))
    out[: len(x)] += x * (1 - wet * 0.5)
    out += wet_sig * wet
    return out


def normalize(x, peak=0.9):
    m = np.max(np.abs(x)) + 1e-9
    return x * (peak / m)


def fade(x, fin=0.005, fout=0.02):
    x = x.copy()
    a, b = secs(fin), secs(fout)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def mix_into(buf, sig, at):
    i = secs(at)
    if i >= len(buf):
        return
    end = min(len(buf), i + len(sig))
    buf[i:end] += sig[: end - i]


def loopify(x, length):
    """Fold everything past `length` back onto the start for a seamless loop."""
    n = secs(length)
    out = x[:n].copy()
    tail = x[n:]
    k = 0
    while len(tail) > 0:
        seg = tail[:n]
        out[: len(seg)] += seg
        tail = tail[n:]
        k += 1
    return out


def stereo(left, right):
    n = max(len(left), len(right))
    l = np.zeros(n)
    r = np.zeros(n)
    l[: len(left)] = left
    r[: len(right)] = right
    return np.stack([l, r], axis=1)


def write_wav(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = np.clip(x, -1, 1)
    channels = 1 if data.ndim == 1 else data.shape[1]
    pcm = (data * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def write_ogg(path_no_ext, x, quality=5):
    if FFMPEG is None:
        write_wav(path_no_ext + ".wav", x)
        return path_no_ext + ".wav"
    tmp = os.path.join(tempfile.gettempdir(), "lbbw_audio_tmp.wav")
    write_wav(tmp, x)
    out = path_no_ext + ".ogg"
    subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(quality), out], check=True)
    os.remove(tmp)
    for stale in (path_no_ext + ".wav",):
        if os.path.exists(stale):
            os.remove(stale)
    return out


# ---------------------------------------------------------------------------------------
# Instruments
# ---------------------------------------------------------------------------------------


def note_freq(name_or_midi):
    if isinstance(name_or_midi, (int, float)):
        return 440.0 * 2 ** ((name_or_midi - 69) / 12)
    names = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
             "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}
    s = name_or_midi
    letter = s[:-1]
    octave = int(s[-1])
    midi = 12 * (octave + 1) + names[letter]
    return note_freq(midi)


def bell(f, d=2.5, ratio=3.5, index=2.2, decay=1.2, bright=1.0):
    n = secs(d)
    t = np.arange(n) / SR
    mod_env = np.exp(-t / (decay * 0.35)) * index * bright
    mod = np.sin(2 * np.pi * f * ratio * t) * mod_env
    car = np.sin(2 * np.pi * f * t + mod)
    return car * env_exp(n, 0.002, decay)


def marimba(f, d=1.6, decay=0.55):
    n = secs(d)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) * np.exp(-t / decay)
    s += 0.35 * np.sin(2 * np.pi * f * 3.93 * t) * np.exp(-t / (decay * 0.18))
    s += 0.12 * np.sin(2 * np.pi * f * 9.2 * t) * np.exp(-t / (decay * 0.06))
    return s * np.clip(t / 0.003, 0, 1)


def kalimba(f, d=2.0, decay=0.9):
    n = secs(d)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) * np.exp(-t / decay)
    s += 0.25 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t / (decay * 0.1))
    s += 0.1 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t / (decay * 0.5))
    return s * np.clip(t / 0.002, 0, 1)


def piano(f, d=3.0, decay=1.4):
    n = secs(d)
    t = np.arange(n) / SR
    s = np.zeros(n)
    for k, amp in enumerate([1.0, 0.45, 0.22, 0.12, 0.07, 0.04], start=1):
        inh = k * math.sqrt(1 + 0.0004 * k * k)
        s += amp * np.sin(2 * np.pi * f * inh * t) * np.exp(-t / (decay / (0.6 + 0.4 * k)))
    return s * np.clip(t / 0.004, 0, 1)


def pad(freqs, d, attack=1.8, release=2.5, detune=0.004, bright=0.5):
    n = secs(d + release)
    t = np.arange(n) / SR
    out_l = np.zeros(n)
    out_r = np.zeros(n)
    e = env_adsr(n, attack, 0.5, 0.85, release, hold=d)
    for f in freqs:
        for k, amp in [(1, 1.0), (2, 0.45 * bright), (3, 0.22 * bright), (4, 0.1 * bright)]:
            ph = RNG.uniform(0, 2 * np.pi)
            lfo = 1 + 0.0015 * np.sin(2 * np.pi * 0.17 * t + ph)
            out_l += amp * np.sin(2 * np.pi * f * k * (1 - detune) * t * lfo + ph)
            out_r += amp * np.sin(2 * np.pi * f * k * (1 + detune) * t * lfo + ph * 1.3)
    return out_l * e / len(freqs), out_r * e / len(freqs)


def soft_bass(f, d, attack=0.08):
    n = secs(d)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * f * 2 * t)
    return s * env_adsr(n, attack, 0.3, 0.7, min(0.6, d * 0.4))


# ---------------------------------------------------------------------------------------
# Sound effects
# ---------------------------------------------------------------------------------------


def sfx_collect():
    out = np.zeros(secs(1.4))
    for i, nm in enumerate(["E6", "G#6", "B6", "E7"]):
        mix_into(out, bell(note_freq(nm), 1.0, ratio=2.0, index=1.2, decay=0.35) * (0.8 - i * 0.12), i * 0.055)
    sh = bandpass(noise(secs(0.5)), 5000, 12000) * env_exp(secs(0.5), 0.01, 0.15) * 0.2
    mix_into(out, sh, 0.0)
    return normalize(reverb(out, 1.2, 0.3), 0.8)


def sfx_reveal():
    d = 1.4
    n = secs(d)
    sweep = bandpass(noise(n), 800, 6000) * env_adsr(n, 0.5, 0.2, 0.6, 0.6) * 0.5
    out = sweep
    for i, nm in enumerate(["A5", "C#6", "E6", "A6", "C#7"]):
        mix_into(out, bell(note_freq(nm), 1.0, ratio=3.0, index=1.0, decay=0.4) * 0.4, 0.25 + i * 0.07)
    return normalize(reverb(out, 1.6, 0.35), 0.75)


def sfx_interact():
    n = secs(0.18)
    click = bandpass(noise(secs(0.012)), 1500, 6000) * 0.6
    blip = osc_sine(glide(1300, 900, 0.12)) * env_exp(secs(0.12), 0.002, 0.04)
    out = np.zeros(n)
    mix_into(out, click, 0)
    mix_into(out, blip * 0.7, 0.005)
    return normalize(out, 0.6)


def sfx_denied():
    out = np.zeros(secs(0.45))
    for i, f in enumerate([420, 330]):
        n = secs(0.16)
        tone = np.sin(2 * np.pi * f * tt(0.16)) + 0.3 * np.sin(2 * np.pi * f * 3 * tt(0.16))
        mix_into(out, tone * env_exp(n, 0.005, 0.07) * 0.6, i * 0.14)
    return normalize(lowpass(out, 2500), 0.55)


def sfx_scan():
    d = 1.6
    n = secs(d)
    ping = bell(1760, d, ratio=1.5, index=0.6, decay=0.5) * 0.6
    t = np.arange(n) / SR
    whoosh = noise(n)
    # sweeping band-pass approximated by crossfading two filtered layers
    hi = bandpass(whoosh, 2500, 9000)
    lo = bandpass(whoosh, 300, 1500)
    k = np.clip(t / 0.9, 0, 1)
    sweep = (hi * (1 - k) + lo * k) * env_adsr(n, 0.05, 0.3, 0.4, 0.8) * 0.45
    sub = osc_sine(glide(220, 110, d)) * env_exp(n, 0.01, 0.4) * 0.3
    return normalize(reverb(ping + sweep + sub, 1.8, 0.35), 0.75)


def sfx_hop():
    d = 0.4
    n = secs(d)
    w = bandpass(noise(n), 400, 2500) * env_adsr(n, 0.05, 0.1, 0.4, 0.2) * 0.5
    tone = osc_sine(glide(260, 620, d, 0.7)) * env_exp(n, 0.01, 0.12) * 0.4
    return normalize(w + tone, 0.55)


def sfx_land():
    d = 0.3
    n = secs(d)
    thump = osc_sine(glide(140, 55, d)) * env_exp(n, 0.002, 0.08)
    click = lowpass(noise(n), 1200) * env_exp(n, 0.001, 0.02) * 0.5
    return normalize(thump + click, 0.6)


def sfx_bonk():
    d = 0.45
    n = secs(d)
    t = np.arange(n) / SR
    f = glide(330, 170, d)
    s = np.sin(phase_from_freq(f) + 1.8 * np.sin(phase_from_freq(f * 2.7)) * np.exp(-t / 0.08))
    return normalize(s * env_exp(n, 0.002, 0.14), 0.6)


def sfx_power_up():
    d = 2.2
    n = secs(d)
    t = np.arange(n) / SR
    f = glide(110, 440, 1.4, 1.6)
    f = np.concatenate([f, np.full(n - len(f), 440.0)])
    s = np.zeros(n)
    for k in range(1, 7):
        s += np.sin(phase_from_freq(f * k)) / k * np.clip(t * (2.0 / k), 0, 1)
    s *= env_adsr(n, 0.3, 0.4, 0.7, 0.6) * 0.5
    s = lowpass(s, 4000)
    for i, nm in enumerate(["A5", "E6", "A6"]):
        mix_into(s, bell(note_freq(nm), 1.4, decay=0.6) * 0.35, 1.25 + i * 0.08)
    return normalize(reverb(s, 2.0, 0.3), 0.8)


def clank(f=420, d=0.5):
    n = secs(d)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t + 2.5 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t / 0.05))
    s += 0.5 * np.sin(2 * np.pi * f * 1.51 * t) * np.exp(-t / 0.12)
    return s * env_exp(n, 0.001, 0.12)


def sfx_gate_open():
    d = 4.0
    n = secs(d)
    rumble = lowpass(brown(n), 180) * env_adsr(n, 0.4, 0.5, 0.8, 1.0) * 1.2
    grind = bandpass(noise(n), 300, 1400) * env_adsr(n, 0.5, 0.4, 0.5, 1.0) * 0.25
    grind *= 0.7 + 0.3 * np.sin(2 * np.pi * 7 * tt(d))
    out = rumble + grind
    for i in range(14):
        mix_into(out, clank(RNG.uniform(500, 900), 0.2) * 0.12, 0.3 + i * 0.22 + RNG.uniform(0, 0.05))
    mix_into(out, clank(260, 0.8) * 0.6, 0.05)
    mix_into(out, clank(210, 0.9) * 0.6, 3.4)
    return normalize(reverb(out, 1.6, 0.25), 0.85)


def sfx_valve():
    d = 1.5
    n = secs(d)
    t = np.arange(n) / SR
    squeak_f = 900 + 300 * np.sin(2 * np.pi * 1.6 * t)
    squeak = np.sin(phase_from_freq(squeak_f) + 0.8 * np.sin(phase_from_freq(squeak_f * 1.5)))
    squeak *= env_adsr(n, 0.1, 0.2, 0.5, 0.4) * (0.5 + 0.5 * np.sin(2 * np.pi * 3.1 * t) ** 2) * 0.3
    out = squeak
    for i in range(10):
        mix_into(out, bandpass(noise(secs(0.02)), 1000, 5000) * 0.5, 0.05 + i * 0.13)
    return normalize(reverb(out, 1.0, 0.2), 0.6)


def sfx_switch_on():
    d = 1.2
    n = secs(d)
    buzz = (np.sign(np.sin(2 * np.pi * 120 * tt(d))) * 0.3 + bandpass(noise(n), 2000, 6000) * 0.3)
    buzz = lowpass(buzz, 3000) * env_exp(n, 0.002, 0.08)
    out = buzz
    mix_into(out, bell(note_freq("E5"), 1.0, decay=0.5) * 0.5, 0.08)
    mix_into(out, bell(note_freq("B5"), 1.0, decay=0.5) * 0.35, 0.16)
    return normalize(reverb(out, 1.2, 0.25), 0.65)


def sfx_lever():
    out = np.zeros(secs(0.7))
    mix_into(out, lowpass(noise(secs(0.05)), 2000) * env_exp(secs(0.05), 0.001, 0.015), 0)
    mix_into(out, clank(180, 0.6) * 0.8, 0.02)
    return normalize(reverb(out, 0.9, 0.2), 0.65)


def sfx_bridge_extend():
    d = 4.5
    out = np.zeros(secs(d))
    for i in range(26):
        f = RNG.uniform(180, 320)
        n = secs(0.12)
        knock = np.sin(2 * np.pi * f * tt(0.12)) * env_exp(n, 0.001, 0.03)
        knock += lowpass(noise(n), 2500) * env_exp(n, 0.001, 0.01) * 0.6
        mix_into(out, knock * 0.6, 0.3 + i * 0.12)
    creak_n = secs(d)
    creak_f = 180 + 60 * np.sin(2 * np.pi * 0.7 * tt(d))
    creak = np.sin(phase_from_freq(creak_f) * 1.0 + 3 * np.sin(phase_from_freq(creak_f * 0.5))) * 0.08
    out += creak * env_adsr(creak_n, 0.5, 0.5, 0.6, 1.0)
    return normalize(reverb(out, 1.5, 0.3), 0.75)


def sfx_mirror_turn():
    d = 0.6
    n = secs(d)
    scrape = bandpass(noise(n), 600, 3000) * env_adsr(n, 0.05, 0.1, 0.6, 0.2) * 0.4
    out = scrape
    mix_into(out, bell(note_freq("D6"), 0.8, decay=0.3) * 0.3, 0.4)
    return normalize(reverb(out, 1.2, 0.25), 0.6)


def sfx_tile_turn():
    d = 0.5
    n = secs(d)
    grind = bandpass(noise(n), 200, 1500) * env_adsr(n, 0.02, 0.1, 0.5, 0.15) * 0.6
    thunk = osc_sine(glide(120, 70, 0.25)) * env_exp(secs(0.25), 0.002, 0.07)
    out = grind
    mix_into(out, thunk, 0.28)
    return normalize(out, 0.65)


def sfx_puzzle_solved():
    out = np.zeros(secs(2.6))
    for i, nm in enumerate(["C5", "E5", "G5", "C6", "E6"]):
        mix_into(out, bell(note_freq(nm), 2.0, ratio=2.0, index=1.0, decay=0.9) * 0.5, i * 0.11)
    l, r = pad([note_freq("C4"), note_freq("G4"), note_freq("E5")], 1.2, attack=0.3, release=1.0)
    mix_into(out, (l + r) * 0.25, 0.0)
    return normalize(reverb(out, 2.2, 0.35), 0.8)


def sfx_door_rumble():
    d = 5.5
    n = secs(d)
    rumble = lowpass(brown(n), 140) * env_adsr(n, 0.8, 0.5, 0.8, 1.5) * 1.3
    grind = bandpass(noise(n), 150, 900) * env_adsr(n, 1.0, 0.5, 0.6, 1.5) * 0.35
    grind *= 0.75 + 0.25 * np.sin(2 * np.pi * 3.0 * tt(d))
    return normalize(reverb(rumble + grind, 2.5, 0.3), 0.85)


def crystal_hum(freqs, d, beat=0.6):
    n = secs(d)
    t = np.arange(n) / SR
    s = np.zeros(n)
    for f in freqs:
        s += np.sin(2 * np.pi * f * t) * (1 + 0.3 * np.sin(2 * np.pi * beat * t))
        s += 0.4 * np.sin(2 * np.pi * f * 2.01 * t)
    return s / len(freqs)


def sfx_resonator():
    d = 3.0
    n = secs(d)
    hum = crystal_hum([note_freq("A4"), note_freq("E5")], d) * env_adsr(n, 0.8, 0.4, 0.7, 1.2) * 0.5
    out = hum
    for i, nm in enumerate(["A5", "E6", "A6", "C#7"]):
        mix_into(out, bell(note_freq(nm), 1.5, ratio=3.0, decay=0.7) * 0.25, 0.5 + i * 0.18)
    return normalize(reverb(out, 2.5, 0.4), 0.8)


def sfx_note(nm):
    f = note_freq(nm)
    s = bell(f, 2.4, ratio=2.0, index=1.4, decay=1.0) * 0.8 + crystal_hum([f], 2.4, 3.0) * env_exp(secs(2.4), 0.05, 0.9) * 0.25
    return normalize(reverb(s, 2.4, 0.4), 0.8)


def sfx_discovery():
    out = np.zeros(secs(3.0))
    l, r = pad([note_freq("D4"), note_freq("A4"), note_freq("F#5")], 1.6, attack=0.4, release=1.2)
    mix_into(out, (l + r) * 0.3, 0)
    for i, nm in enumerate(["A5", "D6", "F#6"]):
        mix_into(out, bell(note_freq(nm), 2.0, decay=0.9) * 0.4, 0.15 + i * 0.16)
    return normalize(reverb(out, 2.4, 0.35), 0.75)


def sfx_objective():
    out = np.zeros(secs(1.4))
    mix_into(out, bell(note_freq("G5"), 1.2, decay=0.5) * 0.5, 0)
    mix_into(out, bell(note_freq("D6"), 1.2, decay=0.6) * 0.5, 0.13)
    return normalize(reverb(out, 1.6, 0.3), 0.6)


def sfx_area_enter():
    d = 2.2
    n = secs(d)
    w = bandpass(noise(n), 400, 4000) * env_adsr(n, 0.6, 0.3, 0.4, 1.0) * 0.4
    out = w
    mix_into(out, bell(note_freq("E5"), 1.8, decay=1.0) * 0.4, 0.5)
    mix_into(out, bell(note_freq("B5"), 1.8, decay=1.0) * 0.3, 0.7)
    return normalize(reverb(out, 2.4, 0.4), 0.6)


def sfx_restore():
    d = 5.0
    out = np.zeros(secs(d + 2))
    l, r = pad([note_freq("D3"), note_freq("A3"), note_freq("F#4"), note_freq("A4")], d - 1.5, attack=1.5, release=2.0)
    mix_into(out, (l + r) * 0.5, 0)
    n = secs(d)
    shimmer = bandpass(noise(n), 4000, 12000) * env_adsr(n, 2.0, 0.5, 0.6, 2.0) * 0.12
    mix_into(out, shimmer, 0)
    for i, nm in enumerate(["D5", "F#5", "A5", "D6", "F#6", "A6"]):
        mix_into(out, bell(note_freq(nm), 2.4, decay=1.1) * 0.3, 1.2 + i * 0.22)
    return normalize(reverb(out, 3.0, 0.4), 0.85)


def sfx_core_awaken():
    d = 7.0
    n = secs(d)
    t = np.arange(n) / SR
    f = glide(55, 110, d, 0.8)
    hum = np.zeros(n)
    for k, a in [(1, 1.0), (2, 0.5), (3, 0.3), (5, 0.15)]:
        hum += a * np.sin(phase_from_freq(f * k))
    hum *= np.clip(t / 4.0, 0, 1) * 0.5
    boom_at = 3.4
    boom = osc_sine(glide(90, 35, 2.5)) * env_exp(secs(2.5), 0.005, 0.8) * 1.2
    out = hum
    mix_into(out, boom, boom_at)
    mix_into(out, lowpass(noise(secs(1.5)), 600) * env_exp(secs(1.5), 0.01, 0.4) * 0.8, boom_at)
    for i, nm in enumerate(["A4", "E5", "A5", "C#6", "E6", "A6"]):
        mix_into(out, bell(note_freq(nm), 3.0, decay=1.4) * 0.3, boom_at + 0.1 + i * 0.15)
    return normalize(reverb(out, 3.5, 0.45), 0.9)


def sfx_heart_restore():
    d = 9.0
    out = np.zeros(secs(d + 3))
    chords = [["C3", "G3", "E4", "G4"], ["A2", "E3", "C4", "E4"], ["F2", "C3", "A3", "F4"], ["G2", "D3", "B3", "G4"]]
    for i, ch in enumerate(chords):
        l, r = pad([note_freq(x) for x in ch], 2.6, attack=1.0, release=2.2, bright=0.7)
        mix_into(out, (l + r) * 0.4, i * 2.2)
    for i in range(16):
        nm = ["C6", "E6", "G6", "B6", "D7"][i % 5]
        mix_into(out, bell(note_freq(nm), 2.0, decay=0.9) * 0.18, 1.0 + i * 0.35)
    boom = osc_sine(glide(70, 30, 3.0)) * env_exp(secs(3.0), 0.01, 1.0)
    mix_into(out, boom, 0.0)
    return normalize(reverb(out, 4.0, 0.45), 0.9)


def chirp(f0, f1, d, vib=0.0):
    n = secs(d)
    f = glide(f0, f1, d)
    if vib:
        f = f * (1 + vib * np.sin(2 * np.pi * 28 * tt(d)))
    return np.sin(phase_from_freq(f)) * env_adsr(n, 0.01, 0.02, 0.8, d * 0.3)


def sfx_boot_up():
    out = np.zeros(secs(2.8))
    seq = [(400, 900, 0.18), (900, 600, 0.12), (700, 1400, 0.2), (1200, 1100, 0.08), (1300, 1250, 0.08), (1500, 2000, 0.25)]
    at = 0.2
    for f0, f1, d in seq:
        mix_into(out, chirp(f0, f1, d, 0.02) * 0.4, at)
        at += d + 0.05
    for i in range(10):
        mix_into(out, osc_sine(RNG.uniform(1800, 3200), 0.03) * env_exp(secs(0.03), 0.001, 0.01) * 0.2, 0.1 + i * 0.09)
    mix_into(out, bell(note_freq("C6"), 1.2, decay=0.5) * 0.4, at + 0.05)
    mix_into(out, bell(note_freq("G6"), 1.2, decay=0.5) * 0.35, at + 0.15)
    return normalize(reverb(out, 1.2, 0.2), 0.7)


def sfx_robot_chirp():
    out = np.zeros(secs(0.8))
    seq = [(1200, 1800, 0.08), (1600, 1100, 0.07), (1400, 2200, 0.12)]
    at = 0.0
    for f0, f1, d in seq:
        mix_into(out, chirp(f0, f1, d, 0.03) * 0.5, at)
        at += d + 0.03
    return normalize(reverb(out, 0.8, 0.15), 0.6)


def sfx_splash():
    d = 1.0
    n = secs(d)
    burst = bandpass(noise(n), 500, 6000) * env_exp(n, 0.005, 0.18) * 0.7
    out = burst
    for i in range(12):
        f0 = RNG.uniform(500, 1200)
        b = osc_sine(glide(f0, f0 * 1.8, 0.06)) * env_exp(secs(0.06), 0.002, 0.02) * 0.25
        mix_into(out, b, 0.05 + RNG.uniform(0, 0.6))
    return normalize(reverb(out, 1.0, 0.2), 0.7)


def sfx_ui(kind):
    if kind == "move":
        s = osc_sine(2100, 0.05) * env_exp(secs(0.05), 0.001, 0.012)
        return normalize(s, 0.35)
    if kind == "confirm":
        out = np.zeros(secs(0.25))
        mix_into(out, osc_sine(1100, 0.08) * env_exp(secs(0.08), 0.002, 0.03), 0)
        mix_into(out, osc_sine(1650, 0.12) * env_exp(secs(0.12), 0.002, 0.05), 0.05)
        return normalize(out, 0.45)
    if kind == "back":
        out = np.zeros(secs(0.25))
        mix_into(out, osc_sine(1400, 0.08) * env_exp(secs(0.08), 0.002, 0.03), 0)
        mix_into(out, osc_sine(950, 0.12) * env_exp(secs(0.12), 0.002, 0.05), 0.05)
        return normalize(out, 0.4)
    d = 0.6
    n = secs(d)
    w = bandpass(noise(n), 1500, 7000) * env_adsr(n, 0.1, 0.1, 0.3, 0.3) * 0.3
    out = w
    mix_into(out, bell(note_freq("A6"), 0.6, decay=0.25) * 0.3, 0.08)
    return normalize(reverb(out, 1.0, 0.2), 0.45)


# ---------------------------------------------------------------------------------------
# Loops and ambience
# ---------------------------------------------------------------------------------------


def loop_hover():
    d = 4.0
    t = tt(d)
    s = 0.6 * np.sin(2 * np.pi * 150 * t) + 0.3 * np.sin(2 * np.pi * 300 * t) + 0.12 * np.sin(2 * np.pi * 450.5 * t)
    s *= 1 + 0.15 * np.sin(2 * np.pi * 0.5 * t)
    s += lowpass(noise(len(t)), 900) * 0.12
    return normalize(s, 0.5)


def loop_machine():
    d = 4.0
    t = tt(d)
    s = np.sin(2 * np.pi * 55 * t) + 0.5 * np.sin(2 * np.pi * 110 * t) + 0.25 * np.sin(2 * np.pi * 165 * t)
    s *= 1 + 0.2 * np.sin(2 * np.pi * 0.75 * t)
    s += bandpass(noise(len(t)), 2000, 5000) * 0.03
    return normalize(s, 0.5)


def loop_waterfall():
    d = 8.0
    n = secs(d)
    s = pink(n) * 0.6 + bandpass(noise(n), 800, 8000) * 0.4
    s *= 0.85 + 0.15 * np.sin(2 * np.pi * 0.25 * tt(d))
    return normalize(lowpass(s, 9000), 0.6)


def loop_water_lap():
    d = 8.0
    out = lowpass(brown(secs(d)), 400) * 0.2
    for i in range(16):
        at = i * 0.5 + RNG.uniform(0, 0.2)
        n = secs(0.6)
        lap = bandpass(noise(n), 300, 2000) * env_adsr(n, 0.15, 0.1, 0.4, 0.3) * 0.3
        mix_into(out, lap, at)
    return normalize(loopify(np.concatenate([out, np.zeros(secs(1))]), d), 0.5)


def loop_stream():
    d = 8.0
    out = bandpass(pink(secs(d + 1)), 300, 7000) * 0.5
    for i in range(140):
        f0 = RNG.uniform(400, 1400)
        b = osc_sine(glide(f0, f0 * RNG.uniform(1.3, 2.2), 0.05)) * env_exp(secs(0.05), 0.002, 0.015) * RNG.uniform(0.05, 0.2)
        mix_into(out, b, RNG.uniform(0, d))
    return normalize(loopify(out, d), 0.55)


def wind_bed(d, low=150, high=1200, gust_rate=0.07, level=0.5, seed_shift=0.0):
    n = secs(d)
    t = tt(d)
    base = bandpass(pink(n), low, high) * level
    gust = 0.6 + 0.4 * np.sin(2 * np.pi * gust_rate * t + seed_shift) * np.sin(2 * np.pi * gust_rate * 0.37 * t + 1.0 + seed_shift)
    whistle = bandpass(noise(n), high * 0.8, high * 1.6) * 0.06 * np.clip(gust - 0.7, 0, 1) * 3
    return base * gust + whistle


def bird_call(kind):
    if kind == 0:
        out = np.zeros(secs(0.8))
        for i in range(RNG.integers(2, 5)):
            f0 = RNG.uniform(2800, 3600)
            mix_into(out, chirp(f0, f0 * RNG.uniform(1.1, 1.4), 0.07, 0.02) * 0.5, i * 0.11)
        return out
    if kind == 1:
        f0 = RNG.uniform(1800, 2400)
        a = chirp(f0, f0 * 1.6, 0.25, 0.01)
        b = chirp(f0 * 1.5, f0 * 0.9, 0.3, 0.01)
        return np.concatenate([a, np.zeros(secs(0.05)), b]) * 0.5
    f0 = RNG.uniform(3500, 4500)
    out = np.zeros(secs(1.0))
    for i in range(8):
        mix_into(out, chirp(f0, f0 * 0.85, 0.04) * 0.35, i * 0.06)
    return out


def crickets(d, rate=4.5, f=4800, level=0.08):
    n = secs(d)
    t = tt(d)
    carrier = np.sin(2 * np.pi * f * t)
    pulse = (np.sin(2 * np.pi * 45 * t) > 0.3).astype(float)
    chirp_env = (np.sin(2 * np.pi * rate * t) > 0.2).astype(float)
    return lowpass(carrier * pulse * chirp_env, 9000) * level


def amb_meadow_base():
    d = 40.0
    w = wind_bed(d + 2, 120, 900, 0.06, 0.55)
    l = w
    r = np.roll(w, secs(0.03)) * 0.95
    return stereo(normalize(loopify(l, d), 0.5), normalize(loopify(r, d), 0.5))


def amb_meadow_life():
    d = 40.0
    l = np.zeros(secs(d + 3))
    r = np.zeros(secs(d + 3))
    for i in range(46):
        call = bird_call(int(RNG.integers(0, 3))) * RNG.uniform(0.15, 0.5)
        pan = RNG.uniform(0, 1)
        at = RNG.uniform(0, d)
        mix_into(l, call * (1 - pan), at)
        mix_into(r, call * pan, at)
    bees = osc_sine(220 + 8 * np.sin(2 * np.pi * 0.3 * tt(d + 3))) * 0.015
    l += bees
    r += bees
    l = reverb(l, 1.6, 0.3)[: len(l)]
    r = reverb(r, 1.6, 0.3, seed=1)[: len(r)]
    return stereo(normalize(loopify(l, d), 0.45), normalize(loopify(r, d), 0.45))


def amb_forest_base():
    d = 40.0
    w = wind_bed(d + 3, 80, 500, 0.04, 0.5, 2.0)
    drops = np.zeros(secs(d + 3))
    for i in range(60):
        f0 = RNG.uniform(900, 1800)
        drop = osc_sine(glide(f0, f0 * 0.55, 0.08)) * env_exp(secs(0.08), 0.001, 0.03) * RNG.uniform(0.05, 0.2)
        mix_into(drops, drop, RNG.uniform(0, d))
    drops = reverb(drops, 2.5, 0.5)[: len(drops)]
    creaks = np.zeros(secs(d + 3))
    for i in range(5):
        cn = secs(1.5)
        cf = RNG.uniform(90, 160) * (1 + 0.2 * np.sin(2 * np.pi * 0.8 * tt(1.5)))
        c = np.sin(phase_from_freq(cf) + 2 * np.sin(phase_from_freq(cf * 0.5))) * env_adsr(cn, 0.4, 0.3, 0.5, 0.5) * 0.04
        mix_into(creaks, c, RNG.uniform(0, d))
    l = w + drops + creaks
    r = np.roll(w, secs(0.05)) + np.roll(drops, secs(0.3)) + creaks * 0.7
    return stereo(normalize(loopify(l, d), 0.45), normalize(loopify(r, d), 0.45))


def amb_forest_life():
    d = 40.0
    c1 = crickets(d + 2, 3.2, 4300, 0.06)
    c2 = crickets(d + 2, 4.1, 5200, 0.05)
    frogs = np.zeros(secs(d + 2))
    for i in range(24):
        n = secs(0.18)
        f = RNG.uniform(260, 420)
        ribbit = np.sin(2 * np.pi * f * tt(0.18) + 3 * np.sin(2 * np.pi * f * 0.5 * tt(0.18))) * env_exp(n, 0.01, 0.06)
        mix_into(frogs, ribbit * 0.15, RNG.uniform(0, d))
        mix_into(frogs, ribbit * 0.1, RNG.uniform(0, d))
    frogs = reverb(frogs, 1.8, 0.4)[: len(frogs)]
    l = c1 + frogs * 0.8
    r = c2 + frogs
    return stereo(normalize(loopify(l, d), 0.4), normalize(loopify(r, d), 0.4))


def amb_shrine_base():
    d = 40.0
    w = wind_bed(d + 3, 300, 2200, 0.05, 0.4, 4.0)
    hum = crystal_hum([note_freq("D3")], d + 3, 0.1) * 0.05
    l = w + hum
    r = np.roll(w, secs(0.04)) + hum
    return stereo(normalize(loopify(l, d), 0.42), normalize(loopify(r, d), 0.42))


def amb_shrine_life():
    d = 40.0
    l = np.zeros(secs(d + 4))
    r = np.zeros(secs(d + 4))
    scale = ["D5", "E5", "F#5", "A5", "B5", "D6", "E6"]
    for i in range(40):
        nm = scale[int(RNG.integers(0, len(scale)))]
        ch = bell(note_freq(nm), 2.5, ratio=3.5, decay=1.2) * RNG.uniform(0.05, 0.18)
        pan = RNG.uniform(0.2, 0.8)
        at = RNG.uniform(0, d)
        mix_into(l, ch * (1 - pan), at)
        mix_into(r, ch * pan, at)
    birds = np.zeros(secs(d + 4))
    for i in range(14):
        mix_into(birds, bird_call(1) * 0.2, RNG.uniform(0, d))
    l = reverb(l + birds * 0.6, 2.5, 0.4)[: len(l)]
    r = reverb(r + birds * 0.4, 2.5, 0.4, seed=1)[: len(r)]
    return stereo(normalize(loopify(l, d), 0.4), normalize(loopify(r, d), 0.4))


def amb_garden_base():
    d = 40.0
    n = secs(d + 3)
    air = bandpass(pink(n), 1500, 9000) * 0.25 * (0.8 + 0.2 * np.sin(2 * np.pi * 0.05 * tt(d + 3)))
    hum = crystal_hum([note_freq("F3"), note_freq("C4")], d + 3, 0.07) * 0.05
    l = air + hum
    r = np.roll(air, secs(0.05)) + hum
    return stereo(normalize(loopify(l, d), 0.38), normalize(loopify(r, d), 0.38))


def amb_garden_life():
    d = 40.0
    l = np.zeros(secs(d + 4))
    r = np.zeros(secs(d + 4))
    scale = ["F5", "G5", "A5", "B5", "C6", "E6", "F6", "A6"]
    for i in range(70):
        nm = scale[int(RNG.integers(0, len(scale)))]
        ch = bell(note_freq(nm), 2.0, ratio=1.41, index=1.5, decay=0.9) * RNG.uniform(0.04, 0.14)
        pan = RNG.uniform(0, 1)
        at = RNG.uniform(0, d)
        mix_into(l, ch * (1 - pan), at)
        mix_into(r, ch * pan, at)
    l = reverb(l, 3.0, 0.5)[: len(l)]
    r = reverb(r, 3.0, 0.5, seed=1)[: len(r)]
    return stereo(normalize(loopify(l, d), 0.4), normalize(loopify(r, d), 0.4))


# ---------------------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------------------


def chord_midis(root_name, quality):
    root = round(69 + 12 * math.log2(note_freq(root_name) / 440))
    shapes = {"maj": [0, 4, 7], "min": [0, 3, 7], "maj7": [0, 4, 7, 11], "min7": [0, 3, 7, 10], "add9": [0, 4, 7, 14],
              "sus2": [0, 2, 7], "6": [0, 4, 7, 9], "min9": [0, 3, 7, 14], "lyd": [0, 4, 6, 11]}
    return [root + i for i in shapes[quality]]


def compose(name, bpm, progression, scale, lead, seconds_per_chord_bars=2, repeats=3, seed=1,
            lead_density=0.45, lead_octave=0, pad_level=0.5, bass=True, bright=0.5, arp=None, reverb_decay=3.2,
            swell=False):
    rng = np.random.default_rng(seed)
    beat = 60.0 / bpm
    bar = beat * 4
    chord_len = bar * seconds_per_chord_bars
    total = chord_len * len(progression) * repeats
    tail = 7.0
    L = np.zeros(secs(total + tail))
    R = np.zeros(secs(total + tail))
    for rep in range(repeats):
        for ci, (root, quality) in enumerate(progression):
            start = (rep * len(progression) + ci) * chord_len
            midis = chord_midis(root, quality)
            freqs = [note_freq(m) for m in midis]
            lvl = pad_level * (0.7 + 0.3 * (rep / max(repeats - 1, 1)) if swell else 1.0)
            l, r = pad(freqs, chord_len, attack=chord_len * 0.35, release=chord_len * 0.5, bright=bright)
            mix_into(L, l * lvl, start)
            mix_into(R, r * lvl, start)
            if bass:
                b = soft_bass(note_freq(midis[0] - 12), chord_len * 0.95) * 0.32
                mix_into(L, b, start)
                mix_into(R, b, start)
            if arp:
                steps = int(chord_len / (beat * arp["step"]))
                pattern = arp["pattern"]
                for s in range(steps):
                    m = midis[pattern[s % len(pattern)] % len(midis)] + 12 * (arp.get("octave", 1) + pattern[s % len(pattern)] // len(midis))
                    note = arp["inst"](note_freq(m)) * arp["level"]
                    pan = 0.5 + 0.35 * math.sin(s * 0.9)
                    t0 = start + s * beat * arp["step"]
                    mix_into(L, note * (1 - pan), t0)
                    mix_into(R, note * pan, t0)
            # Lead: a gentle random walk over the scale, favouring chord tones.
            if rep > 0 or len(progression) * repeats <= 4:
                t_pos = 0.0
                last = scale[len(scale) // 2]
                while t_pos < chord_len - beat * 0.5:
                    dur = rng.choice([1, 1, 2, 2, 3, 4]) * beat * 0.5
                    if rng.random() < lead_density:
                        step = int(rng.choice([-2, -1, -1, 0, 1, 1, 2]))
                        idx = min(max(scale.index(last) + step, 0), len(scale) - 1)
                        cand = scale[idx]
                        if rng.random() < 0.5:
                            chord_tones = [s for s in scale if (s - midis[0]) % 12 in [(m - midis[0]) % 12 for m in midis]]
                            if chord_tones:
                                cand = min(chord_tones, key=lambda s: abs(s - cand))
                        last = cand
                        f = note_freq(cand + 12 * lead_octave)
                        note = lead(f) * 0.42
                        pan = 0.5 + rng.uniform(-0.25, 0.25)
                        mix_into(L, note * (1 - pan), start + t_pos)
                        mix_into(R, note * pan, start + t_pos)
                    t_pos += dur
    L = reverb(L, reverb_decay, 0.4, seed=0)
    R = reverb(R, reverb_decay, 0.4, seed=1)
    L = loopify(L, total)
    R = loopify(R, total)
    peak = max(np.max(np.abs(L)), np.max(np.abs(R))) + 1e-9
    return stereo(L / peak * 0.75, R / peak * 0.75)


def scale_midis(root_name, intervals, octaves=2):
    root = round(69 + 12 * math.log2(note_freq(root_name) / 440))
    out = []
    for o in range(octaves):
        for i in intervals:
            out.append(root + 12 * o + i)
    out.append(root + 12 * octaves)
    return out


PENTA = [0, 2, 4, 7, 9]
DORIAN = [0, 2, 3, 5, 7, 9, 10]
MIXO = [0, 2, 4, 5, 7, 9, 10]
LYDIAN = [0, 2, 4, 6, 7, 9, 11]
MAJOR = [0, 2, 4, 5, 7, 9, 11]


def music_all():
    tracks = {}
    tracks["menu"] = compose("menu", 66, [("C3", "maj7"), ("A2", "min7"), ("F2", "maj7"), ("G2", "6")],
                             scale_midis("C5", PENTA), lambda f: piano(f, 3.0, 1.6), repeats=2, seed=3,
                             lead_density=0.35, pad_level=0.45)
    tracks["meadow"] = compose("meadow", 76, [("D3", "add9"), ("B2", "min7"), ("G2", "maj7"), ("A2", "sus2")],
                               scale_midis("D5", PENTA), lambda f: marimba(f, 1.6, 0.5), repeats=3, seed=5,
                               lead_density=0.5, pad_level=0.42,
                               arp={"step": 1.0, "pattern": [0, 2, 1, 2], "inst": lambda f: kalimba(f, 1.4, 0.5), "level": 0.12, "octave": 1})
    tracks["forest"] = compose("forest", 62, [("A2", "min9"), ("G2", "6"), ("F2", "maj7"), ("E2", "min7")],
                               scale_midis("A4", DORIAN), lambda f: kalimba(f, 2.2, 1.0), repeats=3, seed=7,
                               lead_density=0.3, pad_level=0.5, bright=0.3, reverb_decay=4.0)
    tracks["shrine"] = compose("shrine", 64, [("D3", "sus2"), ("C3", "maj"), ("G2", "add9"), ("D3", "maj")],
                               scale_midis("D5", MIXO), lambda f: bell(f, 2.6, ratio=2.0, index=1.2, decay=1.2), repeats=3, seed=9,
                               lead_density=0.32, pad_level=0.48, bright=0.45, reverb_decay=4.2)
    tracks["garden"] = compose("garden", 70, [("F2", "lyd"), ("G2", "6"), ("E2", "min7"), ("A2", "min9")],
                               scale_midis("F5", LYDIAN), lambda f: bell(f, 2.2, ratio=1.41, index=1.6, decay=1.0), repeats=3, seed=11,
                               lead_density=0.38, pad_level=0.44, bright=0.6, reverb_decay=4.5,
                               arp={"step": 0.5, "pattern": [0, 1, 2, 3, 2, 1], "inst": lambda f: bell(f, 1.0, ratio=3.0, index=0.8, decay=0.35), "level": 0.07, "octave": 2})
    tracks["finale"] = compose("finale", 72, [("C3", "add9"), ("G2", "maj"), ("A2", "min7"), ("F2", "maj7"), ("C3", "maj"), ("D3", "min7"), ("G2", "sus2"), ("G2", "maj")],
                               scale_midis("C5", MAJOR), lambda f: piano(f, 3.2, 1.6), seconds_per_chord_bars=1, repeats=3, seed=13,
                               lead_density=0.55, pad_level=0.55, bright=0.7, reverb_decay=3.6, swell=True,
                               arp={"step": 0.5, "pattern": [0, 1, 2, 1], "inst": lambda f: marimba(f, 1.2, 0.4), "level": 0.08, "octave": 1})
    return tracks


# ---------------------------------------------------------------------------------------


def main():
    os.makedirs(SFX_DIR, exist_ok=True)
    os.makedirs(MUSIC_DIR, exist_ok=True)
    os.makedirs(AMB_DIR, exist_ok=True)
    sfx = {
        "collect": sfx_collect, "reveal": sfx_reveal, "interact": sfx_interact, "denied": sfx_denied,
        "scan": sfx_scan, "hop": sfx_hop, "land": sfx_land, "bonk": sfx_bonk, "power_up": sfx_power_up,
        "gate_open": sfx_gate_open, "valve": sfx_valve, "switch_on": sfx_switch_on, "lever": sfx_lever,
        "bridge_extend": sfx_bridge_extend, "mirror_turn": sfx_mirror_turn, "tile_turn": sfx_tile_turn,
        "puzzle_solved": sfx_puzzle_solved, "door_rumble": sfx_door_rumble, "resonator": sfx_resonator,
        "note_low": lambda: sfx_note("A4"), "note_mid": lambda: sfx_note("C#5"), "note_high": lambda: sfx_note("E5"),
        "discovery": sfx_discovery, "objective": sfx_objective, "area_enter": sfx_area_enter, "restore": sfx_restore,
        "core_awaken": sfx_core_awaken, "heart_restore": sfx_heart_restore, "boot_up": sfx_boot_up,
        "robot_chirp": sfx_robot_chirp, "splash": sfx_splash,
        "ui_move": lambda: sfx_ui("move"), "ui_confirm": lambda: sfx_ui("confirm"), "ui_back": lambda: sfx_ui("back"),
        "ui_open": lambda: sfx_ui("open"),
    }
    for name, fn in sfx.items():
        write_wav(os.path.join(SFX_DIR, name + ".wav"), fade(fn()))
        print("sfx", name)
    loops = {"hover_loop": loop_hover, "machine_hum": loop_machine, "waterfall": loop_waterfall,
             "water_lap": loop_water_lap, "stream": loop_stream}
    for name, fn in loops.items():
        write_ogg(os.path.join(AMB_DIR, name), fn(), 4)
        print("loop", name)
    beds = {"meadow_base": amb_meadow_base, "meadow_life": amb_meadow_life, "forest_base": amb_forest_base,
            "forest_life": amb_forest_life, "shrine_base": amb_shrine_base, "shrine_life": amb_shrine_life,
            "garden_base": amb_garden_base, "garden_life": amb_garden_life}
    for name, fn in beds.items():
        write_ogg(os.path.join(AMB_DIR, name), fn(), 4)
        print("ambience", name)
    for name, data in music_all().items():
        write_ogg(os.path.join(MUSIC_DIR, name), data, 5)
        print("music", name, round(len(data) / SR, 1), "s")
    print("ffmpeg:", FFMPEG)


if __name__ == "__main__":
    main()
