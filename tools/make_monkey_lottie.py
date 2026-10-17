#!/usr/bin/env python3
"""Процедурная Lottie-анимация «Обезьянка-паркурщик».

Персонаж — «кукла на костях»: каждая часть тела отдельный слой Lottie с родителем
(торс → голова, плечо → предплечье → кисть …). Скрипт считает позы по времени
(бег, прыжок на правую границу экрана, отталкивание, заднее сальто, ловля банана,
приземление, радость, убегание) и запекает их в ключевые кадры.

В продакшене этот файл рисует дизайнер в After Effects + Bodymovin, а приложение
просто проигрывает любой Lottie с CDN — новый персонаж приезжает без релиза.

    python3 tools/make_monkey_lottie.py   # → cdn/fun-layer/v1/assets/monkey.json
"""
import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "cdn", "fun-layer", "v1", "assets", "monkey.json")

W, H, FR = 390, 844, 60
OP = 262            # 4.37 c
STEP = 2            # шаг запекания ключей (кадров)
G = 600             # высота бёдер над «полом»
FOOT = 42           # от бёдер до пола
SCALE = 100         # масштаб персонажа, %

# ------------------------------------------------------------------ палитра

def rgb(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]

FUR_HI = rgb("#C99062")
FUR = rgb("#8E5634")
FUR_DARK = rgb("#4F2B17")
FUR_RIM = rgb("#E6B488")
FACE_HI = rgb("#FFF0E4")
FACE = rgb("#F8CBAE")
FACE_SH = rgb("#E39C7C")
EAR_IN = rgb("#F4A994")
INK = rgb("#23140D")
IRIS = rgb("#6B3A1E")
MOUTH = rgb("#7C2622")
TONGUE = rgb("#FF8597")
CHEEK = rgb("#FF7F8C")
NOSE = rgb("#6E3828")
BROW = rgb("#5E3420")
WHITE = [1, 1, 1]
BANANA_HI = rgb("#FFF7B0")
BANANA = rgb("#FFD53C")
BANANA_SH = rgb("#F2A114")
BANANA_DEEP = rgb("#D9800C")
BANANA_STEM_HI = rgb("#9CC24A")
BANANA_STEM = rgb("#5E6B22")
BANANA_TIP = rgb("#3E2812")
SUGAR = rgb("#B0701B")
DUST = rgb("#E3DDF2")
SPARK = rgb("#FFF3A6")
WHOOSH = rgb("#C9B8FF")
# совместимость со старыми именами
SKIN = FACE
SKIN_DARK = FACE_SH

# ------------------------------------------------------------------ утилиты Lottie

def static(v):
    return {"a": 0, "k": v}


def r1(v):
    return round(v, 2)


def anim(frames, values, dims=1, hold=False):
    """Ключи с линейной интерполяцией (значения уже сглажены при запекании)."""
    if all(v == values[0] for v in values):
        v = values[0]
        return static(v if dims > 1 else v)
    keys = []
    prev = None
    vals = [[r1(x) for x in v] if dims > 1 else [r1(v)] for v in values]
    for idx, (f, s) in enumerate(zip(frames, vals)):
        nxt = vals[idx + 1] if idx + 1 < len(vals) else None
        # пропускаем ключ внутри постоянного участка, но сохраняем его границы —
        # иначе линейная интерполяция «растягивает» скачок на весь участок
        if s == prev and nxt == s:
            continue
        k = {"t": f, "s": s}
        if hold:
            k["h"] = 1
        else:
            if dims > 1:
                k["i"] = {"x": 1, "y": 1}
                k["o"] = {"x": 0, "y": 0}
            else:
                k["i"] = {"x": [1], "y": [1]}
                k["o"] = {"x": [0], "y": [0]}
        keys.append(k)
        prev = s
    # как в экспорте Bodymovin: у последнего ключа нет касательных (иначе rlottie сбрасывает значение)
    keys[-1].pop("i", None)
    keys[-1].pop("o", None)
    return {"a": 1, "k": keys}


def tr(p=(0, 0), s=(100, 100), r=0, o=100, sa=None):
    return {"ty": "tr", "p": static(list(p)), "a": static([0, 0]), "s": sa or static(list(s)),
            "r": static(r), "o": static(o), "sk": static(0), "sa": static(0)}


def fill(c, o=100):
    return {"ty": "fl", "c": static(c + [1]), "o": static(o), "r": 1, "bm": 0}


def stroke(c, w, o=100):
    return {"ty": "st", "c": static(c + [1]), "o": static(o), "w": static(w), "lc": 2, "lj": 2, "bm": 0}


def radial(c0, c1, c2, start, end):
    return {"ty": "gf", "o": static(100), "r": 1, "bm": 0, "t": 2,
            "s": static(list(start)), "e": static(list(end)),
            "h": static(0), "a": static(0),
            "g": {"p": 3, "k": static([0] + c0 + [0.55] + c1 + [1] + c2)}}


def grad(stops, start, end, kind=1):
    """Градиентная заливка: stops = [(позиция 0…1, rgb)], kind 1 — линейный, 2 — радиальный."""
    k = []
    for pos, c in stops:
        k += [pos] + list(c)
    return {"ty": "gf", "o": static(100), "r": 1, "bm": 0, "t": kind,
            "s": static(list(start)), "e": static(list(end)), "h": static(0), "a": static(0),
            "g": {"p": len(stops), "k": static(k)}}


def outline(w=1.3, o=55):
    return stroke(INK, w, o)


def ellipse(x, y, w, h):
    return {"ty": "el", "p": static([x, y]), "s": static([w, h]), "d": 1}


def rect(x, y, w, h, r):
    return {"ty": "rc", "p": static([x, y]), "s": static([w, h]), "r": static(r), "d": 1}


def path(points, closed=True):
    """points: [(x, y, (ix, iy), (ox, oy))] — касательные относительно вершины."""
    return {"ty": "sh", "ks": static({
        "c": closed,
        "v": [[p[0], p[1]] for p in points],
        "i": [list(p[2]) for p in points],
        "o": [list(p[3]) for p in points],
    })}


def group(items, name="g", transform=None):
    return {"ty": "gr", "nm": name, "it": items + [transform or tr()]}


LAYERS = []


def layer(name, shapes, parent=None, kind=4, ip=0, op=OP):
    ind = len(LAYERS) + 1
    L = {"ddd": 0, "ind": ind, "ty": kind, "nm": name, "sr": 1, "ao": 0,
         "ks": {"o": static(100), "r": static(0), "p": static([0, 0, 0]),
                "a": static([0, 0, 0]), "s": static([100, 100, 100])},
         "ip": ip, "op": op, "st": 0, "bm": 0}
    if kind == 4:
        L["shapes"] = shapes
    if parent:
        L["parent"] = parent["ind"]
    LAYERS.append(L)
    return L

# ------------------------------------------------------------------ скелет

# (родитель, точка крепления в системе родителя)
JOINTS = {
    "torso": ("root", (0, 0)),
    "head": ("torso", (3, -36)),
    "uaN": ("torso", (5, -35)), "faN": ("uaN", (0, 20)), "hdN": ("faN", (0, 19)),
    "uaF": ("torso", (-5, -35)), "faF": ("uaF", (0, 20)), "hdF": ("faF", (0, 19)),
    "thN": ("root", (5, -3)), "shN": ("thN", (0, 18)), "ftN": ("shN", (0, 16)),
    "thF": ("root", (-4, -3)), "shF": ("thF", (0, 18)), "ftF": ("shF", (0, 16)),
    "t1": ("root", (-15, -10)), "t2": ("t1", (0, 15)), "t3": ("t2", (0, 13)),
}
ANGLES = ["torso", "head", "uaN", "faN", "hdN", "uaF", "faF", "hdF",
          "thN", "shN", "ftN", "thF", "shF", "ftF", "t1", "t2", "t3"]


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def blend(p, q, t):
    t = smooth(t)
    return {k: lerp(p[k], q[k], t) for k in p}


def pose(**kw):
    base = {k: 0.0 for k in ANGLES}
    base.update(t1=70, t2=45, t3=55, hdN=0, hdF=0)
    base.update(kw)
    return base


def run_pose(phase, carry=False):
    s, c = math.sin(phase), math.cos(phase)
    p = pose(
        torso=14 + 2 * c, head=-10 - 2 * c,
        thN=-38 * s - 6, shN=22 + 42 * max(0, math.sin(phase + 1.1)),
        thF=38 * s - 6, shF=22 + 42 * max(0, math.sin(phase + 1.1 + math.pi)),
        ftN=-10, ftF=-10,
        uaN=42 * s, faN=-62 - 12 * s,
        uaF=-42 * s, faF=-62 + 12 * s,
        t1=72 + 10 * s, t2=40 + 14 * math.sin(phase - 0.8), t3=55 + 18 * math.sin(phase - 1.6),
    )
    if carry:  # банан поднят над головой
        p.update(uaN=-92 + 6 * s, faN=-38, hdN=-20)
    return p


CROUCH = pose(torso=26, head=-14, thN=-62, shN=104, thF=-55, shF=96, ftN=-30, ftF=-30,
              uaN=55, faN=-40, uaF=48, faF=-45)
REACH_WALL = pose(torso=-6, head=-12, thN=-78, shN=60, thF=-70, shF=70, ftN=-40, ftF=-40,
                  uaN=60, faN=-30, uaF=70, faF=-20)
# лицом влево, ноги согнуты к стене (назад)
COMPRESS = pose(torso=22, head=-16, thN=78, shN=-110, thF=70, shF=-100, ftN=60, ftF=60,
                uaN=-110, faN=-40, uaF=-95, faF=-50)
KICK = pose(torso=10, head=-20, thN=48, shN=-8, thF=38, shF=-4, ftN=20, ftF=20,
            uaN=-165, faN=-10, uaF=-150, faF=-15)
TUCK = pose(torso=14, head=18, thN=-112, shN=138, thF=-104, shF=132, ftN=-20, ftF=-20,
            uaN=-58, faN=-92, uaF=-48, faF=-96, t1=40, t2=60, t3=70)
REACH = pose(torso=-4, head=-26, thN=-24, shN=44, thF=-10, shF=36, ftN=-10, ftF=-10,
             uaN=-138, faN=-14, hdN=-10, uaF=34, faF=-40)
LAND = pose(torso=34, head=-4, thN=-74, shN=116, thF=-66, shF=108, ftN=-30, ftF=-30,
            uaN=-105, faN=-30, hdN=-20, uaF=44, faF=-60)
STAND = pose(torso=4, head=-14, thN=-8, shN=12, thF=6, shF=8,
             uaN=-98, faN=-36, hdN=-20, uaF=-30, faF=-70)


def wave_arm(p, f):
    q = dict(p)
    q.update(uaF=-140 + 26 * math.sin(f * 0.45), faF=-30 + 20 * math.sin(f * 0.45 + 1))
    return q

# ------------------------------------------------------------------ таймлайн

F_RUN_END = 64
F_WALL = 82
F_KICK = 90
F_FLIP_END = 122
F_CATCH = 127
F_LAND = 146
F_HOP0, F_HOP1 = 160, 184
F_RUNOFF = 196
CYCLE = 22  # кадров на шаг бега

WALL_PT = (352, G - 118)
LAND_X = 150
APEX_S = 0.4407
APEX_A = 926.8
APEX_Y = 310


def flight(s):
    x = lerp(WALL_PT[0], LAND_X, s)
    y = APEX_A * (s - APEX_S) ** 2 + APEX_Y
    return x, y


def timeline(f):
    """→ (x, y, rotation, facing, pose, mouth_open)"""
    if f <= F_RUN_END:
        x = lerp(-22, 292, f / F_RUN_END)   # сразу в кадре — без паузы на «вбегание»
        ph = 2 * math.pi * f / CYCLE
        y = G - 7 * abs(math.sin(ph))
        p = run_pose(ph)
        if f > F_RUN_END - 8:
            p = blend(p, CROUCH, (f - (F_RUN_END - 8)) / 8)
        return x, y, 0, 1, p, 0
    if f <= F_WALL:
        t = (f - F_RUN_END) / (F_WALL - F_RUN_END)
        e = 1 - (1 - t) ** 2
        x = lerp(292, WALL_PT[0], e)
        y = lerp(G, WALL_PT[1], e) - 60 * math.sin(math.pi * t) * 0.5
        rot = lerp(0, -28, smooth(t))
        p = blend(CROUCH, REACH_WALL, t * 1.6)
        return x, y, rot, 1, p, 0
    if f <= F_KICK:
        # прилипли к стене лицом влево, сжались — и толчок
        t = (f - F_WALL) / (F_KICK - F_WALL)
        x = WALL_PT[0] - 2 * smooth(t)
        y = WALL_PT[1] + 6 * math.sin(math.pi * t)
        p = blend(COMPRESS, KICK, (t - 0.55) / 0.45) if t > 0.55 else COMPRESS
        return x, y, -24, -1, p, 0
    if f <= F_LAND:
        s = (f - F_KICK) / (F_LAND - F_KICK)
        x, y = flight(s)
        flip_t = (f - F_KICK - 2) / (F_FLIP_END - F_KICK - 2)
        rot = lerp(-24, 336, smooth(flip_t)) if f < F_FLIP_END else lerp(336, 360, smooth((f - F_FLIP_END) / 8))
        if f < F_KICK + 6:
            p = blend(KICK, TUCK, (f - F_KICK) / 6)
        elif f < F_FLIP_END - 6:
            p = TUCK
        elif f < F_CATCH:
            p = blend(TUCK, REACH, (f - (F_FLIP_END - 6)) / (F_CATCH - F_FLIP_END + 6))
        else:
            land_t = (f - F_CATCH) / (F_LAND - F_CATCH)
            p = blend(REACH, LAND, (land_t - 0.5) / 0.5) if land_t > 0.5 else REACH
        mouth = 1 if F_KICK + 4 < f < F_CATCH + 10 else 0
        return x, y, rot, -1, p, mouth
    if f <= F_RUNOFF:
        if f < F_LAND + 10:
            t = (f - F_LAND) / 10
            y = G + 7 * math.sin(math.pi * t)
            return LAND_X, y, 360, -1, blend(LAND, STAND, t), 0
        if F_HOP0 <= f <= F_HOP1:
            t = (f - F_HOP0) / (F_HOP1 - F_HOP0)
            y = G - 36 * math.sin(math.pi * t)
            p = blend(STAND, TUCK, math.sin(math.pi * t) * 0.35)
            return LAND_X, y, 360, -1, wave_arm(p, f), 1
        return LAND_X, G, 360, -1, wave_arm(STAND, f), 0
    # убегает влево с бананом
    t = (f - F_RUNOFF) / (OP - F_RUNOFF)
    x = lerp(LAND_X, -110, smooth(t * 0.6) * 0.25 + t * 0.75)
    ph = 2 * math.pi * (f - F_RUNOFF) / CYCLE
    y = G - 7 * abs(math.sin(ph))
    p = run_pose(ph, carry=True)
    if f < F_RUNOFF + 8:
        p = blend(wave_arm(STAND, f), p, (f - F_RUNOFF) / 8)
    return x, y, 360, -1, p, 0

# ------------------------------------------------------------------ прямая кинематика (для банана)

def mat_mul(a, b):
    return [
        [a[0][0] * b[0][0] + a[0][1] * b[1][0], a[0][0] * b[0][1] + a[0][1] * b[1][1],
         a[0][0] * b[0][2] + a[0][1] * b[1][2] + a[0][2]],
        [a[1][0] * b[0][0] + a[1][1] * b[1][0], a[1][0] * b[0][1] + a[1][1] * b[1][1],
         a[1][0] * b[0][2] + a[1][1] * b[1][2] + a[1][2]],
    ]


def m_t(x, y):
    return [[1, 0, x], [0, 1, y]]


def m_r(deg):
    a = math.radians(deg)
    return [[math.cos(a), -math.sin(a), 0], [math.sin(a), math.cos(a), 0]]


def m_s(sx, sy):
    return [[sx, 0, 0], [0, sy, 0]]


def world(f, bone):
    x, y, rot, facing, p, _ = timeline(f)
    chain = []
    b = bone
    while b != "root":
        parent, at = JOINTS[b]
        chain.append((at, p[b]))
        b = parent
    m = mat_mul(mat_mul(m_t(x, y), m_r(rot)), m_s(facing * SCALE / 100, SCALE / 100))
    for at, ang in reversed(chain):
        m = mat_mul(m, mat_mul(m_t(*at), m_r(ang)))
    return m


def apply(m, pt):
    return (m[0][0] * pt[0] + m[0][1] * pt[1] + m[0][2], m[1][0] * pt[0] + m[1][1] * pt[1] + m[1][2])

# ------------------------------------------------------------------ рисуем части тела

def capsule(length, width, color, dark=False):
    """Конечность-«плюш»: объём градиентом поперёк, светлая кромка сверху, без контура."""
    hi, mid, lo = (FUR, FUR_DARK, FUR_DARK) if dark else (FUR_HI, FUR, FUR_DARK)
    return group([rect(0, length / 2, width, length + width, width / 2),
                  grad([(0, hi), (0.45, mid), (1, lo)], (-width / 2, 0), (width / 2 + 1, 0))])


def hand(dark=False):
    c0, c1, c2 = (FACE, FACE_SH, FACE_SH) if dark else (FACE_HI, FACE, FACE_SH)
    return [group([ellipse(5, 2.5, 6, 7), grad([(0, c0), (1, c2)], (3, 0), (7, 6), 2)], "thumb"),
            group([ellipse(0, 5, 14, 13.5), grad([(0, c0), (0.6, c1), (1, c2)], (-3, 1), (6, 11), 2)], "palm")]


def foot(dark=False):
    c0, c1, c2 = (FACE, FACE_SH, FACE_SH) if dark else (FACE_HI, FACE, FACE_SH)
    return [group([ellipse(14, 1.5, 6, 6.5), ellipse(9.5, 0.5, 6, 6.5), grad([(0, c1), (1, c2)], (9, -2), (14, 5))], "toes"),
            group([ellipse(6, 3, 22, 11), grad([(0, c0), (0.6, c1), (1, c2)], (2, -1), (10, 9), 2)], "sole")]


def banana_shape():
    """Глянцевый 3D-банан: грани, блик, зелёный хвостик, сахарные крапинки."""
    k = 1.5
    def pt(x, y, i=(0, 0), o=(0, 0)):
        return (x * k, y * k, (i[0] * k, i[1] * k), (o[0] * k, o[1] * k))
    def P(x, y):
        return (x * k, y * k)
    body = [pt(-15, -3, (0, 0), (4, 10)), pt(1, 7.5, (-9, 0), (9, 0)), pt(17, -2, (-3, 8), (0, 0)),
            pt(15, -6, (0, 0), (-4, 5)), pt(1, 1.5, (8, 0), (-8, 0)), pt(-12, -7, (4, 4), (0, 0))]
    belly = [pt(-14, -3.4, (0, 0), (4, 9)), pt(1, 7.5, (-9, 0), (9, 0)), pt(16.6, -2.4, (-3, 8), (0, 0)),
             pt(1, 3.8, (8, 1), (-8, 1))]
    shine = [pt(-9, -2.6, (0, 0), (3, 3)), pt(4, 1.4, (-4, 0.5), (0, 0))]
    stem = [pt(-12, -7, (0, 0), (0, 0)), pt(-15, -12.5, (0, 0), (0, 0)), pt(-12.5, -13.5, (0, 0), (0, 0)),
            pt(-9.5, -7.8, (0, 0), (0, 0))]
    return [
        group([ellipse(*P(4, 3.5), 1.6 * k, 1.1 * k), ellipse(*P(9, 1.8), 1.2 * k, 0.9 * k),
               ellipse(*P(-5, 1.6), 1.0 * k, 0.8 * k), fill(SUGAR, 55)], "sugar"),
        group([ellipse(*P(16.2, -4.3), 3.2 * k, 3.8 * k), fill(BANANA_TIP)], "tip"),
        group([path(stem), grad([(0, BANANA_STEM_HI), (1, BANANA_STEM)], P(-15, -13), P(-10, -7))], "stem"),
        group([path(shine, closed=False), stroke(WHITE, 2.4, 80)], "shine"),
        group([path(belly), grad([(0, BANANA_SH), (1, BANANA_DEEP)], P(1, 2), P(1, 8))], "belly"),
        group([path(body), grad([(0, BANANA_HI), (0.45, BANANA), (1, BANANA_SH)], P(-6, -7), P(6, 6))], "body"),
    ]


def head_shapes():
    blink_frames = list(range(0, OP + 1, STEP))
    blink = [100 if not any(abs(f - b) < 4 for b in (40, 150, 230)) else 10 for f in blink_frames]
    eyes_tr = tr(sa=anim(blink_frames, [[100, v] for v in blink], dims=2))
    eyes_tr["p"] = static([5.5, -34])
    eyes_tr["a"] = static([5.5, -34])
    eyes = group([
        group([ellipse(-7, -38.5, 5.6, 6.2), ellipse(12, -38.5, 5.6, 6.2), fill(WHITE)], "hl1"),
        group([ellipse(-1.2, -29.8, 2.4, 2.4), ellipse(17.8, -29.8, 2.4, 2.4), fill(WHITE, 85)], "hl2"),
        group([ellipse(-3.2, -31, 9, 7), ellipse(15.8, -31, 9, 7), fill(IRIS, 70)], "iris_glow"),
        group([ellipse(-4, -34, 14, 17), ellipse(15, -34, 14, 17),
               grad([(0, rgb("#3A2219")), (1, INK)], (-4, -40), (-4, -26))], "eyeballs"),
    ], "eyes", eyes_tr)

    mouth_frames = list(range(0, OP + 1, STEP))
    open_v = [100 if timeline(f)[5] else 0 for f in mouth_frames]
    smile_tr = tr()
    smile_tr["o"] = anim(mouth_frames, [100 - v for v in open_v])
    open_tr = tr()
    open_tr["o"] = anim(mouth_frames, open_v)
    smile = group([path([(-2, -17, (0, 0), (3.5, 5.5)), (13, -17, (-3.5, 5.5), (0, 0))], closed=False),
                   stroke(MOUTH, 2.3)], "smile", smile_tr)
    mouth_open = group([
        group([ellipse(5.5, -9.5, 7, 4.5), fill(TONGUE)], "tongue"),
        group([ellipse(5.5, -12.5, 11, 12), grad([(0, rgb("#A0322C")), (1, MOUTH)], (5.5, -18), (5.5, -7))], "mouth"),
    ], "open", open_tr)

    tuft = group([
        path([(-3, -60, (0, 0), (-2, -7)), (2, -70, (-4, 2), (0, 0)), (5, -61, (0, 0), (0, 0))]),
        path([(4, -61, (0, 0), (1, -9)), (11, -72, (-3, 3), (0, 0)), (12, -60, (0, 0), (0, 0))]),
        path([(11, -60, (0, 0), (3, -6)), (19, -66, (-3, 1), (0, 0)), (17, -58, (0, 0), (0, 0))]),
        grad([(0, FUR_HI), (1, FUR)], (6, -72), (8, -58)),
    ], "tuft")
    return [
        group([ellipse(5.5, -22, 15, 6), fill(WHITE, 30)], "muzzle_shine"),
        group([path([(-11, -45.5, (0, 0), (3, -3.5)), (0, -47, (-3.5, -1.5), (0, 0))], closed=False),
               path([(11, -47, (0, 0), (3.5, -1.5)), (21.5, -45.5, (-3, -3.5), (0, 0))], closed=False),
               stroke(BROW, 2.8)], "brows"),
        eyes,
        mouth_open,
        smile,
        group([ellipse(4.6, -24.2, 2.4, 1.2), fill(WHITE, 55)], "nose_hl"),
        group([path([(5.5, -20.5, (0, 0), (-4, -1)), (1.5, -24.5, (0, 2.5), (0, -2)), (5.5, -26, (-2, 0), (2, 0)),
                     (9.5, -24.5, (0, -2), (0, 2.5)), (5.5, -20.5, (4, -1), (0, 0))]),
               grad([(0, rgb("#9A5A44")), (1, NOSE)], (5.5, -26), (5.5, -20.5))], "nose"),
        group([ellipse(-12, -21, 11, 7), ellipse(23, -21, 11, 7), fill(CHEEK, 28)], "cheeks_soft"),
        group([ellipse(-12, -21, 7, 4.5), ellipse(23, -21, 7, 4.5), fill(CHEEK, 40)], "cheeks"),
        group([ellipse(-4.5, -34, 29, 29), ellipse(15.5, -34, 29, 29), ellipse(5.5, -18, 42, 31),
               grad([(0, FACE_HI), (0.55, FACE), (1, FACE_SH)], (0, -40), (12, -2), 2)], "face"),
        group([path([(30, -48, (0, 0), (6, 8)), (33, -18, (4, -10), (0, 0))], closed=False),
               stroke(FUR_RIM, 3.2, 55)], "rim"),
        tuft,
        group([ellipse(5.5, -32, 66, 62), grad([(0, FUR_HI), (0.5, FUR), (1, FUR_DARK)], (-12, -54), (38, 6), 2)], "skull"),
        group([ellipse(40, -30, 13, 14), grad([(0, FACE_HI), (1, EAR_IN)], (38, -34), (42, -24), 2)], "earR_in"),
        group([ellipse(39, -30, 22, 23), grad([(0, FUR_HI), (1, FUR_DARK)], (34, -38), (46, -20), 2)], "earR"),
        group([ellipse(-29, -30, 14, 15), grad([(0, FACE_HI), (1, EAR_IN)], (-31, -34), (-27, -24), 2)], "earL_in"),
        group([ellipse(-28, -30, 24, 25), grad([(0, FUR_HI), (1, FUR_DARK)], (-34, -38), (-22, -20), 2)], "earL"),
    ]


def torso_shapes():
    return [
        group([ellipse(3, -41, 30, 9), fill(FUR_DARK, 35)], "ao"),
        group([ellipse(1, -33, 8, 4), fill(WHITE, 20)], "sheen"),
        group([ellipse(5, -19, 26, 30), grad([(0, FACE_HI), (0.6, FACE), (1, FACE_SH)], (2, -30), (8, -5), 2)], "belly"),
        group([ellipse(0, -21, 40, 46), grad([(0, FUR_HI), (0.55, FUR), (1, FUR_DARK)], (-8, -38), (24, 2), 2)], "body"),
    ]


def whoosh():
    arc = [(-48, -26, (0, 0), (0, -27)), (0, -74, (-27, 0), (27, 0)), (48, -26, (0, -27), (0, 0))]
    return [group([path(arc, closed=False), stroke(WHOOSH, 5, 100)], "arc")]


def star(size):
    s = size
    q = s * 0.28
    return group([path([(0, -s, (0, 0), (0, 0)), (q, -q, (0, 0), (0, 0)), (s, 0, (0, 0), (0, 0)),
                        (q, q, (0, 0), (0, 0)), (0, s, (0, 0), (0, 0)), (-q, q, (0, 0), (0, 0)),
                        (-s, 0, (0, 0), (0, 0)), (-q, -q, (0, 0), (0, 0))]), fill(SPARK)], "star")

# ------------------------------------------------------------------ сборка

def build():
    frames = list(range(0, OP + 1, STEP))
    if frames[-1] != OP:
        frames.append(OP)
    tl = [timeline(f) for f in frames]

    # точка ловли банана
    hand_catch = world(F_CATCH, "hdN")
    held_local = (4, 6)
    held_rot_local = -70
    # мировая матрица банана в руке: R(θ)·S(±k, k) → падающий банан совпадает с ним кадр в кадр
    mb = mat_mul(hand_catch, mat_mul(m_t(*held_local), m_r(held_rot_local)))
    catch_pt = (mb[0][2], mb[1][2])
    det = mb[0][0] * mb[1][1] - mb[0][1] * mb[1][0]
    mirror = -1 if det < 0 else 1
    k = math.hypot(mb[0][0], mb[1][0])
    catch_rot = math.degrees(math.atan2(mirror * mb[1][0], mirror * mb[0][0]))

    # --- падающий банан (сверху экрана до руки), верхний слой
    fall_start = 74
    fall_frames = [f for f in frames if fall_start <= f <= F_CATCH] + [F_CATCH]
    fall_frames = sorted(set(fall_frames))
    fpos, frot = [], []
    for f in fall_frames:
        t = (f - fall_start) / (F_CATCH - fall_start)
        y0 = -30
        fpos.append([catch_pt[0] + 6 * (1 - t), y0 + (catch_pt[1] - y0) * t * t, 0])
        frot.append(catch_rot - 220 * (1 - t))
    banana_fall = layer("banana_fall", [group(banana_shape(), "b")], ip=fall_start, op=F_CATCH + 1)
    banana_fall["ks"]["p"] = anim(fall_frames, fpos, dims=3)
    banana_fall["ks"]["r"] = anim(fall_frames, frot)
    banana_fall["ks"]["s"] = static([mirror * k * 100, k * 100, 100])

    # --- искры в момент ловли
    for i, (dx, dy, sz) in enumerate([(-26, -18, 7), (22, -26, 6), (28, 10, 5), (-18, 20, 5)]):
        st = layer(f"spark{i}", [star(sz)], ip=F_CATCH, op=F_CATCH + 26)
        fr = list(range(F_CATCH, F_CATCH + 26, 2))
        st["ks"]["p"] = static([catch_pt[0] + dx, catch_pt[1] + dy, 0])
        st["ks"]["s"] = anim(fr, [[v, v, 100] for v in
                                  [100 * math.sin(math.pi * (f - F_CATCH) / 26) * 1.3 for f in fr]], dims=3)
        st["ks"]["r"] = anim(fr, [(f - F_CATCH) * 6 for f in fr])

    # --- скелет
    root = layer("root", [], kind=3)
    root["ks"]["p"] = anim(frames, [[x, y, 0] for x, y, *_ in tl], dims=3)
    root["ks"]["r"] = anim(frames, [r for _, _, r, *_ in tl])
    root["ks"]["s"] = anim(frames, [[t[3] * SCALE, SCALE, 100] for t in tl], dims=3, hold=True)

    order = []  # (bone, shapes, parent bone) в порядке сверху вниз

    def bone_layer(name, shapes, bone):
        parent_name, at = JOINTS[bone]
        L = layer(name, shapes, parent=None)
        L["_bone"] = bone
        L["_parent_bone"] = parent_name
        L["ks"]["p"] = static([at[0], at[1], 0])
        L["ks"]["r"] = anim(frames, [p[bone] for *_, p, _ in tl])
        return L

    # верхние слои — ближние к зрителю
    banana_held = layer("banana_held", [group(banana_shape(), "b")], ip=F_CATCH, op=OP + 1)
    banana_held["_parent_bone"] = "hdN"
    banana_held["ks"]["p"] = static([held_local[0], held_local[1], 0])
    banana_held["ks"]["r"] = static(held_rot_local)

    bone_layer("handN", hand(), "hdN")
    bone_layer("forearmN", [capsule(19, 9, FUR)], "faN")
    bone_layer("upperarmN", [capsule(20, 10, FUR)], "uaN")
    bone_layer("footN", foot(), "ftN")
    bone_layer("shinN", [capsule(16, 10.5, FUR)], "shN")
    bone_layer("thighN", [capsule(18, 12.5, FUR)], "thN")
    bone_layer("head", head_shapes(), "head")
    bone_layer("torso", torso_shapes(), "torso")
    bone_layer("footF", foot(dark=True), "ftF")
    bone_layer("shinF", [capsule(16, 10, FUR, dark=True)], "shF")
    bone_layer("thighF", [capsule(18, 12, FUR, dark=True)], "thF")
    bone_layer("handF", hand(dark=True), "hdF")
    bone_layer("forearmF", [capsule(19, 8.5, FUR, dark=True)], "faF")
    bone_layer("upperarmF", [capsule(20, 9.5, FUR, dark=True)], "uaF")
    wl = layer("whoosh", whoosh(), ip=F_KICK, op=F_FLIP_END + 6)
    wl["_parent_bone"] = "root"
    wf = list(range(F_KICK, F_FLIP_END + 6, 2))
    wl["ks"]["o"] = anim(wf, [70 * math.sin(math.pi * (f - F_KICK) / (F_FLIP_END + 6 - F_KICK)) for f in wf])
    wl["ks"]["r"] = static(-40)
    bone_layer("tail3", [group([path([(0, 0, (0, 0), (10, 7)), (2, 19, (8, 2), (0, 0))], closed=False),
                                stroke(FUR, 7.5)])], "t3")
    bone_layer("tail2", [capsule(13, 7, FUR, dark=True)], "t2")
    bone_layer("tail1", [capsule(15, 7.5, FUR, dark=True)], "t1")

    # --- пыль при приземлении и у стены
    def dust(at_frame, cx, cy, n, spread):
        for i in range(n):
            ang = math.pi * (i / (n - 1)) if n > 1 else 0
            dx = -math.cos(ang) * spread
            L = layer(f"dust{at_frame}_{i}", [group([ellipse(0, 0, 14, 14), fill(DUST)])],
                      ip=at_frame, op=at_frame + 22)
            fr = list(range(at_frame, at_frame + 22, 2))
            L["ks"]["p"] = anim(fr, [[cx + dx * Ease(f - at_frame), cy - 10 * Ease(f - at_frame) * math.sin(ang), 0]
                                     for f in fr], dims=3)
            L["ks"]["s"] = anim(fr, [[40 + 90 * Ease(f - at_frame)] * 2 + [100] for f in fr], dims=3)
            L["ks"]["o"] = anim(fr, [70 * (1 - (f - at_frame) / 22) for f in fr])

    def Ease(df):
        return 1 - (1 - min(1, df / 22)) ** 3

    dust(F_LAND, LAND_X, G + FOOT * SCALE / 100, 5, 34)
    dust(F_KICK - 2, W - 6, WALL_PT[1] + 10, 3, 18)

    # --- тень
    shadow = layer("shadow", [group([ellipse(0, 0, 54, 12), fill(rgb("#3B2A6B"))])])
    sp, ss, so = [], [], []
    for f, (x, y, *_rest) in zip(frames, tl):
        h = max(0, G - y)
        k = max(0.35, 1 - h / 320)
        wall_fade = max(0, min(1, (W - 20 - x) / 30))
        sp.append([x, G + FOOT * SCALE / 100 + 2, 0])
        ss.append([100 * k, 100 * k, 100])
        so.append(18 * k * wall_fade)
    shadow["ks"]["p"] = anim(frames, sp, dims=3)
    shadow["ks"]["s"] = anim(frames, ss, dims=3)
    shadow["ks"]["o"] = anim(frames, so)

    # проставляем родителей
    by_bone = {L.get("_bone"): L for L in LAYERS if L.get("_bone")}
    by_bone["root"] = root
    for L in LAYERS:
        pb = L.pop("_parent_bone", None)
        L.pop("_bone", None)
        if pb:
            L["parent"] = by_bone[pb]["ind"]

    # null-слой root рендерить не нужно, но он должен существовать — порядок не важен
    return {
        "v": "5.9.0", "fr": FR, "ip": 0, "op": OP, "w": W, "h": H, "nm": "SberKids monkey parkour",
        "ddd": 0, "assets": [], "markers": [{"tm": F_CATCH, "cm": "catch", "dr": 0}],
        "layers": LAYERS,
    }


if __name__ == "__main__":
    data = build()
    with open(OUT, "w") as fh:
        json.dump(data, fh, separators=(",", ":"), ensure_ascii=False)
    print(f"monkey.json {os.path.getsize(OUT)} B, {len(LAYERS)} layers, {OP / FR:.2f}s")
