#!/usr/bin/env python3
"""Оружие героя (запрос 17.11.2026, только вид): шесть видов в руке на рисунке образа E 32×56.
Руки берутся без предмета (как у «Программиста»), поверх — оружие. Сетки — образец для Swift.

    python3 Design/tools/weapons_mock.py <out_dir>
"""
import importlib.util
import os
import sys
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
HERE = os.path.dirname(os.path.abspath(__file__))
sys.argv = [sys.argv[0], OUT]
spec = importlib.util.spec_from_file_location("sprites", os.path.join(HERE, "explore15_sprites.py"))
sp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sp)

# Сетки оружия 32×56: «.» — прозрачно; K — контур, M/m — сталь, W — блик, B/b — дерево, G — золото.
W_COLORS = {"K": (42, 35, 32), "M": (169, 177, 188), "m": (124, 133, 146), "W": (244, 239, 228), "B": (107, 74, 46),
            "b": (138, 90, 52), "G": (217, 164, 65), "R": (168, 67, 47), "r": (200, 44, 40), "s": (232, 96, 80),
            "d": (122, 24, 26), "N": (28, 24, 30), "Y": (196, 40, 40)}
# Буква со «*» в начале — рисуется только позади тела (на прозрачных пикселях).


def grid(points):
    g = [["."] * 32 for _ in range(56)]
    for (x, y, c) in points:
        if 0 <= x < 32 and 0 <= y < 56:
            g[y][x] = c
    return g


# Поле вокруг рисунка 32×56 для оружия, которое выходит за руку: координаты оружия — в рисунке, могут быть < 0.
PAD = 10


def katana():
    """Катана под 45° к земле, лезвие — от персонажа. Короткая рукоять в кулаке (7–8, 31–32), навершие чуть
    выше кулака; цуба и муфта сразу под кулаком; клинок широкий у гарды и сужается к острию на конце."""
    p = []
    # Рукоять сквозь кулак: навершие, оплётка.
    p += [(10, 29, "G"), (11, 28, "K"), (9, 30, "N"), (8, 31, "Y"), (7, 32, "N"), (6, 33, "Y"), (10, 30, "K"), (9, 29, "K")]
    # Цуба — сплошная золотая пластина поперёк клинка, сразу под кулаком.
    for (x, y) in [(3, 33), (7, 33), (5, 31), (5, 35), (3, 32), (7, 34), (4, 31), (6, 35), (2, 33), (6, 31)]:
        p.append((x, y, "K"))
    for (x, y) in [(5, 33), (4, 33), (6, 33), (5, 32), (5, 34), (4, 32), (6, 34), (4, 34), (6, 32)]:
        p.append((x, y, "G"))
    p += [(5, 33, "W")]
    # Клинок вниз-наружу: у гарды — обух, сталь, кромка; к концу сужается до острия.
    n = 16
    for k in range(1, n + 1):
        x, y = 4 - k, 34 + k
        if k <= n - 4:
            p += [(x - 1, y, "d"), (x, y, "r"), (x + 1, y, "s"), (x - 2, y, "K"), (x + 2, y, "K"), (x + 1, y + 1, "K")]
        elif k <= n - 1:
            p += [(x, y, "r"), (x + 1, y, "s"), (x - 1, y, "K"), (x + 2, y, "K"), (x + 1, y + 1, "K")]
        else:
            p += [(x, y, "s"), (x - 1, y, "K"), (x + 1, y, "K"), (x, y + 1, "K")]
    return p


def axe():
    p = []
    for y in range(12, 42):
        p += [(6, y, "K"), (7, y, "b" if y % 4 else "B"), (8, y, "K")]
    for y in range(12, 22):
        w = 5 - abs(y - 16) // 2
        for x in range(1, 6):
            if x >= 6 - w:
                p.append((x, y, "M" if x > 1 else "W"))
        p.append((6 - w - 1, y, "K"))
    return p


def spear():
    """Копьё за спиной по диагонали, лезвие — к земле: длинное листовидное лезвие внизу слева, конец древка над плечом."""
    p = []
    for k in range(0, 26):
        x, y = 4 + k, 38 - k
        p += [("*", x, y, "b"), ("*", x, y + 1, "B"), ("*", x - 1, y, "K"), ("*", x + 1, y + 1, "K")]
    p += [(30, 12, "B"), (31, 11, "K"), (30, 11, "K")]
    # Втулка и кисть у основания лезвия.
    p += [(4, 39, "G"), (3, 40, "G"), (5, 40, "R"), (4, 41, "R"), (2, 41, "R"), (3, 42, "R")]
    # Лезвие: вытянутый лист вдоль диагонали вниз-влево, ребро и кромки.
    for k in range(0, 13):
        cx, cy = 2 - k * 7 // 10, 42 + k
        w = [1, 2, 2, 3, 3, 3, 3, 2, 2, 2, 1, 1, 0][k]
        for d in range(-w, w + 1):
            p.append((cx + d, cy, "W" if d == 0 else ("M" if d > 0 else "m")))
        p += [(cx - w - 1, cy, "K"), (cx + w + 1, cy, "K")]
    p += [(-7, 55, "K")]
    return p


def hammer():
    p = []
    for y in range(16, 44):
        p += [(6, y, "K"), (7, y, "B"), (8, y, "K")]
    for y in range(10, 18):
        for x in range(2, 13):
            p.append((x, y, "K" if y in (10, 17) or x in (2, 12) else ("W" if y == 11 else ("m" if x > 8 else "M"))))
    return p


def daggers():
    """Парные кинжалы под 45°: рукоять в кисти (левая 8–9, правая 22–23, ряды 36–37), клинок вниз-наружу."""
    p = []
    for hx, sx in ((8, -1), (23, 1)):
        p += [(hx, 36, "B"), (hx, 37, "B"), (hx - sx, 35, "G")]
        p += [(hx + sx, 38, "G"), (hx, 38, "G"), (hx + 2 * sx, 38, "K")]
        for k in range(1, 8):
            x, y = hx + sx * k, 38 + k
            p += [(x, y, "W" if k < 6 else "M"), (x - sx, y, "m"), (x + sx, y, "K"), (x - sx, y + 1, "K")]
    return p


def crossbow():
    p = []
    for x in range(0, 13):
        p += [(x, 30, "K"), (x, 31, "b"), (x, 32, "B"), (x, 33, "K")]
    for y in range(25, 39):
        p += [(1, y, "M" if 26 <= y <= 37 else "K"), (2, y, "K")]
    for y in range(26, 38):
        p.append((3 + abs(y - 31) // 3, y, "W"))
    p += [(12, 29, "M"), (13, 30, "M"), (13, 31, "M")]
    return p


WEAPONS = [("Катана", katana), ("Топор", axe), ("Копьё", spear), ("Молот", hammer), ("Парные кинжалы", daggers), ("Арбалет", crossbow)]


def rows_of(outfit):
    return [list(r) for r in sp.ROWS[outfit]]


# Оружие в руке нарисовано под кисть (7–8, 31–32); у рук «Ассасина» кисть ниже и правее — сдвиг (+1, +5).
HAND_SHIFT = (1, 5)
UNSHIFTED = {"daggers", "spear"}


def compose(base_outfit, weapon=None, hair=0x3B2A20, skin=0xE8B892, accent=0x2F6B4F):
    """Образ base_outfit; руки — как у «Ассасина» (опущены, без его кинжалов), поверх — оружие."""
    base = rows_of(base_outfit)
    if weapon:
        arms = rows_of("assassin")
        plain = rows_of("coder")
        for y in range(24, 52):
            for x in range(32):
                if x < 10 or x > 21:
                    # Руки ассасина до кистей (ряды 24–37), ниже — без предмета.
                    base[y][x] = arms[y][x] if y <= 37 else plain[y][x]
    pal = sp.palette(hair, skin, accent, base_outfit)
    pal.update(sp.EXTRA)
    img = Image.new("RGBA", (32 + 2 * PAD, 56), (0, 0, 0, 0))
    px = img.load()
    for y, r in enumerate(base):
        for x, ch in enumerate(r):
            if ch != "." and ch in pal:
                px[x + PAD, y] = pal[ch] + (255,)
    if weapon:
        dx, dy = (0, 0) if weapon.__name__ in UNSHIFTED else HAND_SHIFT
        points = [(t[0], t[1] + dx, t[2] + dy, t[3]) if t[0] == "*" else (t[0] + dx, t[1] + dy, t[2]) for t in weapon()]
        for (_, x, y, c) in [t for t in points if t[0] == "*"]:
            if -PAD <= x < 32 + PAD and 0 <= y < 56 and px[x + PAD, y][3] == 0:
                px[x + PAD, y] = W_COLORS[c] + (255,)
        for (x, y, c) in [t for t in points if t[0] != "*"]:
            if -PAD <= x < 32 + PAD and 0 <= y < 56:
                px[x + PAD, y] = W_COLORS[c] + (255,)
        # Пальцы поверх рукояти — хват (кожа рук «S»/«s» в рядах 35–38).
        for y in range(35, 39):
            for x in list(range(5, 11)) + list(range(21, 27)):
                if base[y][x] in "Ss":
                    px[x + PAD, y] = pal[base[y][x]] + (255,)
    return img


if __name__ == "__main__":
    for k, (title, fn) in enumerate(WEAPONS):
        compose("warrior", fn).save(f"{OUT}/w_{k}.png")
        compose("sage", fn, hair=0xC46A3A, accent=0x3E5C8A).save(f"{OUT}/w_sage_{k}.png")
    for k, o in enumerate(["mage", "warrior", "archer", "assassin", "coder", "baller"]):
        compose(o).save(f"{OUT}/o_{k}.png")
    print("ok")
