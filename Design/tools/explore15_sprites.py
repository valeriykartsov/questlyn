#!/usr/bin/env python3
"""Прототип спрайтов «Побродить» (15A.7) для макетов: дома по климатическим зонам, центр города,
NPC по уровню и зоне, анимация шага героя, корабль. «Было» — те же алгоритмы, что сейчас в
ExploreRenderer.swift; «стало» — эскиз для Swift-реализации. Герой — образ E без изменений рисунка.

    python3 Design/tools/explore15_sprites.py <out_dir>
"""
import os
import re
import sys
from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")


def rgb(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255)


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3]) + ((c[3],) if len(c) == 4 else ())


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def h01(x, y, k=0):
    h = (x * 374761393 + y * 668265263 + k * 2147483647) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return (h ^ (h >> 16)) / 0xFFFFFFFF


class Sprite:
    def __init__(self, w, h):
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.px = self.img.load()
        self.w, self.h = w, h

    def set(self, x, y, c, a=255):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[x, y] = tuple(c[:3]) + (a,)

    def get(self, x, y):
        return self.px[x, y] if 0 <= x < self.w and 0 <= y < self.h else (0, 0, 0, 0)

    def poly(self, pts, c):
        ImageDraw.Draw(self.img).polygon(pts, fill=tuple(c[:3]) + (255,))

    def paste(self, other, x, y):
        self.img.alpha_composite(other.img if isinstance(other, Sprite) else other, (x, y))
        self.px = self.img.load()


def outline(sp, color=(42, 35, 32)):
    """Тёмный контур по краю непрозрачных пикселей — читаемость на снегу и песке."""
    src = sp.img.copy().load()
    for y in range(sp.h):
        for x in range(sp.w):
            if src[x, y][3] == 0 and any(0 <= x + dx < sp.w and 0 <= y + dy < sp.h and src[x + dx, y + dy][3] > 0
                                         for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                sp.set(x, y, color)

# ---------- герой и NPC: данные образа E из кода ----------

def load_rows():
    text = open(os.path.join(ROOT, "Questlyn/Hero/HeroSpriteData.swift")).read()
    rows = {}
    for m in re.finditer(r"case \.(\w+): \[(.*?)\]", text, re.S):
        rows[m.group(1)] = re.findall(r'"([^"]{32})"', m.group(2))
    return rows

ROWS = load_rows()


def palette(hair, skin, accent, outfit):
    def sh(h, f):
        return tuple(min(255, max(0, round(v * f))) for v in rgb(h))
    p = {"K": rgb(0x2A2320), "H": rgb(hair), "h": sh(hair, 0.76), "S": rgb(skin), "s": sh(skin, 0.86), "E": rgb(0x1F2A44),
         "C": rgb(accent), "Y": sh(accent, 1.3), "D": sh(accent, 0.75), "T": rgb(0xD8C7A0), "t": rgb(0xB9A57E),
         "B": rgb(0x6B4A2E), "b": rgb(0xC9772A), "P": rgb(0x3E4A63), "p": rgb(0x2F3A50), "F": rgb(0x5A3E2B), "G": rgb(0xD9A441),
         "W": rgb(0xF4EFE4), "M": rgb(0xA9B1BC), "m": rgb(0x7C8592), "Q": rgb(0x9FE3F0), "g": rgb(0x6B5A4A), "q": rgb(0x3FA7C4),
         "w": rgb(0x8A5A34), "V": rgb(0x8A5A3A), "v": rgb(0x6E4529), "L": rgb(0xE8E0CC), "R": rgb(0xB5473A), "Z": rgb(0xD9772B),
         "X": rgb(0xECE6DA), "J": rgb(0x4C6A8C), "j": rgb(0x3B5573), "z": rgb(0xE8EEF2), "N": rgb(0x2B2B35),
         "O": rgb(accent), "o": sh(accent, 0.75), "l": rgb(0x8A929C), "n": rgb(0x221F1C)}
    if outfit == "archer":
        p["P"], p["p"] = rgb(0x5B5240), rgb(0x47402F)
    if outfit == "coder":
        p["L"], p["l"] = rgb(0xA8B0BA), rgb(0x8A929C)
    return p


def person(outfit, hair, skin, accent, half=True, overlay=None):
    rows = [list(r) for r in ROWS[outfit]]
    if overlay:
        overlay(rows)
    pal = palette(hair, skin, accent, outfit)
    pal.update(EXTRA)
    sp = Sprite(32, 56)
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch != "." and ch in pal:
                sp.set(x, y, pal[ch])
    if half:
        h = Sprite(16, 28)
        for y in range(28):
            for x in range(16):
                c = sp.get(x * 2, y * 2)
                if c[3]:
                    h.set(x, y, c)
        return h
    return sp

# Дополнительные роли цветов для одежды зон.
EXTRA = {"1": rgb(0xEDE7DC), "2": rgb(0xC9C0B0), "3": rgb(0x7A5A3E), "4": rgb(0xE9D7B0), "5": rgb(0xC8AE7E), "6": rgb(0xB8651B)}


def fur(rows):
    """Север: меховая шапка и ворот."""
    for y in range(9, 14):
        for x in range(8, 24):
            if rows[y][x] in "Hh" or (y in (12, 13) and rows[y][x] == "K"):
                rows[y][x] = "1" if (x + y) % 3 else "2"
    for y in (24, 25):
        for x in range(9, 23):
            if rows[y][x] not in ".K":
                rows[y][x] = "1" if (x + y) % 2 else "2"


def scarf(rows):
    """Юг: светлый платок поверх волос и до плеч."""
    for y in range(8, 23):
        for x in range(6, 26):
            if rows[y][x] in "Hh":
                rows[y][x] = "4" if (x + y) % 4 else "5"
    for y in range(20, 26):
        for x in (8, 9, 22, 23):
            if rows[y][x] == ".":
                rows[y][x] = "5"


def walk_frames(base, n=4):
    """4 кадра шага: ноги по очереди вперёд, корпус покачивается на 1 px."""
    frames = []
    w, h = base.w, base.h
    foot_top = int(h * 52 / 56)
    for f in range(n):
        sp = Sprite(w, h + 2)
        bob = 1 if f % 2 == 1 else 0
        for y in range(h):
            for x in range(w):
                c = base.get(x, y)
                if not c[3]:
                    continue
                ny = y + 1 - bob
                if y >= foot_top:
                    left = x < w // 2
                    if f == 1:
                        ny += -1 if left else 1
                    elif f == 3:
                        ny += 1 if left else -1
                sp.set(x, ny, c)
        frames.append(sp)
    return frames


def with_shadow(sp, bg=None):
    """Тень-эллипс под ногами."""
    out = Sprite(sp.w + 4, sp.h + 3)
    d = ImageDraw.Draw(out.img)
    d.ellipse((2, sp.h - 3, sp.w + 1, sp.h + 2), fill=(20, 24, 40, 70))
    out.px = out.img.load()
    out.paste(sp, 2, 0)
    return out

# ---------- дома ----------

def house_old(height=11, roof=0xB8651B):
    sp = Sprite(15, height + 7)
    x, y = 7, height + 6
    for dy in range(height):
        for dx in range(-5, 6):
            sp.set(x + dx, y - dy, rgb(0xE9DCC0) if dx < 0 else rgb(0xCDBE9E))
    for k in range(3):
        sp.set(x - 2, y - k, rgb(0x5C3A1E))
    for dy in range(5):
        half = 6 - dy
        for dx in range(-half, half + 1):
            sp.set(x + dx, y - height - dy, shade(rgb(roof), 0.85 if dx > 0 else 1.0))
    return sp


def iso_house(a, h, wall_l, wall_r, roof, roof_kind="hip", rh=None, logs=False, snow=False, lit=False,
              door=0x5C3A1E, chimney=False, trim=None, win=None):
    """Изометрический дом: основание — ромб полуширины a, стены высоты h, крыша roof_kind."""
    rh = rh if rh is not None else a // 2 + 3
    W, H = 2 * a + 6, h + a + rh + 10
    sp = Sprite(W, H)
    cx, base = a + 3, H - 2           # нижняя точка переднего угла
    fy = base                          # передний нижний угол (0, a/2) → (cx, base)
    L, R = (cx - a, base - a // 2), (cx + a, base - a // 2)
    F = (cx, base)
    up = lambda p, k: (p[0], p[1] - k)
    wl, wr, rf = rgb(wall_l), rgb(wall_r), rgb(roof)
    sp.poly([L, F, up(F, h), up(L, h)], wl)
    sp.poly([F, R, up(R, h), up(F, h)], wr)
    if logs:
        for k in range(2, h, 3):
            for x in range(L[0], R[0] + 1):
                t = (x - L[0]) / (2 * a)
                y = (L[1] + (x - L[0]) // 2 if x <= cx else F[1] - (x - cx) // 2) - k
                sp.set(x, y, shade(wl if x <= cx else wr, 0.78))
    # Дверь — на левой стене, окна — на правой.
    for k in range(min(6, h - 2)):
        for dx in range(2):
            x = cx - a // 2 - 1 + dx
            y = L[1] + (x - L[0]) // 2 - k
            sp.set(x, y, rgb(door))
    wcol = rgb(0xF2B35B) if lit else (rgb(win) if win else rgb(0x5C6B7A))
    for wx in (cx + a // 3, cx + 2 * a // 3 + 1):
        for k in range(h // 2, h // 2 + 3):
            for dx in range(2):
                x = wx + dx
                y = F[1] - (x - cx) // 2 - k
                sp.set(x, y, wcol)
    if trim:
        for x in range(L[0], R[0] + 1):
            y = (L[1] + (x - L[0]) // 2 if x <= cx else F[1] - (x - cx) // 2) - h
            sp.set(x, y, rgb(trim))
    T = up(F, h)
    TL, TR, TB = up(L, h), up(R, h), (cx, base - a - h)
    e = 2  # свес крыши
    TLe, TRe, TFe, TBe = (TL[0] - e, TL[1]), (TR[0] + e, TR[1]), (T[0], T[1] + 1), (TB[0], TB[1] - 1)
    if roof_kind == "hip":
        apex = (cx, base - a // 2 - h - rh)
        sp.poly([TLe, TFe, apex], rf)
        sp.poly([TFe, TRe, apex], shade(rf, 0.78))
        if snow:
            for y in range(sp.h):
                for x in range(sp.w):
                    c = sp.get(x, y)
                    if c[3] and c[:3] in (rf, shade(rf, 0.78)[:3]) and y < apex[1] + rh * 0.65:
                        sp.set(x, y, rgb(0xF2F4F6) if c[:3] == rf else rgb(0xD5DCE2))
    elif roof_kind == "gable":
        # Конёк вдоль левой стены.
        r1, r2 = (TL[0] + a // 2, TL[1] - a // 4 - rh), (T[0] + a // 2, T[1] - a // 4 - rh)
        sp.poly([TLe, TFe, r2, r1], rf)
        sp.poly([TFe, TRe, r2], shade(wr, 0.95))
        sp.poly([r1, r2, TRe, (TB[0] + e, TB[1])], shade(rf, 0.8))
        for k in range(0, 999):
            pass
        if snow:
            for y in range(sp.h):
                for x in range(sp.w):
                    c = sp.get(x, y)
                    if c[3] and c[:3] == rf and h01(x, y, 3) < 0.85:
                        sp.set(x, y, rgb(0xF2F4F6))
    elif roof_kind == "flat":
        sp.poly([TL, T, TR, TB], shade(rgb(wall_l), 1.08))
        for p0, p1 in ((TL, T), (T, TR)):
            for k in range(abs(p1[0] - p0[0]) + 1):
                x = p0[0] + k
                y = p0[1] + (k // 2 if p1[1] > p0[1] else -(k // 2))
                sp.set(x, y - 1, shade(wl if x <= cx else wr, 0.9))
                sp.set(x, y - 2, shade(wl if x <= cx else wr, 0.9))
    if chimney:
        x0, y0 = cx + a // 2, base - a // 2 - h - rh + 3
        for y in range(y0 - 5, y0 + 2):
            for x in range(x0, x0 + 3):
                sp.set(x, y, rgb(0x8A7A6A) if x < x0 + 2 else rgb(0x6E6054))
    return sp


def yurt(r=9, h=8, felt=0xE9DCC0, band=0xB8651B, lit=False):
    W, H = 2 * r + 6, h + r + 12
    sp = Sprite(W, H)
    cx, base = r + 3, H - 3
    d = ImageDraw.Draw(sp.img)
    d.rectangle((cx - r, base - h - r // 2, cx + r, base - r // 4), fill=rgb(felt) + (255,))
    d.ellipse((cx - r, base - r // 2, cx + r, base + 1), fill=rgb(felt) + (255,))
    d.polygon([(cx - r - 1, base - h - r // 3), (cx + r + 1, base - h - r // 3), (cx, base - h - r - 2)], fill=shade(rgb(felt), 0.9) + (255,))
    sp.px = sp.img.load()
    for x in range(cx - r, cx + r + 1):
        for y in range(H):
            c = sp.get(x, y)
            if c[3] and x > cx:
                sp.set(x, y, shade(c, 0.86))
    for x in range(cx - r, cx + r + 1):
        sp.set(x, base - h + 1 - abs(x - cx) // 4, rgb(band))
        sp.set(x, base - h + 2 - abs(x - cx) // 4, rgb(band))
    for k in range(5):
        sp.set(cx - 2, base - k, rgb(0x5C3A1E))
        sp.set(cx - 1, base - k, rgb(0xF2B35B) if lit else rgb(0x5C3A1E))
    sp.set(cx, base - h - r - 2, rgb(0x6B4A2E))
    return sp


def dome_house(a=8, h=9, lit=False):
    sp = iso_house(a, h, 0xE2C69A, 0xC9A97A, 0xE2C69A, roof_kind="flat", lit=lit, door=0x6E4529)
    d = ImageDraw.Draw(sp.img)
    cx = a + 3
    top = sp.h - 2 - a // 2 - h
    d.ellipse((cx - a // 2 - 1, top - a // 2 - 3, cx + a // 2 + 1, top + 2), fill=rgb(0xF0E2C4) + (255,))
    sp.px = sp.img.load()
    for y in range(sp.h):
        for x in range(cx + 1, sp.w):
            c = sp.get(x, y)
            if c[3] and c[:3] == rgb(0xF0E2C4):
                sp.set(x, y, rgb(0xD9C49E))
    return sp


ZONE_HOUSES = {
    "tundra": lambda lit=False: [iso_house(8, 9, 0x8A6A4A, 0x6E5238, 0x6E4529, "hip", logs=True, snow=True, lit=lit, chimney=True),
                                 iso_house(7, 8, 0x8A6A4A, 0x6E5238, 0x6E4529, "gable", logs=True, snow=True, lit=lit)],
    "taiga": lambda lit=False: [iso_house(8, 10, 0x9A7450, 0x7A5A3E, 0x4E5A3A, "gable", logs=True, lit=lit, chimney=True),
                                iso_house(7, 8, 0x9A7450, 0x7A5A3E, 0x6E4529, "hip", logs=True, lit=lit)],
    "temperate": lambda lit=False: [iso_house(8, 11, 0xEDE3CC, 0xD3C6A8, 0xB8651B, "gable", lit=lit, chimney=True, trim=0x6E4529),
                                    iso_house(7, 9, 0xEDE3CC, 0xD3C6A8, 0x3E5C8A, "hip", lit=lit, trim=0x6E4529)],
    "steppe": lambda lit=False: [yurt(lit=lit), iso_house(7, 8, 0xD9C7A0, 0xBDA982, 0x9C8E4E, "hip", lit=lit)],
    "desert": lambda lit=False: [dome_house(lit=lit), iso_house(7, 8, 0xE2C69A, 0xC9A97A, 0xE2C69A, "flat", lit=lit, door=0x6E4529)],
}
ZONE_GROUND = {"tundra": (0xE6ECF0, 0xDCE3E8), "taiga": (0x7E9A6A, 0x75915F), "temperate": (0x7FA552, 0x76994B),
               "steppe": (0xC2B56E, 0xB8AA62), "desert": (0xE8CF8E, 0xDFC383)}

# ---------- сцена: участок земли и объекты ----------

TW, TH = 16, 8


def ground_patch(n, zone, night=False, plaza=None):
    """Ромб n×n клеток земли зоны; plaza — множество клеток площади."""
    W, H = n * TW + 8, n * TH + 60
    sp = Sprite(W, H)
    ox, oy = W // 2, 52
    g0, g1 = rgb(ZONE_GROUND[zone][0]), rgb(ZONE_GROUND[zone][1])
    for ly in range(n):
        for lx in range(n):
            cx, cy = ox + (lx - ly) * TW // 2, oy + (lx + ly) * TH // 2 + TH // 2
            for py in range(TH):
                half = (py + 1) * 2 if py < TH // 2 else (TH - py) * 2
                for dx in range(-half, half):
                    x, y = cx + dx, cy - TH // 2 + py
                    c = g0 if h01(x // 3, y // 2, 5) < 0.55 else g1
                    if plaza and (lx, ly) in plaza:
                        c = rgb(0xB9AE9A) if h01(x, y, 21) < 0.8 else rgb(0x8E8574)
                        if (x + 2 * y) % 8 == 0:
                            c = rgb(0xA79C87)
                    sp.set(x, y, c)
    return sp, (lambda lx, ly: (ox + (lx - ly) * TW // 2, oy + (lx + ly) * TH // 2 + TH // 2))


def place(scene, items):
    """items: (глубина, спрайт, x центра, y низа)."""
    for _, s, x, y in sorted(items, key=lambda t: t[0]):
        scene.paste(s, x - s.w // 2, y - s.h + 1)


def well():
    sp = Sprite(14, 18)
    d = ImageDraw.Draw(sp.img)
    d.ellipse((1, 9, 12, 16), fill=rgb(0x8E8574) + (255,))
    d.ellipse((3, 10, 10, 14), fill=rgb(0x2B5884) + (255,))
    d.rectangle((1, 4, 2, 12), fill=rgb(0x6E4529) + (255,))
    d.rectangle((11, 4, 12, 12), fill=rgb(0x6E4529) + (255,))
    d.polygon([(0, 5), (7, 0), (13, 5)], fill=rgb(0xB8651B) + (255,))
    sp.px = sp.img.load()
    return sp


def stall(color=0xA8432F):
    sp = Sprite(18, 18)
    d = ImageDraw.Draw(sp.img)
    d.rectangle((2, 10, 15, 16), fill=rgb(0x9A7450) + (255,))
    d.rectangle((2, 9, 15, 10), fill=rgb(0xD9A441) + (255,))
    for x in range(1, 17):
        for y in range(3, 8):
            sp.img.putpixel((x, y), (rgb(color) if (x // 3) % 2 else rgb(0xF4EFE4)) + (255,))
    d.rectangle((2, 7, 2, 16), fill=rgb(0x5C3A1E) + (255,))
    d.rectangle((15, 7, 15, 16), fill=rgb(0x5C3A1E) + (255,))
    sp.px = sp.img.load()
    return sp


def temple(zone="temperate", lit=False):
    roof = {"tundra": 0x6E4529, "desert": 0xF0E2C4}.get(zone, 0x3E5C8A)
    sp = iso_house(7, 22, 0xD8D0C0, 0xB8AE9C, roof, "hip", rh=12, lit=lit, door=0x4E3A2A, snow=(zone == "tundra"))
    sp.set(sp.w // 2, 1, rgb(0xD9A441))
    sp.set(sp.w // 2, 2, rgb(0xD9A441))
    return sp


def board_post():
    sp = Sprite(12, 16)
    d = ImageDraw.Draw(sp.img)
    d.rectangle((2, 7, 3, 15), fill=rgb(0x5C3A1E) + (255,))
    d.rectangle((8, 7, 9, 15), fill=rgb(0x5C3A1E) + (255,))
    d.rectangle((0, 1, 11, 9), fill=rgb(0x9A7450) + (255,))
    d.rectangle((2, 3, 5, 6), fill=rgb(0xF4EFE4) + (255,))
    d.rectangle((7, 2, 9, 5), fill=rgb(0xF4EFE4) + (255,))
    sp.px = sp.img.load()
    sp.set(3, 4, rgb(0x1F2A44))
    sp.set(8, 3, rgb(0x1F2A44))
    return sp


def stake():
    sp = Sprite(3, 12)
    for y in range(2, 12):
        sp.set(0, y, rgb(0x8A6A4A))
        sp.set(1, y, rgb(0x6E5238))
    sp.set(0, 1, rgb(0x8A6A4A))
    return sp


def tree(zone):
    sp = Sprite(11, 14)
    leaf = {"tundra": rgb(0x2F4A3E), "taiga": rgb(0x2E5A3E), "temperate": rgb(0x3E6B2E), "steppe": rgb(0x7E8A46), "desert": rgb(0x5E8A4A)}[zone]
    for k in range(3):
        sp.set(5, 13 - k, rgb(0x5C3A1E))
    for dy in range(9):
        half = dy // 2 if zone in ("tundra", "taiga") else (dy + 1 if dy < 4 else 8 - dy)
        for dx in range(-half, half + 1):
            c = leaf
            if zone == "tundra" and (dy % 3 == 0):
                c = rgb(0xF2F4F6)
            sp.set(5 + dx, 2 + dy, c if dx <= 0 else shade(c, 0.85))
    return sp


def city_scene(zone, night=False):
    n = 11
    plaza = {(x, y) for x in range(4, 7) for y in range(4, 7)}
    sp, at = ground_patch(n, zone, plaza=plaza)
    items = []
    houses = ZONE_HOUSES[zone](night)
    spots = [(2, 1), (8, 2), (1, 5), (9, 7), (6, 9), (2, 8), (8, 4)]
    for i, (lx, ly) in enumerate(spots):
        h = houses[i % len(houses)]
        x, y = at(lx, ly)
        items.append((lx + ly, h, x, y + 3))
    x, y = at(5, 5)
    items.append((10, well(), x, y + 4))
    x, y = at(4, 6)
    items.append((10.2, stall(), x, y + 3))
    x, y = at(6, 4)
    items.append((10.1, stall(0x3E5C8A), x, y + 3))
    x, y = at(4, 4)
    items.append((8.5, board_post(), x, y + 2))
    x, y = at(1, 1)
    items.append((2.5, temple(zone, night), x, y + 3))
    for k in range(n):
        for (lx, ly) in ((k, 0), (0, k)):
            if (lx, ly) == (0, 0) or k in (5, 6):
                continue
            x, y = at(lx, ly)
            items.append((lx + ly - 0.6, stake(), x - 4 if lx == 0 else x + 4, y - 2))
    for (lx, ly) in ((10, 1), (0, 10), (10, 10), (3, 10)):
        x, y = at(lx, ly)
        items.append((lx + ly, tree(zone), x, y + 1))
    place(sp, items)
    if night:
        night_tint(sp, [(at(5, 5)[0], at(5, 5)[1] - 4)])
    return sp


def night_tint(sp, lights):
    for y in range(sp.h):
        for x in range(sp.w):
            c = sp.get(x, y)
            if not c[3]:
                continue
            r, g, b = c[:3]
            warm = r > 230 and 150 < g < 200 and b < 110   # окна
            if warm:
                continue
            glow = 0
            for lx, ly in lights:
                import math
                d = math.hypot(x - lx, (y - ly) * 1.6)
                if d < 40:
                    glow = max(glow, (1 - d / 40) ** 1.5)
            nr, ng, nb = int(r * 0.42 + 10), int(g * 0.42 + 13), int(b * 0.42 + 34)
            if glow and h01(x, y, 51) < glow * 1.4:
                nr, ng, nb = int(nr + (r - nr) * glow + 60 * glow), int(ng + (g * 0.85 - ng) * glow + 30 * glow), int(nb + (b * 0.6 - nb) * glow)
            sp.set(x, y, (min(255, nr), min(255, ng), min(255, nb)))
    # Ореол окон.
    src = sp.img.copy().load()
    for y in range(sp.h):
        for x in range(sp.w):
            c = src[x, y]
            if c[3] and c[0] > 230 and 150 < c[1] < 200 and c[2] < 110:
                for dx in range(-3, 4):
                    for dy in range(-2, 3):
                        q = sp.get(x + dx, y + dy)
                        if q[3] and not (q[0] > 230 and q[2] < 110) and h01(x + dx, y + dy, 9) < 0.5:
                            sp.set(x + dx, y + dy, mix(q[:3], (242, 179, 91), 0.35))

# ---------- корабль ----------

def frigate_old():
    sp = Sprite(48, 40)
    hull, wood, line = rgb(0x6B3F22), rgb(0x7A4A2A), rgb(0x3B2414)
    sail, shd, port, stripe = rgb(0xFFFCF6), rgb(0xE3DCCB), rgb(0x2A1A0E), rgb(0xE3CF9A)
    for x, top in ((14, 6), (25, 2), (37, 9)):
        for y in range(top, 29):
            sp.set(x, y, line)
    for left, right, rows in ((9, 19, [(8, 14), (16, 22)]), (19, 31, [(4, 11), (13, 21)]), (32, 42, [(11, 16), (18, 22)])):
        for top, bottom in rows:
            for y in range(top, bottom + 1):
                for x in range(left, right + 1):
                    sp.set(x, y, shd if y == bottom or x == left or x == right else sail)
    for y in range(10, 27):
        frm = 13 - (y - 10) * 11 // 16
        for x in range(frm, 14):
            sp.set(x, y, shd if x == frm else sail)
    for y in range(0, 3):
        for x in range(26, 31):
            sp.set(x, y, rgb(0xA8432F))
    for y in range(22, 29):
        for x in range(35, 47):
            sp.set(x, y, line if y == 22 or x == 35 or x == 46 else wood)
    for y in range(28, 36):
        left, right = 3 + (y - 28), 46 - (y - 28) // 2
        for x in range(left, right + 1):
            sp.set(x, y, line if y == 35 or x == left or x == right else hull)
    for x in range(4, 46):
        sp.set(x, 28, line)
    for x in range(8, 43):
        sp.set(x, 30, port if x % 4 == 0 else stripe)
    for k in range(7):
        sp.set(3 - k // 2, 28 - k, line)
    for x in range(5, 45, 3):
        sp.set(x, 36, rgb(0xDDE8F2))
        sp.set(x + 1, 36, rgb(0xDDE8F2))
    return sp


def ship_iso(frame=0, flag=0xA8432F, sails=2):
    """Корабль, идущий по диагонали изометрии вправо-вниз; отражение — влево-вниз."""
    W, H = 72, 64
    sp = Sprite(W, H)
    hull, hull_d, deck, line = rgb(0x6B3F22), rgb(0x4E2E18), rgb(0xA87A4E), rgb(0x3B2414)
    # Ось корабля u = (2, 1), поперёк v = (-2, 1) в пикселях изометрии.
    cx, cy = 34, 46
    bow, stern = (cx + 22, cy + 11), (cx - 20, cy - 10)
    half = 4
    s1, s2 = (stern[0] - half, stern[1] + half // 2), (stern[0] + half, stern[1] - half // 2)
    m1, m2 = (cx - half - 2, cy + half // 2 + 1), (cx + half + 2, cy - half // 2 - 1)
    deck_poly = [s2, m2, bow, m1, s1]
    # Борт к зрителю: высокий, нос задран, ниже ватерлинии — тёмная полоса.
    drop = 10
    bottom = [(bow[0] - 6, bow[1] + drop - 3), (m1[0] + 2, m1[1] + drop), (s1[0] + 1, s1[1] + drop - 1)]
    sp.poly([s1, m1, bow] + bottom, hull)
    sp.poly([(x, y + drop - 3) for (x, y) in [s1, m1]] + [(bow[0] - 5, bow[1] + drop - 4)] + bottom, hull_d)
    sp.poly(deck_poly, deck)
    # Фальшборт — тёмная кромка палубы.
    ImageDraw.Draw(sp.img).line(deck_poly + [deck_poly[0]], fill=line + (255,))
    sp.px = sp.img.load()
    # Доски палубы.
    for k in range(-4, 5, 2):
        for t in range(0, 40):
            x = stern[0] + t + (-k)
            y = stern[1] + t // 2 + k // 2
            c = sp.get(x, y)
            if c[3] and c[:3] == deck:
                sp.set(x, y, shade(deck, 0.88))
    # Полоса и порты.
    for t in range(0, 44):
        x = s1[0] + t
        y = s1[1] + 2 + t // 2 - (1 if t > 30 else 0)
        c = sp.get(x, y)
        if c[3]:
            sp.set(x, y, rgb(0xE3CF9A) if t % 5 else rgb(0x2A1A0E))
    # Корма — надстройка.
    for y in range(stern[1] - 6, stern[1] + 3):
        for x in range(stern[0] - 4, stern[0] + 6):
            sp.set(x, y, rgb(0x7A4A2A) if x < stern[0] + 1 else rgb(0x5E3820))
    sp.set(stern[0] - 2, stern[1] - 3, rgb(0xF2B35B))
    # Мачты и паруса: парус развёрнут к зрителю, «дышит» по кадрам.
    masts = [(cx + 6, cy + 1, 30)] + ([(cx - 9, cy - 6, 24)] if sails > 1 else [])
    bulge = [0, 1, 2, 1][frame % 4]
    for mx, my, mh in masts:
        for y in range(my - mh, my + 1):
            sp.set(mx, y, line)
        for y0, y1, w in ((my - mh + 4, my - mh + 13, 9), (my - mh + 15, my - mh + 24, 11)):
            for y in range(y0, min(y1, my - 2) + 1):
                t = (y - y0) / max(1, (y1 - y0))
                b = int(round(bulge * (1 - (2 * t - 1) ** 2)))
                for x in range(mx - w + b, mx + w + 1 + b):
                    yy = y + (x - mx) // 5
                    edge = x in (mx - w + b, mx + w + b) or y == y0
                    c = rgb(0xE3DCCB) if edge else (rgb(0xFFFCF6) if x < mx + b else rgb(0xEDE6D6))
                    sp.set(x, yy, c)
        # Флаг на грот-мачте развевается.
    mx, my, mh = masts[0]
    for k in range(6):
        for j in range(3):
            sp.set(mx + 1 + k, my - mh + j + (1 if (k + frame) % 4 == 0 else 0), rgb(flag))
    # Бушприт.
    for k in range(8):
        sp.set(bow[0] + k, bow[1] - 2 - k // 2, line)
    return sp


def sea(w, h, wake=None, k=0):
    sp = Sprite(w, h)
    for y in range(h):
        for x in range(w):
            c = rgb(0x3F6E9C) if h01(x // 3, y, 7) < 0.6 else rgb(0x37658F)
            if h01(x, y, 8 + k) < 0.02:
                c = rgb(0x6A9CC2)
            sp.set(x, y, c)
    if wake:
        # След — «V» от кормы назад, расходится и тает.
        x0, y0, length = wake
        for t in range(length):
            spread = t / 3.5
            for sgn in (-1, 1):
                x = int(x0 - 2 * t - sgn * spread)
                y = int(y0 - t + sgn * spread * 2 / 2)
                if h01(x, y, k + 3) < 0.95 - t / length * 0.7:
                    sp.set(x, y, rgb(0xE6F0F4))
                    sp.set(x + 1, y, rgb(0xB8D3E6))
            if t < length // 2 and h01(t, k, 4) < 0.5:
                sp.set(int(x0 - 2 * t), int(y0 - t), rgb(0x6A9CC2))
    return sp


def shadow_on_water(sp, ship, x, y):
    for yy in range(ship.h):
        for xx in range(ship.w):
            if ship.get(xx, yy)[3] and yy > ship.h - 22:
                q = sp.get(x + xx + 3, y + yy + 3)
                if q[3]:
                    sp.set(x + xx + 3, y + yy + 3, shade(q, 0.8))


def mirror(sp):
    out = Sprite(sp.w, sp.h)
    out.img = sp.img.transpose(Image.FLIP_LEFT_RIGHT)
    out.px = out.img.load()
    return out


def scale(img, k):
    img = img.img if isinstance(img, Sprite) else img
    return img.resize((img.width * k, img.height * k), Image.NEAREST)


def save(sp, name):
    (sp.img if isinstance(sp, Sprite) else sp).save(os.path.join(OUT, name), optimize=True)


def on_bg(sp, color, pad=4):
    bg = Sprite(sp.w + pad * 2, sp.h + pad * 2)
    bg.img = Image.new("RGBA", (bg.w, bg.h), rgb(color) + (255,))
    bg.px = bg.img.load()
    bg.paste(sp, pad, pad)
    return bg


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    # Дома: было — три дома с разной крышей; стало — по зонам.
    old = Sprite(60, 26)
    for i, roof in enumerate((0xB8651B, 0x8A4B3A, 0x3E5C8A)):
        old.paste(house_old(9 + i * 2, roof), 2 + i * 19, 26 - (9 + i * 2) - 7)
    save(on_bg(old, 0x7FA552), "h_old.png")
    for zone, make in ZONE_HOUSES.items():
        hs = make()
        row = Sprite(sum(h.w for h in hs) + 6 * len(hs), max(h.h for h in hs))
        x = 0
        for h in hs:
            row.paste(h, x, row.h - h.h)
            x += h.w + 6
        save(on_bg(row, ZONE_GROUND[zone][0], 6), f"h_{zone}.png")
    # Город: было — домики кучкой; стало — площадь, колодец, рынок, храм, частокол.
    oldcity, at = ground_patch(11, "temperate")
    items = []
    for k, (ax, ay) in enumerate([(5, 5), (6, 4), (4, 6), (6, 6), (4, 4), (7, 5)]):
        x, y = at(ax, ay)
        items.append((ax + ay, house_old(9 + (k % 3) * 2, [0xB8651B, 0x8A4B3A, 0x3E5C8A, 0x2F6B4F, 0x6B4FA3][k % 5]), x, y))
    place(oldcity, items)
    save(oldcity, "c_old.png")
    save(city_scene("temperate"), "c_temperate.png")
    save(city_scene("temperate", night=True), "c_temperate_night.png")
    save(city_scene("tundra"), "c_tundra.png")
    save(city_scene("desert"), "c_desert.png")
    # NPC: было — 4 вида из кода; стало — уровень × зона.
    looks = [("archer", 0xC46A3A, 0xF2D0B0, 0x8A4B3A), ("warrior", 0xE0C27A, 0xC98E68, 0x3E5C8A),
             ("mage", 0x1F1A16, 0x8C5A3C, 0x6B4FA3), ("baller", 0x3B2A20, 0xE8B892, 0x2F6B4F)]
    row = Sprite(4 * 22, 30)
    for i, (o, h, s, a) in enumerate(looks):
        row.paste(person(o, h, s, a), 3 + i * 22, 1)
    save(on_bg(row, 0x7FA552), "n_old.png")
    tiers = [("Знакомый", "coder", 0x7A8A6A), ("Коллега", "archer", 0x3E5C8A), ("Постоянный", "warrior", 0x8A4B3A)]
    zones = [("tundra", fur, 0xE6ECF0), ("temperate", None, 0x7FA552), ("desert", scarf, 0xE8CF8E)]
    for zi, (zone, ov, bg) in enumerate(zones):
        row = Sprite(3 * 26, 34)
        for ti, (_, outfit, acc) in enumerate(tiers):
            p = person(outfit, [0x3B2A20, 0xC46A3A, 0x1F1A16][ti], [0xF2D0B0, 0xE8B892, 0xC98E68][(ti + zi) % 3], acc, overlay=ov)
            outline(p, (31, 28, 26))
            row.paste(with_shadow(p), 3 + ti * 26, 1)
        save(on_bg(row, bg), f"n_{zone}.png")
    # Шаг NPC — 4 кадра.
    base = person("archer", 0xC46A3A, 0xF2D0B0, 0x3E5C8A)
    fr = walk_frames(base)
    row = Sprite(4 * 22, 34)
    for i, f in enumerate(fr):
        row.paste(with_shadow(f), 2 + i * 22, 1)
    save(on_bg(row, 0x7FA552), "n_walk.png")
    # Герой: было — половинный 16×28; стало — полный 32×56 на тех же точках экрана, тень, шаг.
    hero_half = person("mage", 0x3B2A20, 0xE8B892, 0x2F6B4F)
    hero_full = person("mage", 0x3B2A20, 0xE8B892, 0x2F6B4F, half=False)
    for bg, nm in ((0xE6ECF0, "snow"), (0xE8CF8E, "sand"), (0x7FA552, "grass")):
        save(on_bg(scale(hero_half, 2) and Sprite(1, 1), bg) if False else on_bg(hero_half, bg), f"hero_old_{nm}.png")
        hf = with_shadow(hero_full)
        save(on_bg(hf, bg), f"hero_new_{nm}.png")
    frames = walk_frames(hero_full)
    row = Sprite(4 * 40, 62)
    for i, f in enumerate(frames):
        row.paste(with_shadow(f), 2 + i * 40, 0)
    save(on_bg(row, 0x7FA552), "hero_walk.png")
    # Корабль: было; стало — 2 направления, 4 кадра паруса, след, тень, у причала.
    s_old = sea(80, 56)
    s_old.paste(frigate_old(), 16, 10)
    save(s_old, "s_old.png")
    for i in range(4):
        sc = sea(96, 76, wake=(30, 36, 22), k=i)
        sh = ship_iso(i)
        shadow_on_water(sc, sh, 14, 6)
        sc.paste(sh, 14, 6)
        save(sc, f"s_new_{i}.png")
    sc = sea(96, 76, wake=(30, 36, 22), k=5)
    sh = ship_iso(1)
    shadow_on_water(sc, sh, 14, 6)
    sc.paste(sh, 14, 6)
    sc = mirror(sc)
    save(sc, "s_new_left.png")
    sc = sea(96, 76)
    up = ship_iso(0, sails=2)
    # Причал: деревянный настил, корабль со спущенными парусами показан тем же спрайтом без паруса.
    d = ImageDraw.Draw(sc.img)
    d.polygon([(0, 30), (40, 50), (40, 56), (0, 36)], fill=rgb(0x9A7450) + (255,))
    for k in range(0, 40, 4):
        d.line([(k, 30 + k // 2), (k, 36 + k // 2)], fill=rgb(0x6E5238) + (255,))
    sc.px = sc.img.load()
    sc.paste(ship_iso(0, flag=0x2F6B4F, sails=1), 22, 2)
    save(sc, "s_dock.png")
    print("ok")
