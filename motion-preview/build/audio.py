"""Synthesise music + SFX, place Kazakh VO, duck, mix -> WAV (48 kHz stereo).
usage: python3 audio.py v1|v2
"""
import json, subprocess, sys, os
import numpy as np

SR = 48000
DUR = 60.0
BPM = 120.0
BEAT = 60.0 / BPM
rng = np.random.default_rng(7)
HERE = os.path.dirname(os.path.abspath(__file__))


def t_arr(d):
    return np.arange(int(d * SR)) / SR


def env_exp(d, k):
    return np.exp(-t_arr(d) * k)


def adsr(n, a=0.01, r=0.1):
    e = np.ones(n)
    na, nr = max(1, int(a * SR)), max(1, int(r * SR))
    na = min(na, n); nr = min(nr, n - na) if n - na > 0 else 0
    e[:na] = np.linspace(0, 1, na)
    if nr > 0:
        e[n - nr:] *= np.linspace(1, 0, nr)
    return e


def fft_filter(x, lo=None, hi=None):
    """zero-phase band filter via FFT with soft edges"""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    m = np.ones_like(f)
    if lo:
        m *= 1 / (1 + (lo / np.maximum(f, 1)) ** 4)
    if hi:
        m *= 1 / (1 + (f / hi) ** 4)
    return np.fft.irfft(X * m, n)


def noise(d):
    return rng.standard_normal(int(d * SR))


def place(buf, sig, t, g=1.0, pan=0.0):
    i = int(t * SR)
    if i >= buf.shape[1] or i + len(sig) <= 0:
        return
    s = sig
    if i < 0:
        s = s[-i:]; i = 0
    j = min(buf.shape[1], i + len(s))
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    buf[0, i:j] += s[: j - i] * g * l * 1.414
    buf[1, i:j] += s[: j - i] * g * r * 1.414


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


# ── instruments ───────────────────────────────────────────────────────────
def kick(g=1.0):
    d = 0.35; t = t_arr(d)
    f = 45 + 95 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(ph) * np.exp(-t * 9) + 0.25 * fft_filter(noise(d), lo=1500) * np.exp(-t * 90)) * g


def clap(g=1.0):
    d = 0.25; t = t_arr(d)
    n = fft_filter(noise(d), lo=900, hi=6000)
    e = np.exp(-t * 22)
    for k in (0.0, 0.012, 0.024):
        e += np.where(t > k, np.exp(-(t - k) * 120), 0) * 0.6
    return n * e * 0.5 * g


def hat(g=1.0, open_=False):
    d = 0.25 if open_ else 0.05; t = t_arr(d)
    return fft_filter(noise(d), lo=7000) * np.exp(-t * (14 if open_ else 70)) * 0.35 * g


def saw(f, d, det=0.0):
    t = t_arr(d)
    ph = (t * f * (1 + det)) % 1.0
    return 2 * ph - 1


def bass_note(m, d, g=1.0):
    f = mtof(m)
    s = 0.6 * saw(f, d) + 0.6 * np.sin(2 * np.pi * f * t_arr(d))
    s = fft_filter(s, hi=420)
    return s * adsr(len(s), 0.005, 0.05) * np.exp(-t_arr(d) * 2.5) * g


def pad_chord(ms, d, g=1.0, bright=1800):
    s = np.zeros(int(d * SR))
    for m in ms:
        for det in (-0.004, 0.0, 0.005):
            s += saw(mtof(m), d, det)
    s = fft_filter(s, hi=bright) / (len(ms) * 3)
    return s * adsr(len(s), 0.35, 0.6) * g


def pluck(m, d=0.5, g=1.0):
    f = mtof(m); t = t_arr(d)
    s = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(4 * np.pi * f * t) + 0.12 * np.sin(6 * np.pi * f * t)
    return s * np.exp(-t * 7) * adsr(len(t), 0.002, 0.05) * g


def bell(f, d=1.2, g=1.0):
    t = t_arr(d)
    s = np.sin(2 * np.pi * f * t + 1.5 * np.sin(2 * np.pi * f * 3.5 * t) * np.exp(-t * 6))
    s += 0.4 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t * 4)
    return s * np.exp(-t * 3.2) * adsr(len(t), 0.002, 0.1) * g


# ── SFX ───────────────────────────────────────────────────────────────────
def sfx(name):
    if name == 'pop':
        d = 0.12; t = t_arr(d); f = 500 + 700 * (1 - np.exp(-t * 60))
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 35) * 0.7
    if name in ('swish', 'whoosh', 'whooshUp'):
        d = {'swish': 0.35, 'whoosh': 0.6, 'whooshUp': 0.9}[name]
        t = t_arr(d); n = noise(d)
        lo = fft_filter(n, lo=200, hi=1200); hi_ = fft_filter(n, lo=1500, hi=8000)
        x = t / d
        mix = x if name == 'whooshUp' else np.sin(np.pi * x)
        e = np.sin(np.pi * np.clip(x, 0, 1)) ** (1.5 if name != 'whooshUp' else 0.8)
        if name == 'whooshUp':
            e = x ** 1.5 * np.exp(-np.maximum(0, x - 0.92) * 60)
        s = (lo * (1 - mix) + hi_ * mix) * e
        if name == 'whooshUp':
            s += 0.25 * np.sin(2 * np.pi * np.cumsum(200 + 1400 * x ** 2) / SR) * e
        return s * (0.6 if name == 'swish' else 0.9)
    if name == 'clink':
        d = 0.35; t = t_arr(d)
        return sum(np.sin(2 * np.pi * f * t) * np.exp(-t * k) for f, k in ((2400, 14), (3720, 18), (5300, 24))) * 0.25
    if name == 'thud':
        d = 0.35; t = t_arr(d)
        return (np.sin(2 * np.pi * (60 + 50 * np.exp(-t * 30)) * t) * np.exp(-t * 14) + 0.4 * fft_filter(noise(d), hi=600) * np.exp(-t * 25)) * 0.9
    if name == 'steps':
        out = np.zeros(int(1.2 * SR))
        for i in range(7):
            d = 0.12; t = t_arr(d)
            st = (np.sin(2 * np.pi * 95 * t) * np.exp(-t * 40) + 0.3 * fft_filter(noise(d), lo=300, hi=2500) * np.exp(-t * 60)) * (0.8 if i % 2 else 1)
            i0 = int(i * 0.16 * SR); out[i0:i0 + len(st)] += st
        return out * 0.6
    if name == 'door':
        d = 0.45; t = t_arr(d)
        f = 170 + 30 * np.sin(2 * np.pi * 9 * t)
        cr = saw(1, d) * 0
        cr = fft_filter(np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)), lo=300, hi=2500) * np.sin(np.pi * t / d) * 0.25
        return cr
    if name == 'buzz':
        d = 0.4; t = t_arr(d)
        return fft_filter(np.sign(np.sin(2 * np.pi * 110 * t)), hi=2500) * adsr(len(t), 0.005, 0.05) * 0.35
    if name in ('paper', 'bag', 'pocket'):
        d = {'paper': 0.6, 'bag': 0.45, 'pocket': 0.3}[name]; t = t_arr(d)
        n = fft_filter(noise(d), lo=1200 if name == 'paper' else 600, hi=7000)
        am = np.abs(np.sin(2 * np.pi * (11 if name == 'paper' else 7) * t + rng.random() * 3)) ** 2
        s = n * am * np.sin(np.pi * t / d) * 0.45
        if name == 'pocket':
            s += np.sin(2 * np.pi * 120 * t) * np.exp(-t * 30) * 0.4
        return s
    if name == 'focus':
        d = 0.4; t = t_arr(d)
        return np.sin(2 * np.pi * np.cumsum(900 - 500 * t / d) / SR) * np.sin(np.pi * t / d) * 0.08
    if name == 'tick':
        d = 0.04; t = t_arr(d)
        return np.sin(2 * np.pi * 2200 * t) * np.exp(-t * 160) * 0.5
    if name == 'tap':
        d = 0.06; t = t_arr(d)
        return (np.sin(2 * np.pi * 1400 * t) * np.exp(-t * 90) + 0.3 * fft_filter(noise(d), lo=3000) * np.exp(-t * 200)) * 0.5
    if name == 'type':
        out = np.zeros(int(1.0 * SR))
        for i in range(7):
            d = 0.04; t = t_arr(d); k = fft_filter(noise(d), lo=2000, hi=8000) * np.exp(-t * 150) * 0.4
            i0 = int(i * 0.11 * SR + rng.random() * 0.02 * SR); out[i0:i0 + len(k)] += k
        return out
    if name == 'stamp':
        d = 0.5; t = t_arr(d)
        return (np.sin(2 * np.pi * (50 + 80 * np.exp(-t * 25)) * t) * np.exp(-t * 9) + 0.6 * fft_filter(noise(d), hi=1500) * np.exp(-t * 30)) * 1.0
    if name == 'impact':
        d = 1.6; t = t_arr(d)
        boom = np.sin(2 * np.pi * (40 + 60 * np.exp(-t * 12)) * t) * np.exp(-t * 3.2)
        crash = fft_filter(noise(d), lo=3000) * np.exp(-t * 4) * 0.25
        return (boom + crash) * 0.9
    if name == 'ding':
        return bell(1318.5, 1.0, 0.35) + bell(1975.5, 1.0, 0.15)
    if name == 'notif':
        a = bell(1046.5, 0.5, 0.3); b = bell(1568.0, 0.8, 0.3)
        out = np.zeros(int(1.0 * SR)); out[:len(a)] += a; i0 = int(0.09 * SR); out[i0:i0 + len(b)] += b
        return out
    if name == 'cash':
        out = np.zeros(int(1.2 * SR))
        d = 0.08; t = t_arr(d); out[:len(t)] += fft_filter(noise(d), lo=1500) * np.exp(-t * 60) * 0.4
        for k, f in enumerate((2093, 2637, 3136)):
            b = bell(f, 0.9, 0.18); i0 = int((0.06 + k * 0.03) * SR); out[i0:i0 + len(b)] += b
        return out
    if name == 'coin':
        return bell(2637, 0.4, 0.22) + bell(3951, 0.4, 0.1)
    if name == 'chime':
        out = np.zeros(int(2.2 * SR))
        for k, m in enumerate((84, 88, 91, 96)):
            b = bell(mtof(m), 1.4, 0.2); i0 = int(k * 0.09 * SR); out[i0:i0 + len(b)] += b
        return out
    if name == 'print':
        d = 0.6; t = t_arr(d)
        return fft_filter(np.sign(np.sin(2 * np.pi * 60 * t)) * (np.sin(2 * np.pi * 14 * t) > 0), lo=200, hi=3000) * np.sin(np.pi * t / d) * 0.18
    if name == 'flip':
        d = 0.14; t = t_arr(d)
        return fft_filter(noise(d), lo=800, hi=6000) * np.sin(np.pi * t / d) * 0.5
    if name == 'hum':
        d = 1.4; t = t_arr(d)
        h = sum(np.sin(2 * np.pi * 120 * k * t) / k for k in (1, 2, 3, 5))
        flick = 0.6 + 0.4 * (np.sin(2 * np.pi * 23 * t) > -0.6)
        return h * flick * np.sin(np.pi * t / d) * 0.06
    if name == 'beep':
        d = 0.16; t = t_arr(d)
        return np.sin(2 * np.pi * 1850 * t) * adsr(len(t), 0.004, 0.02) * 0.3
    if name == 'riserEnd':
        return np.zeros(10)
    raise ValueError(name)


# ── music arrangement ─────────────────────────────────────────────────────
def music(video):
    buf = np.zeros((2, int((DUR + 1) * SR)))
    beats = int(DUR / BEAT)
    # chord tables (MIDI)
    minor = [[57, 60, 64], [53, 57, 60], [50, 53, 57], [52, 56, 59]]   # Am F Dm E
    major = [[48, 52, 55], [55, 59, 62], [57, 60, 64], [53, 57, 60]]   # C G Am F
    if video == 'v1':
        sections = [(0, 6, 'intro'), (6, 28.5, 'tense'), (28.5, 29.0, 'gap'), (29.0, 55.0, 'drop'), (55.0, 60, 'outro')]
    else:
        sections = [(0, 6, 'intro'), (6, 20.5, 'groove'), (20.5, 31.0, 'build'), (31.0, 52.5, 'drop'), (52.5, 60, 'outro')]

    def sec_at(t):
        for a, b, n in sections:
            if a <= t < b:
                return n
        return 'outro'

    for bi in range(beats + 1):
        t = bi * BEAT
        s = sec_at(t)
        bar = bi // 4; inb = bi % 4
        chords = minor if s == 'tense' else major
        ch = chords[bar % 4]
        if s == 'intro':
            if inb == 0 and bar % 2 == 0:
                place(buf, pad_chord([m + 12 for m in ch], BEAT * 8, 0.18, 1200), t)
            for k in range(2):
                place(buf, pluck(ch[(bi * 2 + k) % 3] + 24, 0.5, 0.10), t + k * BEAT / 2, pan=(-0.4 if k else 0.4))
            continue
        if s == 'gap':
            continue
        if s == 'outro':
            continue
        drive = {'tense': 0.8, 'groove': 0.85, 'build': 0.95, 'drop': 1.0}[s]
        place(buf, kick(0.75 * drive), t)
        if inb in (1, 3):
            place(buf, clap(0.5 * drive), t)
        for k in range(2):
            place(buf, hat(0.5 * drive * (0.7 if k else 1), open_=(s == 'drop' and k == 1 and inb == 3)), t + k * BEAT / 2, pan=0.3)
        # bass: 8ths on root with octave on offbeat
        root = ch[0] - 24
        place(buf, bass_note(root, BEAT / 2 * 0.95, 0.55), t)
        place(buf, bass_note(root + (12 if s != 'tense' else 0), BEAT / 2 * 0.9, 0.42), t + BEAT / 2)
        if inb == 0:
            place(buf, pad_chord([m + 12 for m in ch], BEAT * 4, 0.12 if s == 'tense' else 0.10, 1400 if s == 'tense' else 2600), t)
        # arp
        arp_amp = {'tense': 0.06, 'groove': 0.08, 'build': 0.09, 'drop': 0.10}[s]
        for k in range(4 if s in ('drop', 'build') else 2):
            step = (bi * 4 + k) if s in ('drop', 'build') else (bi * 2 + k)
            m = ch[step % 3] + (24 if s != 'tense' else 12) + (12 if (step // 3) % 2 and s == 'drop' else 0)
            sub = BEAT / (4 if s in ('drop', 'build') else 2)
            place(buf, pluck(m, 0.35, arp_amp), t + k * sub, pan=(0.35 if k % 2 else -0.35))
    # risers / hits
    if video == 'v1':
        d = 1.5; tt = t_arr(d); x = tt / d
        riser = fft_filter(noise(d), lo=800, hi=9000) * x ** 2 * 0.25 + 0.12 * np.sin(2 * np.pi * np.cumsum(220 + 900 * x ** 2) / SR) * x ** 2
        place(buf, riser, 27.0)
        place(buf, pad_chord([48, 55, 60, 64, 67], 5.5, 0.28, 3200), 55.0)
        place(buf, kick(1.0), 55.0)
        place(buf, kick(0.9), 29.0)
    else:
        d = 2.0; tt = t_arr(d); x = tt / d
        riser = fft_filter(noise(d), lo=800, hi=9000) * x ** 2 * 0.2
        place(buf, riser, 29.0)
        place(buf, kick(0.9), 31.0)
        place(buf, pad_chord([48, 55, 60, 64, 67], 7.0, 0.28, 3200), 52.5)
        place(buf, kick(1.0), 52.5)
    return buf


def load_vo(key):
    p = os.path.join(HERE, 'vo', key + '.mp3')
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', p, '-f', 'f32le', '-ac', '1', '-ar', str(SR), '-'], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def main(video):
    meta = json.load(open(os.path.join(HERE, f'{video}_meta.json')))
    n = int((DUR + 1) * SR)
    mus = music(video) * 0.35
    fx = np.zeros((2, n))
    vo = np.zeros((2, n))
    for c in meta['cues']:
        pan = 0.0
        place(fx, sfx(c['s']), c['t'], 0.42 * c['g'], pan)
    vo_spans = []
    for v in meta['vo']:
        s = load_vo(v['key'])
        s = s / (np.sqrt(np.mean(s[np.abs(s) > 0.01] ** 2)) + 1e-9) * 0.16
        place(vo, s, v['t'], 1.0)
        vo_spans.append((v['t'], v['t'] + len(s) / SR))
    # ducking envelope from VO spans (smooth)
    duck = np.ones(n)
    tt = np.arange(n) / SR
    for a, b in vo_spans:
        m = np.clip(np.minimum((tt - (a - 0.15)) / 0.15, ((b + 0.25) - tt) / 0.3), 0, 1)
        duck = np.minimum(duck, 1 - 0.55 * m)
    mus *= duck
    fx *= (0.55 + 0.45 * duck)
    mix = mus + fx + vo
    # fade in / out
    fi = int(0.05 * SR); mix[:, :fi] *= np.linspace(0, 1, fi)
    end = int(DUR * SR); fo = int(1.2 * SR)
    mix[:, end - fo:end] *= np.linspace(1, 0, fo)
    mix = mix[:, :end]
    # soft clip
    mix = np.tanh(mix)
    out = os.path.join(HERE, f'{video}_mix_raw.wav')
    pcm = (np.clip(mix.T, -1, 1) * 32767).astype('<i2')
    import wave
    with wave.open(out, 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    # stems for checks
    np.save(os.path.join(HERE, f'{video}_vospans.npy'), np.array(vo_spans))
    print('wrote', out, 'peak', float(np.max(np.abs(mix))))


if __name__ == '__main__':
    main(sys.argv[1])
