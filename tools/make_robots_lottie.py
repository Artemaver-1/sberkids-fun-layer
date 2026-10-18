#!/usr/bin/env python3
"""Процедурная Lottie-сцена «Цех роботов» — четвёртая пасхалка.

Интерфейс отъезжает вбок (это делает приложение), а под ним — «внутренности»
СберKids: трёхэтажное здание в разрезе. Серверы мигают, по кабелям бегут
данные, роботы печатают код и везут монетки. Один робот замечает ребёнка
(ломает четвёртую стену), катится к красной кнопке и жмёт её — включается
сирена, и приложение захлопывает интерфейс обратно.

    python3 tools/make_robots_lottie.py   # → cdn/fun-layer/v1/assets/robots.json
"""
import json
import math
import os
import random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "cdn", "fun-layer", "v1", "assets", "robots.json")

W, H, FR = 390, 844, 60
OP = 515
STEP = 2
RND = random.Random(4)

# сюжет (кадры, 60 fps). Нажатие кнопки = closeAtMs в конфиге минус ~0,25 c
WORK = 105        # +1,75 c — дольше смотрим, как роботы работают
NOTICE = 192 + WORK   # ≈ 4,95 c — робот замечает зрителя
BANG = 206 + WORK     # «!»
OTHERS = 228 + WORK   # остальные оборачиваются
ROLL0, ROLL1 = 252 + WORK, 312 + WORK
REACH = 318 + WORK
PRESS = 330 + WORK    # ≈ 7,25 c — нажатие

FLOORS = [(66, 290), (306, 526), (542, 762)]   # (верх, перекрытие)


def rgb(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]


WALL_TOP, WALL_BOT = rgb("#252C63"), rgb("#12153A")
ROOM_HI, ROOM_LO = rgb("#2E3778"), rgb("#1C2153")
SLAB_TOP, SLAB_FRONT, SLAB_EDGE = rgb("#7079D6"), rgb("#3B4291"), rgb("#A4ACFF")
RACK_HI, RACK_LO, RACK_SIDE, RACK_TOP = rgb("#353D80"), rgb("#1E2352"), rgb("#171B44"), rgb("#4B54A6")
LED = [rgb("#4CFFB0"), rgb("#46D7FF"), rgb("#FFC94A"), rgb("#FF6BA0")]
DESK_TOP, DESK_FRONT = rgb("#8C93E3"), rgb("#545BAE")
SCREEN_HI, SCREEN_LO = rgb("#22407F"), rgb("#121C46")
CODE = [rgb("#7DF9FF"), rgb("#B6FF5C"), rgb("#FFD86B"), rgb("#FF8FC8")]
BOT_HI, BOT_LO = rgb("#FFFFFF"), rgb("#B9B2F3")
VISOR = rgb("#1B1F44")
EYE = rgb("#62F3FF")
PINK = rgb("#FF6BA0")
WHEEL = rgb("#2A2E5F")
RED, RED_HI, RED_DARK = rgb("#FF3B4E"), rgb("#FF9AA5"), rgb("#A3121F")
YELLOW, INK = rgb("#FFD23F"), rgb("#1A1A24")
GOLD, GOLD_HI = rgb("#F2B23A"), rgb("#FFE58A")
CUBE = [rgb("#5CD0FF"), rgb("#2E8FD6"), rgb("#9BE7FF")]
GEAR_HI, GEAR_LO = rgb("#8E96E8"), rgb("#4C539F")
CABLES = [rgb("#44E0FF"), rgb("#FF5FA2"), rgb("#B6FF5C")]
WHITE = [1, 1, 1]
LAMP = rgb("#FFF3C4")

# ------------------------------------------------------------------ утилиты Lottie


def static(v):
    return {"a": 0, "k": v}


def r2(v):
    return round(v, 2)


def anim(frames, values, dims=1, hold=False):
    vals = [[r2(x) for x in v] if dims > 1 else [r2(v)] for v in values]
    if all(v == vals[0] for v in vals):
        return static(vals[0] if dims > 1 else vals[0][0])
    keys, prev = [], None
    for idx, (f, s) in enumerate(zip(frames, vals)):
        nxt = vals[idx + 1] if idx + 1 < len(vals) else None
        if s == prev and nxt == s:
            continue
        k = {"t": f, "s": s}
        if hold:
            k["h"] = 1
        elif dims > 1:
            k["i"], k["o"] = {"x": 1, "y": 1}, {"x": 0, "y": 0}
        else:
            k["i"], k["o"] = {"x": [1], "y": [1]}, {"x": [0], "y": [0]}
        keys.append(k)
        prev = s
    keys[-1].pop("i", None)
    keys[-1].pop("o", None)
    return {"a": 1, "k": keys}


FRAMES = list(range(0, OP + 1, STEP))
if FRAMES[-1] != OP:
    FRAMES.append(OP)


def track(fn, dims=1, hold=False):
    return anim(FRAMES, [fn(f) for f in FRAMES], dims, hold)


def tr(p=(0, 0), s=(100, 100), r=0, o=100):
    return {"ty": "tr", "p": static(list(p)), "a": static([0, 0]), "s": static(list(s)),
            "r": static(r), "o": static(o), "sk": static(0), "sa": static(0)}


def fill(c, o=100):
    return {"ty": "fl", "c": static(c + [1]), "o": static(o), "r": 1, "bm": 0}


def stroke(c, w, o=100):
    return {"ty": "st", "c": static(c + [1]), "o": static(o), "w": static(w), "lc": 2, "lj": 2, "bm": 0}


def _nudge(start, end):
    """Строго вертикальный/горизонтальный вектор градиента ломает часть рендереров Lottie —
    сдвигаем конец на полпикселя (на вид без разницы)."""
    ex, ey = end
    if abs(ex - start[0]) < 1e-6:
        ex += 0.5
    if abs(ey - start[1]) < 1e-6:
        ey += 0.5
    return (ex, ey)


def grad(stops, start, end, kind=1):
    end = _nudge(start, end)
    k = []
    for pos, c in stops:
        k += [pos] + list(c)
    return {"ty": "gf", "o": static(100), "r": 1, "bm": 0, "t": kind, "s": static(list(start)),
            "e": static(list(end)), "h": static(0), "a": static(0), "g": {"p": len(stops), "k": static(k)}}


def grad_alpha(c, a0, a1, start, end, kind=1):
    """Градиент одного цвета с прозрачностью (свет ламп, лучи маяков)."""
    end = _nudge(start, end)
    k = [0] + list(c) + [1] + list(c) + [0, a0, 1, a1]
    return {"ty": "gf", "o": static(100), "r": 1, "bm": 0, "t": kind, "s": static(list(start)),
            "e": static(list(end)), "h": static(0), "a": static(0), "g": {"p": 2, "k": static(k)}}


def ellipse(x, y, w, h):
    return {"ty": "el", "p": static([x, y]), "s": static([w, h]), "d": 1}


def rect(x, y, w, h, r=0):
    return {"ty": "rc", "p": static([x, y]), "s": static([w, h]), "r": static(r), "d": 1}


def poly(pts, closed=True):
    return {"ty": "sh", "ks": static({"c": closed, "v": [list(p) for p in pts],
                                      "i": [[0, 0] for _ in pts], "o": [[0, 0] for _ in pts]})}


def curve(points, closed=False):
    return {"ty": "sh", "ks": static({"c": closed, "v": [[p[0], p[1]] for p in points],
                                      "i": [list(p[2]) for p in points], "o": [list(p[3]) for p in points]})}


def group(items, name="g", transform=None):
    return {"ty": "gr", "nm": name, "it": items + [transform or tr()]}


LAYERS = []   # снизу вверх; в конце разворачиваем (в Lottie первый слой — верхний)


def layer(name, shapes=None, parent=None, null=False, ip=0, op=OP, p=(0, 0), r=0, s=(100, 100), o=100):
    L = {"ddd": 0, "ty": 3 if null else 4, "nm": name, "sr": 1, "ao": 0,
         "ks": {"o": static(o) if not isinstance(o, dict) else o,
                "r": static(r) if not isinstance(r, dict) else r,
                "p": static([p[0], p[1], 0]) if not isinstance(p, dict) else p,
                "a": static([0, 0, 0]),
                "s": static([s[0], s[1], 100]) if not isinstance(s, dict) else s},
         "ip": ip, "op": op, "st": 0, "bm": 0, "_parent": parent}
    if not null:
        L["shapes"] = shapes or []
    LAYERS.append(L)
    return L


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def ease_back(t):
    t = max(0.0, min(1.0, t))
    c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (t - 1) ** 3 + c1 * (t - 1) ** 2

# ------------------------------------------------------------------ здание


def building():
    items = [group([rect(W / 2, H / 2, W, H), grad([(0, WALL_TOP), (1, WALL_BOT)], (0, 0), (0, H))], "wall")]
    for top, slab in FLOORS:
        h = slab - top
        items.append(group([rect(W / 2, top + h / 2, W - 40, h, 6),
                            grad([(0, ROOM_HI), (1, ROOM_LO)], (0, top), (0, slab))], "room"))
        # панели задней стены
        items.append(group([poly([(x, top + 8), (x, slab - 4)], closed=False) for x in range(44, 360, 46)]
                           + [stroke(rgb("#3A4390"), 1.2, 55)], "panels"))
        # лампа под потолком
        items.append(group([rect(W / 2, top + 6, 150, 7, 3.5), fill(LAMP)], "lamp"))
    for _, slab in FLOORS:
        items.append(group([poly([(0, slab + 6), (W, slab + 6), (W, slab + 18), (0, slab + 18)]),
                            fill(SLAB_FRONT)], "slab_front"))
        items.append(group([poly([(14, slab), (W - 14, slab), (W, slab + 6), (0, slab + 6)]),
                            fill(SLAB_TOP)], "slab_top"))
        items.append(group([poly([(14, slab), (W - 14, slab)], closed=False), stroke(SLAB_EDGE, 1.5, 80)], "edge"))
    # подвал: трубы
    items.append(group([rect(W / 2, 800, W, 6, 3), rect(W / 2, 818, W, 4, 2), fill(rgb("#3F4794"))], "pipes"))
    items.append(group([rect(374, 420, 10, 800, 5), grad([(0, rgb("#6E77D3")), (1, rgb("#383F8C"))], (369, 0), (379, 0))], "riser"))
    layer("building", [it for it in reversed(items)])


def cables():
    paths = []
    for i, c in enumerate(CABLES):
        x = 12 + i * 6
        paths.append(group([poly([(x, 30), (x, H)], closed=False), stroke(c, 2.6, 70)], f"cable{i}"))
    layer("cables", paths)
    # импульсы данных бегут сверху вниз
    for i, c in enumerate(CABLES):
        x = 12 + i * 6
        for k in range(3):
            period = 84 + i * 12
            off = k * period / 3 + i * 9
            pos = track(lambda f, off=off, period=period, x=x: [x, 30 + (H - 30) * (((f + off) % period) / period), 0], 3)
            layer(f"pulse{i}_{k}", [group([ellipse(0, 0, 11, 11), fill(c, 25)]), group([ellipse(0, 0, 5, 5), fill(WHITE)])], p=pos)


def box3d(cx, bottom, w, h, depth, front, side, top, name):
    """Объёмный ящик: фронт + боковина + крышка (вид чуть сверху-справа)."""
    x0, x1, y0 = cx - w / 2, cx + w / 2, bottom - h
    return [
        group([poly([(x0, y0), (x1, y0), (x1 + depth, y0 - depth * 0.6), (x0 + depth, y0 - depth * 0.6)]), fill(top)], name + "_top"),
        group([poly([(x1, y0), (x1 + depth, y0 - depth * 0.6), (x1 + depth, bottom - depth * 0.6), (x1, bottom)]), fill(side)], name + "_side"),
        group([rect(cx, y0 + h / 2, w, h, 2), grad([(0, front[0]), (1, front[1])], (cx, y0), (cx, bottom))], name + "_front"),
    ]


def servers():
    top, slab = FLOORS[0]
    for ri, cx in enumerate((78, 146, 214, 282)):
        shapes = []
        bottom = slab - 1
        h = 158
        leds = []
        for r in range(7):
            for col in range(3):
                x = cx - 15 + col * 15
                y = bottom - h + 18 + r * 20
                color = RND.choice(LED)
                # мигание: включено/выключено ступеньками
                state, nxt, vals = 1, 0, []
                for f in FRAMES:
                    if f >= nxt:
                        state = 1 - state if RND.random() < 0.7 else state
                        nxt = f + RND.randint(6, 26)
                    vals.append(100 if state else 18)
                t = tr()
                t["o"] = anim(FRAMES, vals, hold=True)
                leds.append(group([ellipse(x, y, 5, 5), fill(color)], f"led{r}{col}", t))
            shapes.append(group([rect(cx, bottom - h + 18 + r * 20 + 7, 46, 2, 1), fill(rgb("#141838"))], f"vent{r}"))
        layer(f"rack{ri}", leds + shapes + box3d(cx, bottom, 54, h, 9, (RACK_HI, RACK_LO), RACK_SIDE, RACK_TOP, "rack"))


def monitor(cx, desk_y, name):
    sx, sy = cx, desk_y - 34
    lines = []
    for i in range(6):
        wdt = RND.choice([14, 20, 26, 32, 40])
        x = sx - 26 + wdt / 2 + RND.choice([0, 0, 6, 12])
        y = sy - 13 + i * 5
        vals = []
        for f in FRAMES:
            phase = (f // 7) % 9
            vals.append(100 if phase >= i else 0)
        t = tr()
        t["o"] = anim(FRAMES, vals, hold=True)
        lines.append(group([rect(x, y, wdt, 2.6, 1.3), fill(CODE[i % len(CODE)])], f"code{i}", t))
    cur = tr()
    cur["o"] = anim(FRAMES, [100 if (f // 15) % 2 == 0 else 0 for f in FRAMES], hold=True)
    lines.append(group([rect(sx + 22, sy + 13, 5, 3, 1), fill(WHITE)], "cursor", cur))
    layer(name, lines + [
        group([rect(sx, sy, 62, 38, 5), grad([(0, SCREEN_HI), (1, SCREEN_LO)], (sx, sy - 19), (sx, sy + 19))], "screen"),
        group([rect(sx, sy, 70, 46, 8), fill(rgb("#E9E7FF"))], "bezel"),
        group([rect(sx, desk_y - 6, 8, 12, 2), rect(sx, desk_y - 1, 26, 3, 1.5), fill(rgb("#C9C5F2"))], "stand"),
        group([rect(sx - 46, desk_y - 3, 30, 5, 2), fill(rgb("#D8D5FA"))], "keyboard"),
    ])


def desks():
    top, slab = FLOORS[1]
    for name, x0, x1 in (("desk1", 30, 168), ("desk2", 182, 320)):
        y = 470
        cx = (x0 + x1) / 2
        layer(name, [
            group([rect(x0 + 10, (y + slab) / 2, 6, slab - y, 2), rect(x1 - 10, (y + slab) / 2, 6, slab - y, 2), fill(DESK_FRONT)], "legs"),
            group([rect(cx, y + 5, x1 - x0, 9, 2), fill(DESK_FRONT)], "front"),
            group([poly([(x0, y), (x1, y), (x1 + 6, y - 5), (x0 + 6, y - 5)]), fill(DESK_TOP)], "top"),
        ])
    monitor(122, 465, "monitor1")
    monitor(274, 465, "monitor2")


def red_button():
    top, slab = FLOORS[1]
    cx, bottom = 352, slab - 1
    stripes = []
    for i in range(6):
        y0 = bottom - 52 + i * 9
        stripes.append(poly([(cx - 15, y0), (cx - 15 + 9, y0), (cx - 15 + 18, y0 + 9), (cx - 15 + 9, y0 + 9)]))
    press = tr()
    press["p"] = track(lambda f: [0, 4 if PRESS <= f < PRESS + 40 else (2 if f >= PRESS + 40 else 0)], 2)
    flash = tr()
    flash["o"] = track(lambda f: 0 if f < PRESS else 70 * max(0, math.sin((f - PRESS) / 60 * math.pi * 4)) ** 2)
    layer("button", [
        group([ellipse(cx, bottom - 64, 70, 40), grad_alpha(RED_HI, 0.9, 0, (cx, bottom - 64), (cx + 34, bottom - 64), 2)], "flash", flash),
        group([ellipse(cx - 5, bottom - 68, 9, 4), fill(WHITE, 70),
               ellipse(cx, bottom - 64, 30, 16), grad([(0, RED_HI), (0.5, RED), (1, RED_DARK)], (cx - 6, bottom - 70), (cx + 10, bottom - 58), 2)], "cap", press),
        group([rect(cx, bottom - 58, 34, 6, 3), fill(rgb("#C9C5F2"))], "rim"),
        group(stripes + [fill(INK)], "stripes"),
        group([rect(cx, bottom - 27, 30, 54, 3), fill(YELLOW)], "pedestal"),
    ])


def gear_path(r, teeth):
    pts = []
    for i in range(teeth * 2):
        a0 = math.pi * i / teeth
        rr = r if i % 2 == 0 else r * 0.8
        for da in (-0.32, 0.32):
            a = a0 + da * math.pi / teeth
            pts.append((rr * math.cos(a), rr * math.sin(a)))
    return poly(pts)


def factory_floor():
    top, slab = FLOORS[2]
    for name, cx, cy, r, teeth, speed in (("gearA", 296, 604, 34, 10, 1.6), ("gearB", 346, 634, 22, 7, -2.5), ("gearC", 250, 640, 15, 6, 3.4)):
        layer(name, [group([ellipse(0, 0, r * 0.5, r * 0.5), fill(rgb("#2A3170"))], "hub"),
                     group([gear_path(r, teeth), grad([(0, GEAR_HI), (1, GEAR_LO)], (-r, -r), (r, r))], "gear")],
              p=(cx, cy), r=track(lambda f, s=speed: f * s))
    # конвейер
    y = 718
    rollers = [group([ellipse(x, y + 12, 12, 12), fill(rgb("#2A2F64"))]) for x in range(40, 361, 26)]
    layer("conveyor", rollers + [
        group([rect(W / 2 - 5, y + 18, 330, 30, 4), fill(rgb("#363D86"))], "frame"),
        group([rect(W / 2 - 5, y + 2, 330, 12, 6), fill(rgb("#20244F"))], "belt"),
    ])
    stripes = layer("belt_marks", [group([rect(x, y + 2, 3, 10, 1), fill(rgb("#454C9E"))]) for x in range(30, 380, 22)],
                    p=track(lambda f: [(f * 1.1) % 22, 0, 0], 3))
    # монетки и кубики данных едут вправо
    for i in range(6):
        period = 300
        off = i * period / 6
        pos = track(lambda f, off=off: [10 + 360 * (((f + off) % period) / period), y - 8, 0], 3)
        if i % 2 == 0:
            shapes = [group([ellipse(0, 0, 9, 9), stroke(GOLD, 1.6), ellipse(-2, -2, 4, 3), fill(GOLD_HI)]),
                      group([ellipse(0, 0, 16, 16), grad([(0, GOLD_HI), (1, GOLD)], (-6, -6), (6, 6))])]
        else:
            shapes = [group([poly([(0, -10), (9, -5), (0, 0), (-9, -5)]), fill(CUBE[2])]),
                      group([poly([(0, 0), (9, -5), (9, 5), (0, 10)]), fill(CUBE[1])]),
                      group([poly([(0, 0), (-9, -5), (-9, 5), (0, 10)]), fill(CUBE[0])])]
        layer(f"item{i}", shapes, p=pos)

# ------------------------------------------------------------------ роботы


def robot(name, ground, x_fn, look_fn, arms_fn, bob_fn=lambda f: 0, scale=100, extras=None):
    """Робот: колесо, корпус, руки, голова с визором, глаза-светодиоды и антенна."""
    root = layer(name + "_root", null=True,
                 p=track(lambda f: [x_fn(f), ground, 0], 3), s=(scale, scale))
    vx = [(x_fn(f + 1) - x_fn(f - 1)) / 2 for f in FRAMES]
    roll = [0]
    for v in vx[1:]:
        roll.append(roll[-1] + v * STEP / 8 * 57.3)
    layer(name + "_shadow", [group([ellipse(0, 0, 44, 9), fill(INK, 35)])], parent=root)
    layer(name + "_wheel", [group([poly([(-7, 0), (7, 0)], closed=False), poly([(0, -7), (0, 7)], closed=False), stroke(rgb("#8A92E6"), 2)]),
                            group([ellipse(0, 0, 18, 18), grad([(0, rgb("#4A5099")), (1, WHEEL)], (-6, -6), (8, 8), 2)])],
          parent=root, p=(0, -9), r=anim(FRAMES, roll))
    body = layer(name + "_body", [
        group([ellipse(0, -31, 7, 7), fill(PINK)], "chest_light"),
        group([rect(0, -31, 18, 12, 4), fill(VISOR)], "chest"),
        group([rect(0, -32, 34, 36, 12), grad([(0, BOT_HI), (1, BOT_LO)], (-10, -48), (14, -14), 2)], "torso"),
    ], parent=root, p=track(lambda f: [0, bob_fn(f), 0], 3))
    for side, sx in (("L", -18), ("R", 18)):
        layer(f"{name}_arm{side}", [
            group([ellipse(0, 19, 10, 10), fill(BOT_LO)], "hand"),
            group([rect(0, 9, 7, 22, 3.5), grad([(0, BOT_HI), (1, BOT_LO)], (-4, 0), (4, 0))], "arm"),
        ], parent=body, p=(sx, -44), r=track(lambda f, side=side: arms_fn(f)[0 if side == "L" else 1]))
    head = layer(name + "_head", [
        group([poly([(0, -30), (0, -40)], closed=False), stroke(rgb("#9AA1E8"), 2.4)], "antenna"),
        group([ellipse(-22, -15, 6, 10), ellipse(22, -15, 6, 10), fill(BOT_LO)], "ears"),
        group([rect(0, -15, 32, 19, 8), fill(VISOR)], "visor"),
        group([rect(0, -15, 42, 31, 13), grad([(0, BOT_HI), (1, BOT_LO)], (-12, -30), (16, 2), 2)], "skull"),
    ], parent=body, p=(0, -50),
       r=track(lambda f: look_fn(f)[3]), s=track(lambda f: [look_fn(f)[2], look_fn(f)[2], 100], 3))
    blink = tr()
    blink["s"] = track(lambda f: [100, 15 if (f % 150) in (70, 71, 72, 73) else 100], 2)
    layer(name + "_antenna_ball", [group([ellipse(0, 0, 14, 14), fill(PINK, 25)]), group([ellipse(0, 0, 8, 8), fill(PINK)])],
          parent=head, p=(0, -42), o=track(lambda f: 60 + 40 * math.sin(f / 9)))
    layer(name + "_eyes", [group([
        group([ellipse(-5.5, -2, 2.4, 2.4), ellipse(8.5, -2, 2.4, 2.4), fill(WHITE)], "hl"),
        group([rect(-7, 0, 6.5, 10, 3.2), rect(7, 0, 6.5, 10, 3.2), fill(EYE)], "leds"),
        group([rect(-7, 0, 12, 16, 6), rect(7, 0, 12, 16, 6), fill(EYE, 22)], "glow"),
    ], "eyes", blink)], parent=head,
        p=track(lambda f: [look_fn(f)[0], -15 + look_fn(f)[1], 0], 3),
        s=track(lambda f: [look_fn(f)[4], look_fn(f)[4], 100], 3))
    if extras:
        extras(root, body, head)
    return root


def look_work(direction, notice_at=None):
    """→ (dx, dy, масштаб головы, наклон головы, масштаб глаз): смотрит в монитор, потом на зрителя."""
    def fn(f):
        if notice_at is None or f < notice_at:
            return (4.5 * direction, 1, 100, 0, 100)
        t = smooth((f - notice_at) / 10)
        widen = 100 + 45 * smooth((f - notice_at) / 8) - 10 * smooth((f - notice_at - 40) / 30)
        return (4.5 * direction * (1 - t), 1 - t, 100 + 8 * t, -6 * math.sin(min(1, (f - notice_at) / 14) * math.pi), widen)
    return fn


def typing(f, stop=None):
    if stop is not None and f >= stop:
        return (-25, -35)
    a = math.sin(f * 0.9)
    return (-48 + 14 * a, -62 - 14 * a)


def robots():
    t1, s1 = FLOORS[0]
    t2, s2 = FLOORS[1]
    t3, s3 = FLOORS[2]

    # Техник на этаже серверов: обходит стойки, потом оборачивается
    def tech_x(f):
        if f >= OTHERS:
            f = OTHERS
        u = (f / 150) % 2
        return lerp(104, 312, smooth(u if u < 1 else 2 - u))
    robot("tech", s1 - 1, tech_x, look_work(1, OTHERS),
          lambda f: (-20 + 6 * math.sin(f / 7), 20 - 6 * math.sin(f / 7)) if f < OTHERS else (-10, 150),
          bob_fn=lambda f: -1.5 * abs(math.sin(f / 6)) if f < OTHERS else 0, scale=90)

    # Тележка с монетками и робот-грузчик на нижнем этаже
    def mover_x(f):
        return lerp(56, 180, smooth(min(f, OTHERS) / OTHERS))
    cart = layer("cart", [
        group([ellipse(-12, 6, 10, 10), ellipse(14, 6, 10, 10), fill(WHEEL)], "wheels"),
        group([ellipse(-6, -24, 12, 12), ellipse(6, -26, 12, 12), ellipse(0, -31, 12, 12), fill(GOLD)], "coins"),
        group([rect(0, -10, 40, 22, 4), grad([(0, rgb("#B9B2F3")), (1, rgb("#7C73D9"))], (0, -21), (0, 1))], "bin"),
    ], p=track(lambda f: [mover_x(f) + 44, s3 - 6, 0], 3))
    robot("mover", s3 - 1, mover_x, look_work(1, OTHERS + 6), lambda f: (-70, -80), scale=92)

    # Офис: правый робот печатает, оборачивается
    robot("coder", s2 - 1, lambda f: 226, look_work(1, OTHERS + 3), lambda f: typing(f, OTHERS + 3))

    # Главный герой: замечает ребёнка, катится к кнопке и жмёт её
    def hero_x(f):
        if f < ROLL0:
            return 74
        return lerp(74, 318, smooth((f - ROLL0) / (ROLL1 - ROLL0)))

    def hero_arms(f):
        if f < NOTICE:
            return typing(f)
        if f < ROLL0:
            return (-20, 20)          # замер
        if f < REACH:
            return (12, -12)          # руки назад — разгон
        if f < PRESS:
            t = smooth((f - REACH) / (PRESS - REACH))
            return (10, lerp(-12, -150, t))
        t = smooth((f - PRESS) / 6)
        return (10, lerp(-150, -118, t) if f < PRESS + 30 else -118)

    def hero_bob(f):
        if ROLL0 <= f < ROLL1:
            return -2 * abs(math.sin(f / 4))
        return 0

    def hero_extras(root, body, head):
        # «!» над головой
        pop = tr()
        pop["s"] = track(lambda f: [0, 0] if f < BANG else [100 * ease_back((f - BANG) / 10)] * 2, 2)
        pop["o"] = track(lambda f: 100 if BANG <= f < ROLL0 + 20 else 0)
        layer("hero_bang", [group([
            group([rect(0, -8, 4.5, 13, 2), ellipse(0, 4, 5, 5), fill(RED)], "mark"),
            group([poly([(-4, 14), (4, 14), (-6, 22)]), rect(0, -2, 22, 30, 9), fill(WHITE)], "bubble"),
        ], "bang", pop)], parent=head, p=(24, -52))
        # капли пота при разгоне
        for i, (dx, dy, d0) in enumerate(((-26, -22, 0), (24, -30, 9))):
            layer(f"hero_sweat{i}", [group([curve([(0, -6, (0, 0), (4, 5)), (0, 4, (4, 0), (-4, 0)), (0, -6, (-4, 5), (0, 0))], True),
                                            fill(rgb("#8FE3FF"))])], parent=head,
                  p=track(lambda f, dx=dx, dy=dy, d0=d0: [dx, dy + ((f - ROLL0 - d0) % 24) * 0.6, 0], 3),
                  o=track(lambda f, d0=d0: 90 if ROLL0 + d0 <= f < PRESS + 30 and ((f - ROLL0 - d0) % 24) < 18 else 0))

    robot("hero", s2 - 1, hero_x, look_work(1, NOTICE), hero_arms, bob_fn=hero_bob, extras=hero_extras)

    # «?» над остальными
    for name, x, y, scale in (("q_tech", None, s1 - 118, 90), ("q_coder", 226, s2 - 126, 100), ("q_mover", None, s3 - 120, 92)):
        xf = (lambda f, x=x: x) if x else ((lambda f: tech_x(f)) if name == "q_tech" else (lambda f: mover_x(f)))
        t = tr()
        t["s"] = track(lambda f: [0, 0] if f < OTHERS + 8 else [100 * ease_back((f - OTHERS - 8) / 10)] * 2, 2)
        layer(name, [group([
            group([curve([(-5, -4, (0, 0), (0, -6)), (0, -9, (-3, 0), (3, 0)), (5, -4, (0, -4), (0, 3)), (0, 2, (3, -2), (0, 0)), (0, 5, (0, 0), (0, 0))]),
                   stroke(rgb("#7A6CF0"), 2.6)], "q"),
            group([ellipse(0, 10, 3.4, 3.4), fill(rgb("#7A6CF0"))], "dot"),
            group([rect(0, 0, 22, 28, 9), fill(WHITE)], "bubble"),
        ], "qq", t)], p=track(lambda f, xf=xf, y=y: [xf(f) + 22, y, 0], 3))

# ------------------------------------------------------------------ свет и тревога


def lights():
    for i, (top, slab) in enumerate(FLOORS):
        layer(f"cone{i}", [group([poly([(W / 2 - 75, top + 9), (W / 2 + 75, top + 9), (W / 2 + 150, slab), (W / 2 - 150, slab)]),
                                  grad_alpha(LAMP, 0.16, 0, (W / 2, top + 9), (W / 2, slab))])])
        # маяки тревоги
        layer(f"beacon{i}", [group([ellipse(0, 0, 16, 12), grad([(0, RED_HI), (1, RED)], (-4, -4), (6, 6), 2)])],
              p=(W / 2 + 92, top + 12), o=track(lambda f: 100 if f >= PRESS else 35))
        layer(f"beam{i}", [group([poly([(0, 0), (150, -26), (150, 26)]), grad_alpha(RED, 0.55, 0, (0, 0), (150, 0))])],
              p=(W / 2 + 92, top + 12), r=track(lambda f: (f - PRESS) * 9),
              o=track(lambda f: 0 if f < PRESS else 100))
    layer("alarm_tint", [group([rect(W / 2, H / 2, W, H), fill(RED)])],
          o=track(lambda f: 0 if f < PRESS else 24 * math.sin((f - PRESS) / 60 * math.pi * 3.2) ** 2))


def build():
    building()
    cables()
    servers()
    desks()
    red_button()
    factory_floor()
    robots()
    lights()
    layers = list(reversed(LAYERS))
    for i, L in enumerate(layers):
        L["ind"] = i + 1
    for L in layers:
        parent = L.pop("_parent")
        if parent is not None:
            L["parent"] = parent["ind"]
    return {"v": "5.9.0", "fr": FR, "ip": 0, "op": OP, "w": W, "h": H, "nm": "SberKids robots factory",
            "ddd": 0, "assets": [], "markers": [{"tm": NOTICE, "cm": "notice", "dr": 0}, {"tm": PRESS, "cm": "press", "dr": 0}],
            "layers": layers}


if __name__ == "__main__":
    data = build()
    with open(OUT, "w") as fh:
        json.dump(data, fh, separators=(",", ":"), ensure_ascii=False)
    print(f"robots.json {os.path.getsize(OUT)} B, {len(LAYERS)} layers, {OP / FR:.2f}s")
