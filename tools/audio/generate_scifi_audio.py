"""Synthesizes the sounds for the three sci-fi areas (research facility, alien reactor,
quantum lab). Reuses the synthesis helpers from generate_audio.py without regenerating any
existing sound, so the original areas' audio stays byte-for-byte unchanged.

Run:  python tools/audio/generate_scifi_audio.py
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import generate_audio as ga  # noqa: E402

SR = ga.SR
RNG = np.random.default_rng(777)
secs, tt, glide, env_exp, env_adsr = ga.secs, ga.tt, ga.glide, ga.env_exp, ga.env_adsr
bandpass, lowpass, highpass, normalize, fade, mix_into = ga.bandpass, ga.lowpass, ga.highpass, ga.normalize, ga.fade, ga.mix_into
reverb, loopify, stereo, note_freq, bell, pad = ga.reverb, ga.loopify, ga.stereo, ga.note_freq, ga.bell, ga.pad


def noise(n):
    return RNG.uniform(-1, 1, n)


def pink(n):
    return ga.spectral(noise(n), lambda f: 1 / np.sqrt(np.maximum(f, 20)))


def brown(n):
    return ga.spectral(noise(n), lambda f: 1 / np.maximum(f, 15))


def saw(freq, d):
    ph = np.cumsum(np.full(secs(d), freq) if np.isscalar(freq) else freq) / SR
    return 2 * (ph % 1.0) - 1


def square(freq, d, duty=0.5):
    ph = np.cumsum(np.full(secs(d), freq) if np.isscalar(freq) else freq) / SR
    return np.where((ph % 1.0) < duty, 1.0, -1.0)


# --- Sound effects ---------------------------------------------------------------------

def sfx_terminal_beep():
    out = np.zeros(secs(0.35))
    for i, f in enumerate([1320, 1760]):
        n = secs(0.09)
        s = np.sin(2 * np.pi * f * tt(0.09)) * env_adsr(n, 0.003, 0.02, 0.6, 0.03)
        mix_into(out, s * 0.5, i * 0.1)
    return reverb(out, 0.4, 0.15)


def sfx_power_restore():
    d = 3.2
    n = secs(d)
    f = glide(60, 420, d, 0.6)
    s = saw(f, d) * 0.25 + np.sin(2 * np.pi * np.cumsum(f * 2) / SR) * 0.3
    s = lowpass(s, 2400) * env_adsr(n, 0.2, 0.5, 0.8, 0.9)
    thunk = brown(secs(0.6)) * env_exp(secs(0.6), 0.002, 0.15) * 0.9
    out = np.zeros(n + secs(0.5))
    mix_into(out, thunk, 0.0)
    mix_into(out, s, 0.05)
    for i, k in enumerate([0, 4, 7, 12]):
        mix_into(out, bell(note_freq(60 + k + 12), 1.4, 2.0, 0.6, 0.6) * 0.18, 2.0 + i * 0.12)
    return reverb(out, 1.6, 0.3)


def sfx_error_buzz():
    d = 0.6
    n = secs(d)
    s = square(110, d, 0.4) * 0.35 + square(116, d, 0.5) * 0.25
    s = lowpass(s, 1800) * env_adsr(n, 0.005, 0.05, 0.8, 0.12)
    gate = (np.sin(2 * np.pi * 14 * tt(d)) > -0.2).astype(float)
    return s * gate


def sfx_relay_toggle():
    out = np.zeros(secs(0.7))
    clank = bandpass(noise(secs(0.12)), 600, 4000) * env_exp(secs(0.12), 0.001, 0.04)
    mix_into(out, clank * 0.8, 0.0)
    f = glide(180, 640, 0.25)
    zap = saw(f, 0.25) * env_exp(secs(0.25), 0.005, 0.12) * 0.3
    mix_into(out, lowpass(zap, 3000), 0.05)
    return reverb(out, 0.6, 0.2)


def sfx_laser_on():
    d = 1.2
    n = secs(d)
    f = glide(220, 880, 0.4, 0.5)
    rise = np.concatenate([f, np.full(n - len(f), 880)])
    s = np.sin(2 * np.pi * np.cumsum(rise) / SR) * 0.4 + np.sin(2 * np.pi * np.cumsum(rise * 1.5) / SR) * 0.15
    return s * env_adsr(n, 0.02, 0.2, 0.6, 0.6)


def sfx_cart_move():
    d = 0.9
    n = secs(d)
    roll = bandpass(noise(n), 200, 1400) * 0.4 * env_adsr(n, 0.05, 0.1, 0.8, 0.3)
    rattle = bandpass(noise(n), 2000, 6000) * 0.08 * (np.sin(2 * np.pi * 18 * tt(d)) > 0.6)
    out = roll + rattle
    clunk = brown(secs(0.25)) * env_exp(secs(0.25), 0.002, 0.07)
    mix_into(out, clunk * 0.8, d - 0.25)
    return out


def sfx_door_slide():
    d = 1.6
    n = secs(d)
    hiss = bandpass(noise(n), 1500, 8000) * 0.18 * env_adsr(n, 0.02, 0.1, 0.5, 0.5)
    motor = saw(glide(90, 140, d), d) * 0.12
    motor = lowpass(motor, 900) * env_adsr(n, 0.05, 0.2, 0.7, 0.4)
    out = hiss + motor
    mix_into(out, brown(secs(0.3)) * env_exp(secs(0.3), 0.002, 0.08) * 0.7, d - 0.3)
    return out


def sfx_core_transfer():
    d = 1.8
    n = secs(d)
    f = glide(160, 520, d, 0.8)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.35
    bubbles = bandpass(noise(n), 300, 2000) * (np.sin(2 * np.pi * 9 * tt(d)) > 0.5) * 0.15
    return reverb((s + bubbles) * env_adsr(n, 0.1, 0.3, 0.7, 0.6), 1.2, 0.3)


def sfx_sync_lock():
    out = np.zeros(secs(1.6))
    for i, k in enumerate([0, 7, 12]):
        mix_into(out, bell(note_freq(64 + k), 1.2, 2.0, 0.8, 0.5) * 0.3, i * 0.08)
    clunk = brown(secs(0.3)) * env_exp(secs(0.3), 0.002, 0.08) * 0.6
    mix_into(out, clunk, 0.0)
    return reverb(out, 1.4, 0.3)


def sfx_hazard_warn():
    d = 0.8
    n = secs(d)
    f = glide(300, 900, d, 1.5)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_adsr(n, 0.05, 0.1, 0.8, 0.1) * 0.3
    crackle = bandpass(noise(n), 3000, 9000) * (RNG.random(n) > 0.97) * 0.5
    return s + crackle


def sfx_hazard_burst():
    d = 1.0
    n = secs(d)
    blast = bandpass(noise(n), 200, 6000) * env_exp(n, 0.005, 0.3) * 0.8
    zap = saw(glide(800, 120, 0.5), 0.5) * env_exp(secs(0.5), 0.002, 0.2) * 0.3
    out = blast
    mix_into(out, lowpass(zap, 4000), 0.0)
    return reverb(out, 0.8, 0.2)


def sfx_gravity_shift():
    d = 2.0
    n = secs(d)
    f = glide(90, 45, d, 0.7)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.5 + np.sin(2 * np.pi * np.cumsum(f * 3.01) / SR) * 0.15
    swirl = bandpass(pink(n), 400, 2500) * 0.15 * (0.5 + 0.5 * np.sin(2 * np.pi * 3 * tt(d)))
    return reverb((s + swirl) * env_adsr(n, 0.2, 0.4, 0.7, 0.8), 2.2, 0.35)


def sfx_phase_shift():
    d = 1.0
    n = secs(d)
    up = glide(300, 2400, 0.35, 0.5)
    s = np.zeros(n)
    s[:len(up)] = np.sin(2 * np.pi * np.cumsum(up) / SR) * env_exp(len(up), 0.005, 0.2)
    shimmer = sum(np.sin(2 * np.pi * f * tt(d)) for f in [880, 1320, 1975]) * 0.08 * env_exp(n, 0.1, 0.4)
    return reverb((s * 0.4 + shimmer), 1.6, 0.4)


def sfx_time_freeze():
    d = 1.6
    n = secs(d)
    f = glide(1200, 140, d, 0.5)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.35 * env_adsr(n, 0.01, 0.3, 0.6, 0.6)
    tick = np.zeros(n)
    for i in range(6):
        mix_into(tick, bandpass(noise(secs(0.02)), 2000, 7000) * 0.4, i * 0.12 * (1 + i * 0.25))
    return reverb(s + tick, 2.4, 0.4)


def sfx_time_resume():
    d = 1.0
    n = secs(d)
    f = glide(140, 1000, d, 1.8)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.35 * env_adsr(n, 0.05, 0.2, 0.6, 0.3)
    return reverb(s, 1.2, 0.3)


def sfx_portal_whoosh():
    d = 2.4
    n = secs(d)
    w = bandpass(pink(n), 200, 3000) * env_adsr(n, 0.6, 0.5, 0.7, 1.0) * 0.6
    f = glide(80, 400, d, 1.2)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.25 * env_adsr(n, 0.3, 0.5, 0.6, 0.8)
    return reverb(w + tone, 2.4, 0.4)


def sfx_lift_move():
    d = 2.6
    n = secs(d)
    motor = lowpass(saw(np.full(n, 70.0) * (1 + 0.02 * np.sin(2 * np.pi * 0.5 * tt(d))), d), 600) * 0.25
    rumble = lowpass(brown(n), 200) * 0.6
    e = env_adsr(n, 0.4, 0.3, 0.8, 0.8)
    out = (motor + rumble) * e
    mix_into(out, bell(note_freq(76), 0.8, 2.0, 0.5, 0.4) * 0.2, d - 0.7)
    return out


def sfx_node_wake():
    out = np.zeros(secs(1.8))
    mix_into(out, bell(note_freq(57), 1.8, 1.41, 1.2, 0.9) * 0.35, 0.0)
    mix_into(out, bell(note_freq(64), 1.6, 2.0, 0.8, 0.8) * 0.25, 0.05)
    hum = np.sin(2 * np.pi * 110 * tt(1.6)) * env_adsr(secs(1.6), 0.2, 0.4, 0.5, 0.8) * 0.2
    mix_into(out, hum, 0.0)
    return reverb(out, 2.0, 0.35)


def sfx_overload():
    d = 1.4
    n = secs(d)
    s = saw(glide(400, 60, d, 0.5), d) * 0.3
    crack = bandpass(noise(n), 2000, 10000) * (RNG.random(n) > 0.9) * env_exp(n, 0.01, 0.5) * 0.6
    return reverb(lowpass(s, 3000) * env_exp(n, 0.01, 0.6) + crack, 1.0, 0.3)


# --- Loops and beds ---------------------------------------------------------------------

def loop_laser_hum():
    d = 4.0
    t = tt(d)
    s = np.sin(2 * np.pi * 220 * t) * 0.4 + np.sin(2 * np.pi * 440.4 * t) * 0.2 + np.sin(2 * np.pi * 660 * t) * 0.08
    s *= 1 + 0.08 * np.sin(2 * np.pi * 6 * t)
    return normalize(s, 0.45)


def loop_blade_whir():
    d = 4.0
    t = tt(d)
    swish = bandpass(noise(len(t)), 500, 3000) * (0.5 + 0.5 * np.sin(2 * np.pi * 6 * t)) ** 2
    hum = np.sin(2 * np.pi * 95 * t) * 0.3
    return normalize(swish * 0.6 + hum, 0.45)


def amb_lab_base():
    d = 40.0
    n = secs(d + 2)
    t = tt(d + 2)
    hum = np.sin(2 * np.pi * 60 * t) * 0.12 + np.sin(2 * np.pi * 120 * t) * 0.06
    air = bandpass(pink(n), 150, 1500) * 0.35 * (0.8 + 0.2 * np.sin(2 * np.pi * 0.05 * t))
    out = hum + air
    for i in range(10):
        at = RNG.uniform(1, d - 2)
        creak = bandpass(noise(secs(0.6)), 300, 1200) * env_adsr(secs(0.6), 0.2, 0.1, 0.4, 0.3) * 0.15
        mix_into(out, creak, at)
        if i % 3 == 0:
            mix_into(out, bell(note_freq(84 + int(RNG.integers(0, 5))), 0.6, 3.0, 0.3, 0.2) * 0.04, at + 0.3)
    l = loopify(out, d)
    r = loopify(np.roll(out, secs(0.04)), d)
    return stereo(normalize(reverb(l, 2.0, 0.3), 0.5), normalize(reverb(r, 2.0, 0.3, seed=1), 0.5))


def amb_reactor_base():
    d = 40.0
    n = secs(d + 2)
    t = tt(d + 2)
    drone = np.sin(2 * np.pi * 41 * t) * 0.35 + np.sin(2 * np.pi * 82.3 * t) * 0.18 + np.sin(2 * np.pi * 61.7 * t) * 0.12
    drone *= 1 + 0.25 * np.sin(2 * np.pi * 0.11 * t)
    rumble = lowpass(brown(n), 140) * 0.5
    out = drone + rumble
    for i in range(16):
        at = RNG.uniform(1, d - 2)
        crack = bandpass(noise(secs(0.3)), 2500, 9000) * (RNG.random(secs(0.3)) > 0.92) * 0.25
        mix_into(out, crack, at)
    l = loopify(out, d)
    r = loopify(np.roll(out, secs(0.05)), d)
    return stereo(normalize(reverb(l, 3.0, 0.35), 0.55), normalize(reverb(r, 3.0, 0.35, seed=1), 0.55))


def amb_quantum_base():
    d = 40.0
    n = secs(d + 4)
    t = tt(d + 4)
    l = np.zeros(n)
    r = np.zeros(n)
    for f, ph in [(220, 0.0), (329.6, 1.3), (493.9, 2.1), (659.3, 0.7)]:
        amp = 0.08 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.03 * t + ph))
        l += np.sin(2 * np.pi * f * t + ph) * amp
        r += np.sin(2 * np.pi * f * 1.003 * t + ph * 1.2) * amp
    for i in range(14):
        at = RNG.uniform(1, d - 3)
        f = note_freq(int(RNG.choice([69, 71, 74, 76, 78, 81])))
        tone = np.sin(2 * np.pi * f * tt(2.0)) * env_adsr(secs(2.0), 1.6, 0.1, 0.5, 0.3) * 0.06
        mix_into(l, tone, at)
        mix_into(r, tone * 0.8, at + 0.02)
    air = bandpass(pink(n), 2000, 8000) * 0.04
    l = loopify(l + air, d)
    r = loopify(r + air, d)
    return stereo(normalize(reverb(l, 4.0, 0.45), 0.5), normalize(reverb(r, 4.0, 0.45, seed=1), 0.5))


def music_tracks():
    tracks = {}
    tracks["lab"] = ga.compose("lab", 58, [("D3", "min9"), ("A#2", "maj7"), ("G2", "min7"), ("A2", "sus2")],
                               ga.scale_midis("D5", ga.DORIAN), lambda f: bell(f, 2.0, ratio=3.0, index=0.8, decay=0.9), repeats=3, seed=21,
                               lead_density=0.22, pad_level=0.55, bright=0.25, reverb_decay=4.5)
    tracks["reactor"] = ga.compose("reactor", 70, [("E2", "min"), ("C2", "maj7"), ("D2", "sus2"), ("E2", "min7")],
                                   ga.scale_midis("E4", [0, 2, 3, 7, 8]), lambda f: ga.marimba(f, 1.0, 0.3), repeats=3, seed=23,
                                   lead_density=0.3, pad_level=0.6, bright=0.2, reverb_decay=3.5,
                                   arp={"step": 0.5, "pattern": [0, 0, 1, 0, 2, 0, 1, 0], "inst": lambda f: ga.soft_bass(f, 0.25, 0.005), "level": 0.18, "octave": 0})
    tracks["quantum"] = ga.compose("quantum", 64, [("A2", "lyd"), ("F#2", "min7"), ("D2", "maj7"), ("E2", "sus2")],
                                   ga.scale_midis("A4", ga.LYDIAN), lambda f: bell(f, 2.6, ratio=1.41, index=1.4, decay=1.2), repeats=3, seed=25,
                                   lead_density=0.3, pad_level=0.5, bright=0.55, reverb_decay=5.0,
                                   arp={"step": 0.5, "pattern": [0, 2, 1, 3, 2, 1], "inst": lambda f: bell(f, 0.9, ratio=4.0, index=0.6, decay=0.3), "level": 0.06, "octave": 2})
    return tracks


def main():
    sfx = {
        "terminal_beep": sfx_terminal_beep, "power_restore": sfx_power_restore, "error_buzz": sfx_error_buzz,
        "relay_toggle": sfx_relay_toggle, "laser_on": sfx_laser_on, "cart_move": sfx_cart_move,
        "door_slide": sfx_door_slide, "core_transfer": sfx_core_transfer, "sync_lock": sfx_sync_lock,
        "hazard_warn": sfx_hazard_warn, "hazard_burst": sfx_hazard_burst, "gravity_shift": sfx_gravity_shift,
        "phase_shift": sfx_phase_shift, "time_freeze": sfx_time_freeze, "time_resume": sfx_time_resume,
        "portal_whoosh": sfx_portal_whoosh, "lift_move": sfx_lift_move, "node_wake": sfx_node_wake,
        "overload": sfx_overload,
    }
    for name, fn in sfx.items():
        ga.write_wav(os.path.join(ga.SFX_DIR, name + ".wav"), fade(normalize(fn(), 0.85)))
        print("sfx", name)
    for name, fn in {"laser_hum": loop_laser_hum, "blade_whir": loop_blade_whir}.items():
        ga.write_ogg(os.path.join(ga.AMB_DIR, name), fn(), 4)
        print("loop", name)
    for name, fn in {"lab_base": amb_lab_base, "reactor_base": amb_reactor_base, "quantum_base": amb_quantum_base}.items():
        ga.write_ogg(os.path.join(ga.AMB_DIR, name), fn(), 4)
        print("ambience", name)
    for name, data in music_tracks().items():
        ga.write_ogg(os.path.join(ga.MUSIC_DIR, name), data, 5)
        print("music", name, round(len(data) / SR, 1), "s")


if __name__ == "__main__":
    main()
