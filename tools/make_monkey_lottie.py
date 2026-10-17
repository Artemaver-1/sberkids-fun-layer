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

FUR = rgb("#9A6140")
FUR_DARK = rgb("#6E4129")
FUR_LIGHT = rgb("#B97E55")
SKIN = rgb("#F9D9B0")
SKIN_DARK = rgb("#EDBE8F")
EAR_IN = rgb("#F3A49B")
INK = rgb("#2A1A12")
MOUTH = rgb("#8C2F2B")
CHEEK = rgb("#FF8C8C")
WHITE = [1, 1, 1]
BANANA = rgb("#FFD84A")
BANANA_DARK = rgb("#E8A92C")
BANANA_TIP = rgb("#6B4518")
DUST = rgb("#D9D3E8")
SPARK = rgb("#FFF3A6")

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
    for f, v in zip(frames, values):
        s = [r1(x) for x in v] if dims > 1 else [r1(v)]
        if s == prev and f != frames[-1]:
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
    "head": ("torso", (3, -44)),
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
        x = lerp(-70, 292, f / F_RUN_END)
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

def capsule(length, width, color):
    return group([rect(0, length / 2, width, length + width, width / 2), fill(color)])


def banana_shape():
    pts = [
        (-17, -2, (0, 0), (4, 9)),
        (0, 7, (-9, 0), (9, 0)),
        (17, -3, (-3, 8), (0, 0)),
        (15, -6, (0, 0), (-4, 4)),
        (0, 1, (8, 0), (-8, 0)),
        (-14, -6, (4, 4), (0, 0)),
    ]
    body = group([path(pts), stroke(BANANA_DARK, 1.6), fill(BANANA)], "banana")
    shine = group([path([(-8, 1, (0, 0), (4, 3)), (6, 3, (-4, 1), (0, 0))], closed=False),
                   stroke([1, 0.97, 0.75], 1.6, 80)], "shine")
    tips = group([ellipse(-16.5, -4, 3.5, 4), ellipse(16, -4.5, 3, 3.5), fill(BANANA_TIP)], "tips")
    return [tips, shine, body]


def head_shapes():
    blink_frames = list(range(0, OP + 1, STEP))
    blink = [100 if not any(abs(f - b) < 4 for b in (40, 150, 230)) else 15 for f in blink_frames]
    eyes_tr = tr(sa=anim(blink_frames, [[100, v] for v in blink], dims=2))
    eyes_tr["p"] = static([6, -27])
    eyes_tr["a"] = static([6, -27])
    eyes = group([
        group([ellipse(1.5, -27, 2.4, 2.4), ellipse(15.5, -27, 2.4, 2.4), fill(WHITE)], "hl"),
        group([ellipse(0, -26, 6, 7), ellipse(14, -26, 6, 7), fill(INK)], "pupils"),
        group([ellipse(-2, -27, 11, 13), ellipse(12, -27, 11, 13), fill(WHITE)], "whites"),
    ], "eyes", eyes_tr)

    mouth_frames = list(range(0, OP + 1, STEP))
    open_v = [100 if timeline(f)[5] else 0 for f in mouth_frames]
    smile_tr = tr()
    smile_tr["o"] = anim(mouth_frames, [100 - v for v in open_v])
    open_tr = tr()
    open_tr["o"] = anim(mouth_frames, open_v)
    smile = group([path([(0, -14, (0, 0), (2, 4)), (12, -14, (-2, 4), (0, 0))], closed=False),
                   stroke(INK, 1.8)], "smile", smile_tr)
    mouth_open = group([ellipse(6, -11.5, 7, 8), fill(MOUTH)], "open", open_tr)
    return [
        group([path([(-3, -46, (0, 0), (2, -5)), (3, -49, (-2, 2), (0, 0)), (4, -43, (0, 0), (0, 0))]),
               fill(FUR_DARK)], "tuft"),
        eyes,
        mouth_open,
        smile,
        group([ellipse(4.5, -18.5, 2.2, 1.6), ellipse(8.5, -18.5, 2.2, 1.6), fill(INK, 85)], "nose"),
        group([ellipse(-7, -15, 7, 4.5), ellipse(18, -15, 7, 4.5), fill(CHEEK, 55)], "cheeks"),
        group([ellipse(-5, -28, 21, 21), ellipse(13, -28, 21, 21), ellipse(5, -15, 32, 20), fill(SKIN)], "face"),
        group([ellipse(2, -22, 48, 46), radial(FUR_LIGHT, FUR, FUR_DARK, (-8, -36), (26, -2))], "skull"),
        group([ellipse(27, -21, 8, 9), fill(EAR_IN)], "earR_in"),
        group([ellipse(26, -21, 14, 15), fill(FUR)], "earR"),
        group([ellipse(-22, -22, 8, 9), fill(EAR_IN)], "earL_in"),
        group([ellipse(-21, -22, 15, 16), fill(FUR)], "earL"),
    ]


def torso_shapes():
    return [
        group([ellipse(5, -19, 24, 30), fill(SKIN_DARK)], "belly"),
        group([ellipse(0, -22, 38, 50), radial(FUR_LIGHT, FUR, FUR_DARK, (-6, -36), (24, 0))], "body"),
    ]


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

    bone_layer("handN", [group([ellipse(0, 4, 12, 12), fill(SKIN_DARK)])], "hdN")
    bone_layer("forearmN", [capsule(19, 8.5, FUR)], "faN")
    bone_layer("upperarmN", [capsule(20, 9.5, FUR)], "uaN")
    bone_layer("footN", [group([ellipse(6, 3, 19, 9), fill(SKIN_DARK)])], "ftN")
    bone_layer("shinN", [capsule(16, 10, FUR)], "shN")
    bone_layer("thighN", [capsule(18, 12, FUR)], "thN")
    bone_layer("head", head_shapes(), "head")
    bone_layer("torso", torso_shapes(), "torso")
    bone_layer("footF", [group([ellipse(6, 3, 18, 8.5), fill(SKIN)])], "ftF")
    bone_layer("shinF", [capsule(16, 9.5, FUR_DARK)], "shF")
    bone_layer("thighF", [capsule(18, 11.5, FUR_DARK)], "thF")
    bone_layer("handF", [group([ellipse(0, 4, 11, 11), fill(SKIN)])], "hdF")
    bone_layer("forearmF", [capsule(19, 8, FUR_DARK)], "faF")
    bone_layer("upperarmF", [capsule(20, 9, FUR_DARK)], "uaF")
    bone_layer("tail3", [group([path([(0, 0, (0, 0), (8, 6)), (2, 16, (6, 2), (0, 0))], closed=False),
                                stroke(FUR_DARK, 6)])], "t3")
    bone_layer("tail2", [capsule(13, 6, FUR_DARK)], "t2")
    bone_layer("tail1", [capsule(15, 6.5, FUR_DARK)], "t1")

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
