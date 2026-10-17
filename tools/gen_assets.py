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
    rgb = 0.12 + 0.95 * rgb
    if gold:
        gold_tint = np.array([1.0, 0.78, 0.25], np.float32)
        lum = rgb.mean(axis=2, keepdims=True)
        rgb = gold_tint * (0.55 + 0.6 * lum)

    # прозрачность: почти прозрачный центр, плотный обод (Френель)
    fres = rr ** 7
    alpha = 0.025 + 0.8 * fres
    if gold:
        alpha = 0.1 + 0.85 * rr ** 4
    # тонкая кромка: цветная, чуть темнее — видна и на белом фоне
    edge = np.exp(-((rr - 0.982) / 0.016) ** 2)
    rgb = rgb * (1 - edge[..., None] * 0.35)
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


def write_wav(name, samples):
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


def pop():
    n = int(SR * 0.11)
    t = np.arange(n) / SR
    f = 950 * np.exp(-t * 18) + 260
    phase = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(phase) * env(n, 0.002, 38)
    click = RNG.standard_normal(n) * env(n, 0.0005, 160) * 0.35
    return (s * 0.75 + click) * 0.9


def chime():
    buf = np.zeros(int(SR * 1.2))
    for i, f in enumerate((1318.5, 1661.2, 1975.5, 2637.0)):
        place(buf, tone(f, 0.9, ((1, 1.0), (2, 0.25), (3, 0.08)), decay=5.5) * 0.28, i * 0.075)
    # лёгкое «эхо»
    out = buf.copy()
    for d, g in ((0.09, 0.3), (0.17, 0.15)):
        k = int(d * SR)
        out[k:] += buf[:-k] * g
    return out * 0.8


def jungle():
    # ксилофонный бег по пентатонике — весёлая «тема» обезьянки
    notes = (523.3, 587.3, 659.3, 784.0, 880.0, 1046.5, 880.0, 1046.5, 1318.5)
    times = (0, 0.1, 0.2, 0.3, 0.4, 0.5, 1.9, 2.0, 2.15)
    buf = np.zeros(int(SR * 2.8))
    for f, at in zip(notes, times):
        place(buf, tone(f, 0.5, ((1, 1.0), (3.93, 0.35), (9.5, 0.08)), decay=9) * 0.3, at)
    # «бойнг» в момент ловли банана (~2.25 c от старта эффекта)
    n = int(SR * 0.45)
    t = np.arange(n) / SR
    f = 220 + 160 * np.sin(2 * np.pi * 9 * t) * np.exp(-t * 6) + 120 * t
    boing = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.004, 5) * 0.32
    place(buf, boing, 2.25)
    return buf


def whoo():
    # добрый «ууу» — мягко, без страшилок (0+/6+)
    n = int(SR * 1.5)
    t = np.arange(n) / SR
    glide = 380 + 140 * np.sin(np.pi * t / 1.5) + 8 * np.sin(2 * np.pi * 5.5 * t)
    s = np.sin(2 * np.pi * np.cumsum(glide) / SR) + 0.3 * np.sin(4 * np.pi * np.cumsum(glide) / SR)
    shape = np.sin(np.pi * np.clip(t / 1.5, 0, 1)) ** 1.5
    wind = np.convolve(RNG.standard_normal(n), np.ones(40) / 40, mode="same") * 0.6
    return (s * 0.22 + wind * 0.12) * shape


def giggle():
    buf = np.zeros(int(SR * 0.7))
    for i, f in enumerate((1250, 1150, 1080, 980)):
        n = int(SR * 0.09)
        t = np.arange(n) / SR
        ff = f * (1 + 0.06 * np.sin(2 * np.pi * 30 * t))
        s = np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.sin(np.pi * t / t[-1]) * 0.3
        place(buf, s, i * 0.12)
    return buf


def main():
    os.makedirs(OUT, exist_ok=True)
    save_png(bubble(320, gold=False, seed=11), "bubble.png")
    save_png(bubble(320, gold=True, seed=23), "bubble_gold.png")
    save_png(snowflake(160), "snowflake.png")
    save_png(fog(256), "fog.png")
    write_wav("pop.wav", pop())
    write_wav("chime.wav", chime())
    write_wav("jungle.wav", jungle())
    write_wav("whoo.wav", whoo())
    write_wav("giggle.wav", giggle())


if __name__ == "__main__":
    main()
