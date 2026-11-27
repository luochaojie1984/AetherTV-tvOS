"""Generate subtle, studio-grade Apple TV UI sound effects (48kHz 16-bit mono WAV).

Usage: python -I make_tvos_sounds.py <output-dir>

Creates 5 lightweight, refined acoustic cues bundled in Sources/App/Sounds/:
  - aether_focus.wav   (36ms soft wooden-glass focus tick)
  - aether_select.wav  (95ms crisp crystalline confirmation chime)
  - aether_panel.wav   (135ms gentle upward harmonic glass shimmer)
  - aether_back.wav    (75ms soft downward dismiss tap)
  - aether_scrub.wav   (24ms tactile micro-detent tick for scrub/jog wheel)
"""
import math
import os
import sys
import wave

import numpy as np

SR = 48000


def write_wav(path, samples):
    clipped = np.clip(samples, -1.0, 1.0)
    pcm = (clipped * 32767.0).astype("<i2")
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())


def envelope(n, attack_ms, decay_tau_ms):
    t = np.arange(n, dtype=np.float64) / SR
    att = np.minimum(1.0, t / max(attack_ms / 1000.0, 1e-5))
    dec = np.exp(-t / max(decay_tau_ms / 1000.0, 1e-5))
    # Smooth end fade to prevent click
    tail = np.ones(n, dtype=np.float64)
    fade_n = min(int(SR * 0.004), n // 4)
    if fade_n > 0:
        tail[-fade_n:] = np.linspace(1.0, 0.0, fade_n)
    return att * dec * tail


def make_focus_tick():
    """Soft tactile glass-wood focus tick (subtle Apple TV focus feel)."""
    n = int(SR * 0.038)
    t = np.arange(n, dtype=np.float64) / SR
    # Smooth downward pitch bend 740Hz -> 430Hz
    freq = 430.0 + 310.0 * np.exp(-t / 0.009)
    phase = 2.0 * math.pi * np.cumsum(freq) / SR
    sig = 0.72 * np.sin(phase) + 0.24 * np.sin(phase * 2.02)
    return sig * envelope(n, 1.5, 9.0) * 0.34


def make_select_confirm():
    """Crystalline dual-harmonic confirmation pop."""
    n = int(SR * 0.095)
    t = np.arange(n, dtype=np.float64) / SR
    # Fundamental A5 (880Hz) + warm fifth E6 (1318.5Hz) + gentle low click
    s1 = np.sin(2.0 * math.pi * 880.0 * t) * envelope(n, 2.0, 26.0) * 0.55
    s2 = np.sin(2.0 * math.pi * 1318.5 * t) * envelope(n, 3.0, 22.0) * 0.32
    s3 = np.sin(2.0 * math.pi * 330.0 * t) * envelope(n, 1.0, 7.0) * 0.25
    return (s1 + s2 + s3) * 0.42


def make_panel_open():
    """Airy upward glass chime for opening panels & sheets."""
    n = int(SR * 0.140)
    t = np.arange(n, dtype=np.float64) / SR
    out = np.zeros(n, dtype=np.float64)
    notes = [(0.0, 587.33, 0.34), (0.026, 880.0, 0.30), (0.052, 1174.66, 0.24)]
    for start_s, freq, gain in notes:
        idx = int(start_s * SR)
        if idx >= n:
            continue
        rem = n - idx
        nt = np.arange(rem, dtype=np.float64) / SR
        tone = (0.8 * np.sin(2.0 * math.pi * freq * nt) + 0.2 * np.sin(2.0 * math.pi * freq * 2.0 * nt))
        out[idx:] += tone * envelope(rem, 4.0, 34.0) * gain
    return out * 0.44


def make_back_dismiss():
    """Gentle downward wood-glass dismiss tap."""
    n = int(SR * 0.075)
    t = np.arange(n, dtype=np.float64) / SR
    freq = 390.0 + 240.0 * np.exp(-t / 0.016)
    phase = 2.0 * math.pi * np.cumsum(freq) / SR
    sig = 0.80 * np.sin(phase) + 0.20 * np.sin(phase * 1.5)
    return sig * envelope(n, 2.0, 19.0) * 0.34


def make_scrub_notch():
    """Crisp tactile precision dial click for fast-forward & jog-wheel."""
    n = int(SR * 0.024)
    t = np.arange(n, dtype=np.float64) / SR
    freq = 640.0 + 480.0 * np.exp(-t / 0.004)
    phase = 2.0 * math.pi * np.cumsum(freq) / SR
    sig = 0.78 * np.sin(phase) + 0.22 * np.sin(phase * 2.4)
    return sig * envelope(n, 0.8, 5.5) * 0.28


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    sounds = {
        "aether_focus.wav": make_focus_tick(),
        "aether_select.wav": make_select_confirm(),
        "aether_panel.wav": make_panel_open(),
        "aether_back.wav": make_back_dismiss(),
        "aether_scrub.wav": make_scrub_notch(),
    }
    for name, data in sounds.items():
        write_wav(os.path.join(out_dir, name), data)
    print(f"wrote {len(sounds)} tvOS UI sound files into {out_dir}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
