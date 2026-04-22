"""
Procedural audio generator for Abysson.
Generates ambient tracks and SFX as WAV files.
"""
import numpy as np
import struct
import os
import random

SAMPLE_RATE = 22050  # Game-quality, keeps file sizes reasonable

def write_wav(filename, samples, sample_rate=SAMPLE_RATE):
    """Write mono 16-bit WAV file."""
    samples = np.clip(samples, -1.0, 1.0)
    int_samples = (samples * 32767).astype(np.int16)
    num_samples = len(int_samples)
    data_size = num_samples * 2
    with open(filename, 'wb') as f:
        # RIFF header
        f.write(b'RIFF')
        f.write(struct.pack('<I', 36 + data_size))
        f.write(b'WAVE')
        # fmt chunk
        f.write(b'fmt ')
        f.write(struct.pack('<IHHIIHH', 16, 1, 1, sample_rate, sample_rate * 2, 2, 16))
        # data chunk
        f.write(b'data')
        f.write(struct.pack('<I', data_size))
        f.write(int_samples.tobytes())
    print(f"  Written: {filename} ({num_samples / sample_rate:.1f}s, {os.path.getsize(filename) // 1024}KB)")

def noise(length):
    return np.random.uniform(-1, 1, length)

def sine(freq, duration, sr=SAMPLE_RATE):
    t = np.arange(int(sr * duration)) / sr
    return np.sin(2 * np.pi * freq * t)

def fade_in_out(samples, fade_in=0.5, fade_out=0.5, sr=SAMPLE_RATE):
    n = len(samples)
    fi = int(sr * fade_in)
    fo = int(sr * fade_out)
    out = samples.copy()
    if fi > 0:
        out[:fi] *= np.linspace(0, 1, fi)
    if fo > 0:
        out[-fo:] *= np.linspace(1, 0, fo)
    return out

def lowpass(samples, cutoff=0.1):
    """Simple single-pole lowpass filter."""
    out = np.zeros_like(samples)
    out[0] = samples[0] * cutoff
    for i in range(1, len(samples)):
        out[i] = out[i-1] + cutoff * (samples[i] - out[i-1])
    return out

def fast_lowpass(samples, cutoff_ratio):
    """Faster lowpass using convolution with exponential kernel."""
    kernel_size = max(int(1.0 / cutoff_ratio), 4)
    kernel = np.exp(-np.arange(kernel_size) * cutoff_ratio * 2)
    kernel /= kernel.sum()
    return np.convolve(samples, kernel, mode='same')

def resonant_tone(freq, duration, decay=2.0, sr=SAMPLE_RATE):
    t = np.arange(int(sr * duration)) / sr
    return np.sin(2 * np.pi * freq * t) * np.exp(-decay * t)

# ==================== AMBIENCE TRACKS ====================

def gen_deep_space_drift(duration=45.0):
    """Deep space — very low drones, distant metallic creaks, cosmic wind."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    out = np.zeros(n)
    # Sub-bass drone with slow modulation
    t = np.arange(n) / sr
    drone = np.sin(2 * np.pi * 35 * t + np.sin(2 * np.pi * 0.03 * t) * 3) * 0.12
    drone += np.sin(2 * np.pi * 52 * t + np.sin(2 * np.pi * 0.05 * t) * 2) * 0.08
    out += drone
    # Filtered noise — cosmic wind
    wind = noise(n) * 0.04
    wind = fast_lowpass(wind, 0.005)
    wind *= (1.0 + np.sin(2 * np.pi * 0.02 * t) * 0.5)
    out += wind
    # Distant metallic pings
    for _ in range(8):
        pos = random.randint(sr, n - sr * 2)
        freq = random.uniform(800, 2500)
        ping = resonant_tone(freq, 0.8, decay=4.0) * random.uniform(0.02, 0.05)
        end = min(pos + len(ping), n)
        out[pos:end] += ping[:end-pos]
    return fade_in_out(out * 0.9, 2.0, 2.0)

def gen_nebula_hum(duration=45.0):
    """Inside a nebula — rich harmonic drones, shimmering high frequencies."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    t = np.arange(n) / sr
    out = np.zeros(n)
    # Layered harmonics with slow phase drift
    for i, freq in enumerate([55, 82.5, 110, 165, 220]):
        phase_mod = np.sin(2 * np.pi * (0.01 + i * 0.007) * t) * (2 + i * 0.5)
        out += np.sin(2 * np.pi * freq * t + phase_mod) * (0.1 / (1 + i * 0.3))
    # Shimmering high-frequency wash
    shimmer = noise(n) * 0.02
    shimmer = fast_lowpass(shimmer, 0.02)
    shimmer *= (0.5 + 0.5 * np.sin(2 * np.pi * 0.08 * t))
    out += shimmer
    return fade_in_out(out * 0.7, 2.0, 2.0)

def gen_engine_room(duration=45.0):
    """Ship engine room — mechanical hum, rhythmic throbbing, pipe sounds."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    t = np.arange(n) / sr
    out = np.zeros(n)
    # Engine throb — pulsing low frequency
    throb = np.sin(2 * np.pi * 60 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 1.2 * t)) * 0.15
    throb += np.sin(2 * np.pi * 120 * t) * 0.06
    out += throb
    # Mechanical rattle
    rattle = noise(n) * 0.03
    rattle = fast_lowpass(rattle, 0.08)
    rattle *= (0.3 + 0.7 * np.abs(np.sin(2 * np.pi * 2.4 * t)))
    out += rattle
    # Pipe resonance tones
    for _ in range(12):
        pos = random.randint(0, n - sr)
        freq = random.choice([180, 240, 360, 480])
        tone = resonant_tone(freq, 0.5, decay=6.0) * 0.04
        end = min(pos + len(tone), n)
        out[pos:end] += tone[:end-pos]
    return fade_in_out(out * 0.8, 1.5, 1.5)

def gen_station_systems(duration=45.0):
    """Station interior — ventilation hum, computer beeps, power conduits. Super Metroid lab vibes."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    t = np.arange(n) / sr
    out = np.zeros(n)
    # Ventilation — filtered noise
    vent = noise(n) * 0.06
    vent = fast_lowpass(vent, 0.01)
    vent *= (0.7 + 0.3 * np.sin(2 * np.pi * 0.15 * t))
    out += vent
    # Power conduit hum — 60Hz harmonics
    hum = np.sin(2 * np.pi * 60 * t) * 0.08
    hum += np.sin(2 * np.pi * 180 * t) * 0.03
    hum += np.sin(2 * np.pi * 300 * t) * 0.01
    hum *= (0.8 + 0.2 * np.sin(2 * np.pi * 0.04 * t))
    out += hum
    # Computer beeps and chirps
    for _ in range(20):
        pos = random.randint(0, n - sr)
        freq = random.choice([440, 880, 1320, 660, 550, 1100])
        dur = random.uniform(0.05, 0.15)
        beep = sine(freq, dur) * random.uniform(0.02, 0.06)
        beep = fade_in_out(beep, 0.01, 0.02)
        end = min(pos + len(beep), n)
        out[pos:end] += beep[:end-pos]
    # Occasional hydraulic hiss
    for _ in range(4):
        pos = random.randint(sr, n - sr * 2)
        hiss_len = int(sr * random.uniform(0.3, 0.8))
        hiss = noise(hiss_len) * 0.05
        hiss = fast_lowpass(hiss, 0.15)
        hiss = fade_in_out(hiss, 0.05, 0.2)
        end = min(pos + len(hiss), n)
        out[pos:end] += hiss[:end-pos]
    return fade_in_out(out * 0.8, 1.5, 1.5)

def gen_solar_wind(duration=45.0):
    """Solar wind near a star — rushing filtered noise, radiation crackle."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    t = np.arange(n) / sr
    out = np.zeros(n)
    # Rushing wind with modulation
    wind = noise(n) * 0.1
    wind = fast_lowpass(wind, 0.015)
    wind *= (0.6 + 0.4 * np.sin(2 * np.pi * 0.07 * t + np.sin(2 * np.pi * 0.02 * t) * 2))
    out += wind
    # Deep rumble
    rumble = np.sin(2 * np.pi * 28 * t + np.sin(2 * np.pi * 0.05 * t) * 4) * 0.08
    out += rumble
    # Radiation crackle — short noise bursts
    for _ in range(30):
        pos = random.randint(0, n - sr // 2)
        crack_len = int(sr * random.uniform(0.01, 0.05))
        crack = noise(crack_len) * random.uniform(0.03, 0.08)
        crack = fade_in_out(crack, 0.002, 0.01)
        end = min(pos + len(crack), n)
        out[pos:end] += crack[:end-pos]
    return fade_in_out(out * 0.75, 2.0, 2.0)

def gen_asteroid_field(duration=45.0):
    """Asteroid field — distant impacts, grinding rock, low rumbles."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    t = np.arange(n) / sr
    out = np.zeros(n)
    # Deep space background
    bg = noise(n) * 0.02
    bg = fast_lowpass(bg, 0.003)
    out += bg
    # Sub-bass rumble
    out += np.sin(2 * np.pi * 40 * t) * 0.06 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.03 * t))
    # Impact sounds — filtered noise bursts with low-frequency content
    for _ in range(15):
        pos = random.randint(sr, n - sr * 2)
        dur = random.uniform(0.1, 0.4)
        imp_n = int(sr * dur)
        imp = noise(imp_n) * random.uniform(0.04, 0.1)
        imp = fast_lowpass(imp, 0.04)
        imp *= np.exp(-np.arange(imp_n) / (sr * dur * 0.3))
        end = min(pos + len(imp), n)
        out[pos:end] += imp[:end-pos]
    # Grinding tones
    for _ in range(6):
        pos = random.randint(0, n - sr * 3)
        freq = random.uniform(60, 150)
        dur = random.uniform(0.5, 1.5)
        grind = sine(freq, dur) * 0.04
        grind *= noise(len(grind)) * 0.5 + 0.5
        grind = fade_in_out(grind, 0.1, 0.3)
        end = min(pos + len(grind), n)
        out[pos:end] += grind[:end-pos]
    return fade_in_out(out * 0.85, 2.0, 2.0)

def gen_warp_tunnel(duration=45.0):
    """Warp/hyperspace travel — rising/falling sweeps, phaser-like wobble."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    t = np.arange(n) / sr
    out = np.zeros(n)
    # Sweeping oscillator
    sweep_freq = 80 + 40 * np.sin(2 * np.pi * 0.05 * t) + 20 * np.sin(2 * np.pi * 0.13 * t)
    sweep = np.sin(2 * np.pi * np.cumsum(sweep_freq / sr)) * 0.1
    out += sweep
    # Phase wobble
    wobble = np.sin(2 * np.pi * 200 * t + np.sin(2 * np.pi * 3.0 * t) * 5) * 0.05
    out += wobble
    # High-frequency shimmer
    shimmer = noise(n) * 0.03
    shimmer = fast_lowpass(shimmer, 0.04)
    shimmer *= (0.5 + 0.5 * np.sin(2 * np.pi * 0.1 * t))
    out += shimmer
    # Sub-bass thrust
    out += np.sin(2 * np.pi * 30 * t) * 0.07
    return fade_in_out(out * 0.8, 2.0, 2.0)

def gen_derelict_ship(duration=45.0):
    """Derelict/abandoned ship — eerie silence, distant creaks, failing systems."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    t = np.arange(n) / sr
    out = np.zeros(n)
    # Very quiet background hum — failing power
    hum = np.sin(2 * np.pi * 50 * t) * 0.04
    hum *= (0.3 + 0.7 * np.sin(2 * np.pi * 0.08 * t))  # Flickering
    out += hum
    # Metallic creaks
    for _ in range(10):
        pos = random.randint(sr * 2, n - sr * 2)
        freq = random.uniform(300, 900)
        creak = resonant_tone(freq, 0.6, decay=3.0) * random.uniform(0.03, 0.07)
        # Pitch bend down
        bend_t = np.arange(len(creak)) / sr
        creak *= np.sin(2 * np.pi * (freq * 0.2) * bend_t * np.exp(-2 * bend_t))
        end = min(pos + len(creak), n)
        out[pos:end] += creak[:end-pos]
    # Distant dripping sound
    for _ in range(8):
        pos = random.randint(0, n - sr)
        drip = resonant_tone(random.uniform(1500, 3000), 0.08, decay=15.0) * 0.04
        end = min(pos + len(drip), n)
        out[pos:end] += drip[:end-pos]
    # Very faint filtered noise
    faint = noise(n) * 0.015
    faint = fast_lowpass(faint, 0.003)
    out += faint
    return fade_in_out(out * 0.7, 2.0, 2.0)

def gen_planet_atmosphere(duration=45.0):
    """Atmospheric planet — wind gusts, distant thunder, pressure rumble."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    t = np.arange(n) / sr
    out = np.zeros(n)
    # Wind base
    wind = noise(n) * 0.08
    wind = fast_lowpass(wind, 0.008)
    # Wind gusts
    gust_env = np.zeros(n)
    for _ in range(6):
        pos = random.randint(0, n - sr * 4)
        dur = random.uniform(2.0, 4.0)
        gust_n = int(sr * dur)
        env = np.sin(np.linspace(0, np.pi, gust_n)) ** 2
        end = min(pos + gust_n, n)
        gust_env[pos:end] += env[:end-pos] * random.uniform(0.5, 1.0)
    wind *= (0.4 + gust_env * 0.6)
    out += wind
    # Pressure rumble
    out += np.sin(2 * np.pi * 25 * t + np.sin(2 * np.pi * 0.04 * t) * 3) * 0.06
    # Distant thunder
    for _ in range(3):
        pos = random.randint(sr * 3, n - sr * 5)
        thunder_n = int(sr * random.uniform(1.5, 3.0))
        thunder = noise(thunder_n) * 0.12
        thunder = fast_lowpass(thunder, 0.02)
        thunder *= np.exp(-np.arange(thunder_n) / (sr * 1.0))
        thunder = fade_in_out(thunder, 0.05, 0.5)
        end = min(pos + len(thunder), n)
        out[pos:end] += thunder[:end-pos]
    return fade_in_out(out * 0.8, 2.0, 2.0)

def gen_comm_chatter(duration=45.0):
    """Radio/comms chatter — static bursts, garbled tones, signal processing sounds."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    t = np.arange(n) / sr
    out = np.zeros(n)
    # Low static floor
    static = noise(n) * 0.02
    static = fast_lowpass(static, 0.02)
    out += static
    # Background carrier tone
    out += np.sin(2 * np.pi * 400 * t) * 0.01 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.03 * t))
    # Garbled voice-like tones (formant-ish)
    for _ in range(15):
        pos = random.randint(0, n - sr * 2)
        dur = random.uniform(0.3, 1.0)
        chunk_n = int(sr * dur)
        chunk_t = np.arange(chunk_n) / sr
        f1 = random.uniform(200, 600)
        f2 = random.uniform(800, 1800)
        voice = (np.sin(2 * np.pi * f1 * chunk_t) * 0.5 +
                 np.sin(2 * np.pi * f2 * chunk_t) * 0.3) * 0.04
        # AM modulation to make it sound garbled
        voice *= noise(chunk_n) * 0.5 + 0.5
        voice = fade_in_out(voice, 0.02, 0.05)
        end = min(pos + chunk_n, n)
        out[pos:end] += voice[:end-pos]
    # Static bursts
    for _ in range(10):
        pos = random.randint(0, n - sr)
        burst_n = int(sr * random.uniform(0.05, 0.2))
        burst = noise(burst_n) * random.uniform(0.04, 0.08)
        burst = fade_in_out(burst, 0.01, 0.02)
        end = min(pos + burst_n, n)
        out[pos:end] += burst[:end-pos]
    return fade_in_out(out * 0.7, 1.5, 1.5)


# ==================== SFX ====================

def gen_dock_clamp(duration=1.2):
    """Docking clamp engaging — metallic clunk + hydraulic hiss."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    out = np.zeros(n)
    t = np.arange(n) / sr
    # Heavy metallic impact
    imp_n = int(sr * 0.15)
    imp = noise(imp_n) * 0.7
    imp = fast_lowpass(imp, 0.08)
    imp *= np.exp(-np.arange(imp_n) / (sr * 0.03))
    out[:imp_n] += imp
    # Low resonance
    res1 = resonant_tone(80, 0.5, decay=5.0)
    res2 = resonant_tone(160, 0.3, decay=8.0)
    out[:len(res1)] += res1[:min(len(res1), n)] * 0.3
    out[:len(res2)] += res2[:min(len(res2), n)] * 0.15
    # Hydraulic hiss after clunk
    hiss_start = int(sr * 0.2)
    hiss_n = int(sr * 0.6)
    hiss = noise(hiss_n) * 0.15
    hiss = fast_lowpass(hiss, 0.12)
    hiss = fade_in_out(hiss, 0.05, 0.3)
    out[hiss_start:hiss_start + hiss_n] += hiss
    return fade_in_out(out * 0.8, 0.005, 0.1)

def gen_airlock_cycle(duration=1.5):
    """Airlock cycling — pressurization whoosh + seal clunk."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    out = np.zeros(n)
    t = np.arange(n) / sr
    # Whoosh — rising then falling filtered noise
    whoosh = noise(n) * 0.2
    whoosh = fast_lowpass(whoosh, 0.03)
    env = np.sin(np.linspace(0, np.pi, n)) ** 1.5
    whoosh *= env
    out += whoosh
    # Seal clunk at end
    seal_pos = int(sr * 1.1)
    seal_n = int(sr * 0.15)
    seal = noise(seal_n) * 0.4
    seal = fast_lowpass(seal, 0.06)
    seal *= np.exp(-np.arange(seal_n) / (sr * 0.03))
    end = min(seal_pos + seal_n, n)
    out[seal_pos:end] += seal[:end-seal_pos]
    # Pressure tone
    out += np.sin(2 * np.pi * 120 * t) * 0.05 * env
    return fade_in_out(out * 0.8, 0.01, 0.1)

def gen_crew_footstep(duration=0.3):
    """Single footstep on metal grating."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    out = np.zeros(n)
    # Impact noise
    imp_n = int(sr * 0.04)
    imp = noise(imp_n) * 0.5
    imp = fast_lowpass(imp, 0.1)
    imp *= np.exp(-np.arange(imp_n) / (sr * 0.01))
    out[:imp_n] += imp
    # Metal ring
    r1 = resonant_tone(400, 0.15, decay=12.0) * 0.15
    r2 = resonant_tone(800, 0.1, decay=15.0) * 0.08
    out[:len(r1)] += r1[:min(len(r1), n)]
    out[:len(r2)] += r2[:min(len(r2), n)]
    return fade_in_out(out * 0.6, 0.001, 0.05)

def gen_alert_klaxon(duration=2.0):
    """Alert/warning klaxon — two-tone alternating."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    t = np.arange(n) / sr
    # Alternate between two frequencies
    freq = np.where(np.sin(2 * np.pi * 2.0 * t) > 0, 440.0, 330.0)
    out = np.sin(2 * np.pi * np.cumsum(freq / sr)) * 0.25
    # Add harmonics for harshness
    out += np.sin(2 * np.pi * np.cumsum(freq * 2 / sr)) * 0.08
    out += np.sin(2 * np.pi * np.cumsum(freq * 3 / sr)) * 0.04
    return fade_in_out(out * 0.7, 0.02, 0.02)

def gen_power_down(duration=2.0):
    """System powering down — descending tone with noise."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    t = np.arange(n) / sr
    # Descending frequency
    freq = 400 * np.exp(-1.5 * t)
    out = np.sin(2 * np.pi * np.cumsum(freq / sr)) * 0.2
    # Dying hum
    out *= np.exp(-0.8 * t)
    # Noise crackle
    crackle = noise(n) * 0.05 * np.exp(-1.0 * t)
    crackle = fast_lowpass(crackle, 0.06)
    out += crackle
    return fade_in_out(out * 0.8, 0.01, 0.3)

def gen_power_up(duration=2.0):
    """System powering up — ascending tone with building hum."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    t = np.arange(n) / sr
    # Ascending frequency
    freq = 60 + 340 * (1.0 - np.exp(-2.0 * t))
    out = np.sin(2 * np.pi * np.cumsum(freq / sr)) * 0.2
    # Building envelope
    out *= (1.0 - np.exp(-1.5 * t))
    # Harmonics building in
    out += np.sin(2 * np.pi * np.cumsum(freq * 2 / sr)) * 0.05 * (1.0 - np.exp(-2.0 * t))
    # Noise reduction as system stabilizes
    crackle = noise(n) * 0.04 * np.exp(-1.5 * t)
    out += crackle
    return fade_in_out(out * 0.8, 0.01, 0.1)

def gen_menu_open(duration=0.4):
    """UI menu opening — quick ascending chime."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    out = np.zeros(n)
    # Two quick ascending tones
    t1 = resonant_tone(600, 0.15, decay=10.0) * 0.2
    t2 = resonant_tone(900, 0.15, decay=10.0) * 0.15
    offset = int(sr * 0.08)
    out[:len(t1)] += t1
    end2 = min(offset + len(t2), n)
    out[offset:end2] += t2[:end2-offset]
    return fade_in_out(out * 0.6, 0.005, 0.1)

def gen_menu_close(duration=0.35):
    """UI menu closing — quick descending chime."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    out = np.zeros(n)
    t1 = resonant_tone(800, 0.12, decay=12.0) * 0.18
    t2 = resonant_tone(500, 0.12, decay=12.0) * 0.15
    offset = int(sr * 0.07)
    out[:len(t1)] += t1
    end2 = min(offset + len(t2), n)
    out[offset:end2] += t2[:end2-offset]
    return fade_in_out(out * 0.6, 0.005, 0.1)

def gen_repair_sound(duration=1.5):
    """Ship repair — welding spark + ratchet sounds."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    out = np.zeros(n)
    t = np.arange(n) / sr
    # Welding crackle
    for _ in range(20):
        pos = random.randint(0, n - sr // 4)
        spark_n = int(sr * random.uniform(0.02, 0.08))
        spark = noise(spark_n) * random.uniform(0.1, 0.25)
        spark *= np.exp(-np.arange(spark_n) / (sr * 0.01))
        end = min(pos + spark_n, n)
        out[pos:end] += spark[:end-pos]
    # Underlying tone
    out += np.sin(2 * np.pi * 200 * t) * 0.04 * (0.5 + 0.5 * np.sin(2 * np.pi * 8 * t))
    return fade_in_out(out * 0.6, 0.01, 0.1)

def gen_cargo_load(duration=0.8):
    """Cargo being loaded — thud + slide."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    out = np.zeros(n)
    # Heavy thud
    thud_n = int(sr * 0.1)
    thud = noise(thud_n) * 0.5
    thud = fast_lowpass(thud, 0.04)
    thud *= np.exp(-np.arange(thud_n) / (sr * 0.02))
    out[:thud_n] += thud
    # Low resonance
    res = resonant_tone(60, 0.3, decay=5.0)
    end = min(len(res), n)
    out[:end] += res[:end] * 0.2
    # Slide sound
    slide_start = int(sr * 0.15)
    slide_n = int(sr * 0.4)
    slide = noise(slide_n) * 0.08
    slide = fast_lowpass(slide, 0.05)
    slide = fade_in_out(slide, 0.02, 0.15)
    end = min(slide_start + slide_n, n)
    out[slide_start:end] += slide[:end-slide_start]
    return fade_in_out(out * 0.7, 0.005, 0.1)

def gen_crew_board(duration=0.6):
    """Crew boarding — boot step + airlock beep."""
    sr = SAMPLE_RATE
    n = int(sr * duration)
    out = np.zeros(n)
    # Boot step
    step = gen_crew_footstep(0.15)
    out[:len(step)] += step * 0.8
    # Confirmation beep
    beep_start = int(sr * 0.25)
    beep = resonant_tone(880, 0.15, decay=8.0) * 0.15
    end = min(beep_start + len(beep), n)
    out[beep_start:end] += beep[:end-beep_start]
    return fade_in_out(out * 0.7, 0.005, 0.05)

if __name__ == "__main__":
    random.seed(42)
    np.random.seed(42)

    amb_dir = os.path.join(os.path.dirname(__file__), "ambience")
    sfx_dir = os.path.join(os.path.dirname(__file__), "sfx")

    print("=== Generating Ambience Tracks ===")
    ambience = {
        "deep_space_drift": gen_deep_space_drift,
        "nebula_hum": gen_nebula_hum,
        "engine_room": gen_engine_room,
        "station_systems": gen_station_systems,
        "solar_wind": gen_solar_wind,
        "asteroid_field_ambience": gen_asteroid_field,
        "warp_tunnel": gen_warp_tunnel,
        "derelict_ship": gen_derelict_ship,
        "planet_atmosphere": gen_planet_atmosphere,
        "comm_chatter": gen_comm_chatter,
    }
    for name, gen_func in ambience.items():
        write_wav(os.path.join(amb_dir, f"{name}.wav"), gen_func())

    print("\n=== Generating SFX ===")
    sfx = {
        "dock_clamp": gen_dock_clamp,
        "airlock_cycle": gen_airlock_cycle,
        "crew_footstep": gen_crew_footstep,
        "alert_klaxon": gen_alert_klaxon,
        "power_down": gen_power_down,
        "power_up": gen_power_up,
        "menu_open": gen_menu_open,
        "menu_close": gen_menu_close,
        "repair": gen_repair_sound,
        "cargo_load": gen_cargo_load,
        "crew_board": gen_crew_board,
    }
    for name, gen_func in sfx.items():
        write_wav(os.path.join(sfx_dir, f"{name}.wav"), gen_func())

    print("\nDone! Generated %d ambience tracks and %d SFX." % (len(ambience), len(sfx)))
