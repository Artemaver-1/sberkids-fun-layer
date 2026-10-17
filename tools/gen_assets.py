#!/usr/bin/env python3
"""Генератор ресурсов слоя приколов: спрайты и звуки.

Всё рисуется и синтезируется процедурно — никаких чужих картинок и звуков,
поэтому нет вопросов с правами (требование ТЗ про интеллектуальную собственность).

    python3 tools/gen_assets.py            # → cdn/fun-layer/v1/assets/

Зависимости только для генерации (в продукт не попадают): numpy, pillow.
"""
import math
import os
import struct
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "cdn", "fun-layer", "v1", "assets")
RNG = np.random.default_rng(2026)


def save_png(arr, name):
    img = Image.fromarray(np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA")
    path = os.path.join(OUT, name)
    img.save(path, optimize=True)
    print(f"{name:18s} {os.path.getsize(path):>7d} B")


# ---------------------------------------------------------------- пузырь

def smooth_noise(size, scale, seed):
    """Гладкий шум: случайная сетка + бикубическое растяжение."""
    rng = np.random.default_rng(seed)
    small = rng.random((scale, scale)).astype(np.float32)
    img = Image.fromarray((small * 255).astype(np.uint8), "L").resize((size, size), Image.BICUBIC)
    return np.asarray(img, np.float32) / 255.0


def bubble(size=320, gold=False, seed=1):
    ss = 2  # суперсэмплинг для гладкого края
    n = size * ss
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    cx = cy = (n - 1) / 2
    R = n * 0.47
    dx, dy = (x - cx) / R, (y - cy) / R
    r = np.sqrt(dx * dx + dy * dy)
    inside = r <= 1.0
    rr = np.clip(r, 0, 1)
    cos_t = np.sqrt(1 - rr * rr)

    # толщина плёнки: тоньше сверху (стекает вниз) + завихрения
    swirl = smooth_noise(n, 7, seed) * 0.6 + smooth_noise(n, 15, seed + 1) * 0.4
    thickness = 260 + 520 * (0.5 + 0.5 * dy) + 380 * swirl  # нм
    nfilm = 1.33
    rgb = np.zeros((n, n, 3), np.float32)
    for i, lam in enumerate((650.0, 540.0, 450.0)):
        phase = 4 * math.pi * nfilm * thickness * np.sqrt(1 - (1 - cos_t ** 2) / nfilm ** 2) / lam
        rgb[..., i] = np.sin(phase / 2) ** 2
    # насыщенность и яркость в духе макетов СберKids (лайм/лаванда/голубой)
    # насыщенные цвета плёнки: на светлом фоне СберKids пузырь должен читаться
    rgb = np.clip(1.25 * rgb - 0.1, 0, 1)
    if gold:
        gold_tint = np.array([1.0, 0.78, 0.25], np.float32)
        lum = rgb.mean(axis=2, keepdims=True)
        rgb = gold_tint * (0.55 + 0.6 * lum)

    # прозрачность: почти прозрачный центр, плотный обод (Френель)
    fres = rr ** 5
    alpha = 0.06 + 0.85 * fres
    if gold:
        alpha = 0.1 + 0.85 * rr ** 4
    # тонкая кромка: цветная, чуть темнее — видна и на белом фоне
    edge = np.exp(-((rr - 0.982) / 0.016) ** 2)
    rgb = rgb * (1 - edge[..., None] * 0.5)
    alpha = np.maximum(alpha, edge * 0.95)

    # блики: окно сверху-слева и маленький снизу-справа
    def spot(ox, oy, sx, sy, rot, strength):
        c, s = math.cos(rot), math.sin(rot)
        ux = (dx - ox) * c + (dy - oy) * s
        uy = -(dx - ox) * s + (dy - oy) * c
        return strength * np.exp(-((ux / sx) ** 2 + (uy / sy) ** 2) ** 1.4)

    hl = spot(-0.42, -0.45, 0.30, 0.15, -0.75, 1.0) + spot(0.5, 0.55, 0.12, 0.06, -0.75, 0.6)
    hl += spot(-0.12, -0.70, 0.08, 0.05, 0.0, 0.5)
    rgb = rgb * (1 - hl[..., None]) + hl[..., None]
    alpha = np.clip(alpha + hl * 0.9, 0, 1)

    alpha = np.where(inside, alpha, 0)
    out = np.dstack([np.clip(rgb, 0, 1), alpha])
    img = Image.fromarray((out * 255).astype(np.uint8), "RGBA").resize((size, size), Image.LANCZOS)
    return np.asarray(img, np.float32) / 255.0


# ---------------------------------------------------------------- снежинка

def snowflake(size=160):
    ss = 4
    n = size * ss
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = n / 2
    L = n * 0.44
    w = int(n * 0.035)
    for k in range(6):
        a = k * math.pi / 3 - math.pi / 2
        ex, ey = c + L * math.cos(a), c + L * math.sin(a)
        d.line([(c, c), (ex, ey)], fill=(255, 255, 255, 255), width=w)
        for t, bl in ((0.42, 0.26), (0.68, 0.18), (0.86, 0.1)):
            px, py = c + L * t * math.cos(a), c + L * t * math.sin(a)
            for side in (-1, 1):
                b = a + side * math.pi / 3.2
                d.line([(px, py), (px + L * bl * math.cos(b), py + L * bl * math.sin(b))],
                       fill=(255, 255, 255, 255), width=int(w * 0.8))
        d.ellipse([ex - w, ey - w, ex + w, ey + w], fill=(255, 255, 255, 255))
    d.regular_polygon((c, c, n * 0.07), 6, fill=(255, 255, 255, 255))
    glow = img.filter(ImageFilter.GaussianBlur(n * 0.02))
    base = Image.new("RGBA", (n, n), (180, 220, 255, 0))
    base = Image.alpha_composite(base, glow)
    base = Image.alpha_composite(base, img)
    base = base.resize((size, size), Image.LANCZOS)
    return np.asarray(base, np.float32) / 255.0


# ---------------------------------------------------------------- туман

def fog(size=256):
    """Бесшовная текстура тумана: фрактальный шум на периодической решётке."""
    acc = np.zeros((size, size), np.float32)
    amp, total = 1.0, 0.0
    for octave, cells in enumerate((4, 8, 16, 32)):
        grid = RNG.random((cells, cells)).astype(np.float32)
        # периодическая бикубическая интерполяция: склеиваем края перед растяжением
        tiled = np.tile(grid, (3, 3))
        big = Image.fromarray((tiled * 255).astype(np.uint8), "L").resize((size * 3, size * 3), Image.BICUBIC)
        layer = np.asarray(big, np.float32)[size:2 * size, size:2 * size] / 255.0
        acc += layer * amp
        total += amp
        amp *= 0.5
    acc /= total
    acc = np.clip((acc - 0.35) / 0.5, 0, 1) ** 1.6
    rgba = np.dstack([np.ones_like(acc), np.ones_like(acc), np.ones_like(acc), acc * 0.9])
    return rgba


# ---------------------------------------------------------------- звуки

SR = 22050


def write_wav(name, samples, peak=0.8):
    samples = samples / (np.abs(samples).max() + 1e-9) * peak   # одинаковая громкость всех звуков
    samples = np.clip(samples, -1, 1)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((samples * 32767).astype("<i2").tobytes())
    print(f"{name:18s} {os.path.getsize(path):>7d} B")


def env(n, attack=0.005, decay=8.0):
    t = np.arange(n) / SR
    a = np.clip(t / attack, 0, 1)
    return a * np.exp(-t * decay)


def tone(freq, dur, partials=((1, 1.0),), decay=6.0, attack=0.004):
    n = int(SR * dur)
    t = np.arange(n) / SR
    s = sum(a * np.sin(2 * np.pi * freq * k * t) for k, a in partials)
    return s * env(n, attack, decay)


def place(buf, s, at):
    i = int(at * SR)
    buf[i:i + len(s)] += s[:max(0, len(buf) - i)]


def biquad_bandpass(x, f0, q):
    """Резонатор (RBJ band-pass) — из таких собираются форманты голоса."""
    w0 = 2 * math.pi * f0 / SR
    alpha = math.sin(w0) / (2 * q)
    b0, b2 = alpha, -alpha
    a0, a1, a2 = 1 + alpha, -2 * math.cos(w0), 1 - alpha
    b0, b2, a1, a2 = b0 / a0, b2 / a0, a1 / a0, a2 / a0
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, xi in enumerate(x):
        yi = b0 * xi + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, xi
        y2, y1 = y1, yi
        y[i] = yi
    return y


VOWELS = {  # (частота форманты, добротность, вес)
    "u": [(330, 6, 1.0), (820, 8, 0.5), (2400, 12, 0.15)],
    "o": [(480, 6, 1.0), (900, 8, 0.6), (2500, 12, 0.15)],
    "a": [(800, 5, 1.0), (1250, 7, 0.7), (2700, 12, 0.2)],
    "i": [(300, 6, 0.8), (2300, 10, 0.9), (3000, 12, 0.4)],
}


def voice(f0_start, f0_end, dur, vowel, vibrato=6.0, vib_depth=0.03, breath=0.04, attack=0.03, release=0.08):
    """Мультяшный голос: гармонический источник + форманты гласной."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    glide = f0_start + (f0_end - f0_start) * (t / dur) ** 0.7
    f0 = glide * (1 + vib_depth * np.sin(2 * np.pi * vibrato * t))
    phase = 2 * np.pi * np.cumsum(f0) / SR
    src = np.zeros(n)
    for k in range(1, 30):
        if f0_end * k > 6000:
            break
        src += np.sin(k * phase) / k ** 1.1
    src += RNG.standard_normal(n) * breath
    out = sum(w * biquad_bandpass(src, f, q) for f, q, w in VOWELS[vowel])
    envl = np.minimum(1, t / attack) * np.minimum(1, (dur - t) / release)
    out = out * np.clip(envl, 0, 1)
    return out / (np.abs(out).max() + 1e-9)


def sweep_bandpass(x, f_curve, q):
    """Полосовой фильтр с плавающей частотой (свист, «вжух»)."""
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        if i % 32 == 0:
            w0 = 2 * math.pi * f_curve[i] / SR
            alpha = math.sin(w0) / (2 * q)
            a0 = 1 + alpha
            b0, b2, a1, a2 = alpha / a0, -alpha / a0, -2 * math.cos(w0) / a0, (1 - alpha) / a0
        yi = b0 * x[i] + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, x[i]
        y2, y1 = y1, yi
        y[i] = yi
    return y


def room(x, mix=0.18):
    """Лёгкое «пространство»: несколько затухающих отражений."""
    out = x.copy()
    for ms, g in ((23, 0.45), (37, 0.32), (53, 0.22), (79, 0.14)):
        k = int(SR * ms / 1000)
        out[k:] += x[:-k] * g * mix * 2
    return out


def lowpass(x, cutoff):
    """Однополюсный ФНЧ — смягчает «цифровую» резкость."""
    a = math.exp(-2 * math.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i, xi in enumerate(x):
        acc = (1 - a) * xi + a * acc
        y[i] = acc
    return y


def pop():
    """ASMR-лопание мыльного пузыря: мягкий шумовой «пфт», влажное потрескивание, тёплый низ.
    Без тональных «пиу» — звук шумовой и короткий, как у настоящей плёнки у микрофона."""
    n = int(SR * 0.11)
    t = np.arange(n) / SR
    noise = RNG.standard_normal(n)
    puff = biquad_bandpass(noise, 2300, 0.9) * np.exp(-t * 140) * np.minimum(1, t / 0.0008)
    air = lowpass(noise, 5000) * np.exp(-t * 60) * 0.18
    body = np.sin(2 * np.pi * 190 * t + 2 * np.exp(-t * 80)) * np.exp(-t * 85) * 0.55
    wet = np.zeros(n)
    for at, amp in ((0.006, 0.45), (0.014, 0.3), (0.025, 0.18), (0.039, 0.1)):
        k = int(at * SR)
        m = int(0.0016 * SR)
        wet[k:k + m] += biquad_bandpass(RNG.standard_normal(m), 4200, 1.2) * amp * np.hanning(m)
    out = puff * 0.9 + air + body + wet
    return lowpass(room(out, 0.08), 9000)


def bubbles():
    """ASMR-бульканье: тихие пузырьки под водой — низкие, мягкие, с влажным шорохом."""
    buf = np.zeros(int(SR * 1.5))
    for i in range(11):
        n = int(SR * 0.18)
        t = np.arange(n) / SR
        f0 = RNG.uniform(180, 480)
        f = f0 * (1 + 0.35 * (1 - np.exp(-t * 22)))
        b = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * RNG.uniform(16, 26)) * np.minimum(1, t / 0.008)
        place(buf, b * RNG.uniform(0.25, 0.6), i * 0.12 + RNG.uniform(0, 0.06))
    n = len(buf)
    hiss = lowpass(RNG.standard_normal(n), 1800) * 0.05 * np.sin(np.pi * np.arange(n) / n) ** 2
    out = lowpass(buf, 2400) + hiss
    return room(out, 0.25)


def _tone(freqs, dur, decay, amps=None):
    n = int(SR * dur)
    t = np.arange(n) / SR
    amps = amps or [1.0] * len(freqs)
    return sum(a * np.sin(2 * np.pi * f * t) for f, a in zip(freqs, amps)) * np.exp(-t * decay) * np.minimum(1, t / 0.002)


def step(pitch=1.0):
    return _tone([1300 * pitch, 2700 * pitch], 0.06, 95, [1.0, 0.35]) * 0.5


def boing(f_start, f_end, dur=0.35):
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = f_start + (f_end - f_start) * (1 - np.exp(-t * 9)) + 40 * np.sin(2 * np.pi * 14 * t) * np.exp(-t * 7)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7) * np.minimum(1, t / 0.004)


def thud():
    n = int(SR * 0.22)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * np.cumsum(120 * np.exp(-t * 12) + 60) / SR) * np.exp(-t * 22)
    dust = biquad_bandpass(RNG.standard_normal(n), 700, 0.7) * np.exp(-t * 30) * 0.35
    return body + dust


def whoosh(dur=0.5):
    n = int(SR * dur)
    t = np.arange(n) / SR
    curve = 400 + 1900 * np.sin(np.pi * t / dur) ** 1.5
    w = sweep_bandpass(RNG.standard_normal(n), curve, 1.6)
    return w * np.sin(np.pi * t / dur) ** 2 * 0.9


def sparkle():
    buf = np.zeros(int(SR * 0.9))
    for i, f in enumerate((2093.0, 2637.0, 3136.0, 4186.0)):
        place(buf, _tone([f, f * 2.01], 0.6, 7, [1.0, 0.2]) * 0.22, i * 0.055)
    return buf


def marimba(f, dur=0.45):
    return _tone([f, f * 3.93, f * 9.5], dur, 9, [1.0, 0.3, 0.06])


def chime():
    buf = np.zeros(int(SR * 1.2))
    for i, f in enumerate((1318.5, 1661.2, 1975.5, 2637.0)):
        place(buf, tone(f, 0.9, ((1, 1.0), (2, 0.25), (3, 0.08)), decay=5.5) * 0.28, i * 0.075)
    out = buf.copy()
    for d, g in ((0.09, 0.3), (0.17, 0.15)):
        k = int(d * SR)
        out[k:] += buf[:-k] * g
    return out * 0.8


def jungle():
    """Звуковая дорожка обезьянки, синхронная с кадрами Lottie (60 fps):
    топот → пружинка прыжка (к. 64) → удар о стену (к. 82) → отталкивание (к. 90) →
    «вжух» сальто → «поп» + искры при ловле банана (к. 127) → приземление (к. 146) →
    прыжок радости и ксилофон → убегает с топотом."""
    fr = lambda f: f / 60
    buf = np.zeros(int(SR * 4.6))
    for i, at in enumerate(np.arange(0.1, fr(62), 0.183)):
        place(buf, step(1.0 if i % 2 else 0.86) * 0.55, at)
    place(buf, boing(260, 620) * 0.38, fr(64))
    place(buf, thud() * 0.45, fr(82))
    place(buf, step(0.7) * 0.6, fr(82))
    place(buf, boing(330, 820, 0.3) * 0.36, fr(90))
    place(buf, whoosh(0.52) * 0.55, fr(92))
    place(buf, pop() * 0.6, fr(127))
    place(buf, sparkle(), fr(128))
    place(buf, thud() * 0.55, fr(146))
    place(buf, boing(420, 760, 0.25) * 0.25, fr(160))
    place(buf, step(0.9) * 0.4, fr(184))
    for i, f in enumerate((783.99, 987.77, 1174.66, 1567.98)):
        place(buf, marimba(f) * 0.32, fr(150) + i * 0.085)
    for i, at in enumerate(np.arange(fr(198), fr(258), 0.183)):
        fade = 1 - i / 8
        place(buf, step(1.0 if i % 2 else 0.86) * 0.5 * max(0.15, fade), at)
    return room(buf, 0.15)


def whoo():
    """Добрые призраки: двухголосое «у-у-у» с вибрато, дыхание тумана и искорки."""
    dur = 1.9
    a = voice(250, 330, dur, "u", vibrato=5, vib_depth=0.06, breath=0.08, attack=0.35, release=0.6)
    b = voice(375, 470, dur - 0.2, "o", vibrato=5.5, vib_depth=0.06, breath=0.08, attack=0.4, release=0.6)
    buf = np.zeros(int(SR * 2.3))
    place(buf, a * 0.32, 0.0)
    place(buf, b * 0.2, 0.18)
    n = len(buf)
    air = biquad_bandpass(RNG.standard_normal(n), 900, 0.8) * 0.06 * np.sin(np.pi * np.arange(n) / n) ** 2
    buf += air
    for i, f in enumerate((1568.0, 2093.0, 2637.0)):
        place(buf, tone(f, 0.5, ((1, 1.0), (2, 0.2)), decay=7) * 0.06, 1.5 + i * 0.12)
    return buf


def giggle():
    """Хихиканье призрака: «хи-хи-хи»."""
    buf = np.zeros(int(SR * 0.7))
    for i, f in enumerate((1050, 980, 920, 860)):
        place(buf, voice(f, f * 0.92, 0.075, "i", vibrato=0.1, vib_depth=0, breath=0.12, attack=0.008, release=0.03) * 0.28,
              i * 0.11)
    return buf


def main():
    os.makedirs(OUT, exist_ok=True)
    save_png(bubble(320, gold=False, seed=11), "bubble.png")
    save_png(bubble(320, gold=True, seed=23), "bubble_gold.png")
    save_png(snowflake(160), "snowflake.png")
    save_png(fog(256), "fog.png")
    write_wav("pop.wav", pop())
    write_wav("bubbles.wav", bubbles())
    write_wav("chime.wav", chime())
    write_wav("jungle.wav", jungle())
    write_wav("whoo.wav", whoo())
    write_wav("giggle.wav", giggle())


if __name__ == "__main__":
    main()
