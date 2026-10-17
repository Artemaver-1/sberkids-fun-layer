#!/usr/bin/env python3
"""Макет приложения СберKids из экспорта Figma (PNG 2x) — для демо-оболочки.

Экраны берутся 1:1 из макетов организаторов. Скрипт вырезает каждый экран,
убирает системные полосы Android (статус-бар и навигацию), отделяет плавающий
таб-бар (с прозрачным фоном — он висит поверх прокрутки) и сохраняет всё в
ios/SberKidsFun/ShellAssets. Это только оболочка для демо: в продукт уходит
модуль FunLayer, а не эти картинки.

    python3 tools/build_shell_assets.py ~/Downloads/sberkids-figma
"""
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "ios", "SberKidsFun", "ShellAssets")
ANDROID_STATUS = 48   # 24 pt @2x
ANDROID_NAV = 96      # 48 pt @2x


def frames(path):
    """Все фреймы-экраны в экспорте раздела (по альфа-каналу, ниже заголовка раздела)."""
    im = Image.open(path).convert("RGBA")
    a = np.asarray(im)[..., 3] > 10
    a[:180] = False
    cols = a.any(axis=0)
    runs, start = [], None
    for x, v in enumerate(cols):
        if v and start is None:
            start = x
        if not v and start is not None:
            runs.append((start, x))
            start = None
    if start is not None:
        runs.append((start, len(cols)))
    result = []
    for x0, x1 in runs:
        if x1 - x0 < 300:
            continue
        rows = np.where(a[:, x0:x1].any(axis=1))[0]
        result.append(im.crop((x0, rows[0], x1, rows[-1] + 1)).convert("RGB"))
    return result


def android_nav_top(img):
    """Android-фреймы (360 pt) внизу имеют чёрную навигационную полосу → её верхняя граница."""
    if abs(img.width - 720) > 4:
        return None
    rows = np.asarray(img).astype(int).mean(axis=(1, 2))
    h = len(rows)
    y = h - 1
    while y > h - 60 and rows[y] >= 45:   # возможная кромка под полосой
        y -= 1
    end = y
    while y > h - 260 and rows[y] < 45:
        y -= 1
    return y + 1 if end - y >= 70 else None


def strip_system_bars(img):
    nav = android_nav_top(img)
    if nav is not None:
        return img.crop((0, ANDROID_STATUS, img.width, nav))
    return img


def find_tabbar(img):
    """Плавающий таб-бар: белая «пилюля» у нижнего края. → (y0, y1) или None."""
    a = np.asarray(img).astype(int)
    h, w = a.shape[:2]
    # колонки между иконками — там «пилюля» чисто белая (иконки и подписи не мешают)
    white = np.zeros(h, bool)
    for fx in (0.21, 0.405, 0.595, 0.765):
        white |= (a[:, int(w * fx), :] > 248).all(axis=1)
    y = h - 1
    while y > h - 500 and not white[y]:
        y -= 1
    if y <= h - 500:
        return None
    y1 = y + 1
    while y > 0 and white[y]:
        y -= 1
    y0 = y + 1
    if y1 - y0 < 120:
        return None
    # над «пилюлей» берём запас под украшения активной вкладки (корона, сердечко),
    # но не залезаем на контент: левый край над «пилюлей» должен быть однотонным фоном
    # таб-бар вырезаем с запасом сверху под украшения активной вкладки (фон станет прозрачным),
    # а контент — до самого верха «пилюли»: так ничего не обрезается
    return y0, max(0, y0 - 64), min(h, y1 + 24)


def transparent_background(img):
    """Фон вокруг «пилюли» → прозрачный (заливка от краёв по похожему цвету)."""
    rgba = np.dstack([np.asarray(img), np.full(img.size[::-1], 255, np.uint8)])
    h, w = rgba.shape[:2]
    rgb = rgba[..., :3].astype(int)
    seen = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        q.append((0, x)); q.append((h - 1, x))
    for y in range(h):
        q.append((y, 0)); q.append((y, w - 1))
    while q:
        y, x = q.popleft()
        if seen[y, x]:
            continue
        seen[y, x] = True
        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx]:
                if np.abs(rgb[ny, nx] - rgb[y, x]).sum() < 10 and rgb[ny, nx].min() < 252:
                    q.append((ny, nx))
    alpha = np.where(seen, 0, 255).astype(np.uint8)
    # мягкий край: полупрозрачная кайма в 1 px
    edge = np.zeros_like(seen)
    edge[1:-1, 1:-1] = seen[1:-1, 1:-1] & ~(seen[:-2, 1:-1] & seen[2:, 1:-1] & seen[1:-1, :-2] & seen[1:-1, 2:])
    alpha[edge] = 90
    rgba[..., 3] = alpha
    return Image.fromarray(rgba, "RGBA")


def save_jpeg(img, name, q=86):
    path = os.path.join(OUT, name)
    img.save(path, "JPEG", quality=q, optimize=True, progressive=True)
    return path


def main(src):
    os.makedirs(OUT, exist_ok=True)
    main_frames = frames(os.path.join(src, "Главный.png"))
    profile = frames(os.path.join(src, "Профиль.png"))
    content = frames(os.path.join(src, "Контент.png"))
    tasks = frames(os.path.join(src, "Дела.png"))
    piggy = frames(os.path.join(src, "Копилки.png"))
    history = frames(os.path.join(src, "История операций.png"))
    limits = frames(os.path.join(src, "Лимиты.png"))

    tabs = dict(zip(["main", "tasks", "content", "piggy"], main_frames))
    report = []
    for key, frame in tabs.items():
        img = strip_system_bars(frame)
        tb = find_tabbar(img)
        assert tb, f"нет таб-бара на {key}"
        pill, y0, y1 = tb
        transparent_background(img.crop((0, y0, img.width, y1))).save(os.path.join(OUT, f"tabbar_{key}.png"), optimize=True)
        save_jpeg(img.crop((0, 0, img.width, pill)), f"screen_{key}.jpg")
        report.append((key, img.width, pill, y1 - y0))

    pushed = {
        "profile": profile[0], "settings": profile[1], "design": profile[4],
        "history": history[0], "limits": limits[0],
        "content_snail": content[0], "content_cyber": content[1], "content_money": content[2],
        "content_story": content[3], "task_create": tasks[0], "task_story": tasks[1],
        "piggy_new": piggy[0], "piggy_goal": piggy[1],
    }
    for key, frame in pushed.items():
        img = strip_system_bars(frame)
        save_jpeg(img, f"screen_{key}.jpg")
        report.append((key, img.width, img.height, 0))

    for row in report:
        print("%-14s w=%d h=%d tab=%d" % row)
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
    print(f"ShellAssets: {total / 1024 / 1024:.1f} МБ (только демо-оболочка)")


if __name__ == "__main__":
    main(os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Downloads/sberkids-figma"))
