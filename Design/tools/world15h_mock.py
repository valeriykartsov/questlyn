#!/usr/bin/env python3
"""15H: столица, большие города с безопасной территорией, мирные NPC и монстры, легенды (17.11.2026, на review).

    python3 Design/tools/world15h_mock.py <out_dir>
"""
import importlib.util
import math
import os
import sys
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
HERE = os.path.dirname(os.path.abspath(__file__))
argv = sys.argv
sys.argv = [argv[0], OUT]


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


arch = load("arch", "archipelago15h_mock.py")
sp = load("sprites", "explore15_sprites.py")
rgb = arch.rgb

# ---------- Остров главы крупно: города-территории, столица, NPC в городах и на дорогах, монстры в диких местах ----------

arch.W, arch.H = 130, 130
N = 130


def blob(cx, cy, r, k):
    n = arch.value_noise(N, N, 4, k)
    return {(x, y) for y in range(N) for x in range(N)
            if math.hypot(x - cx, y - cy) <= r * (0.8 + 0.4 * n[y][x])}


def line(a, b):
    pts = []
    steps = max(abs(b[0] - a[0]), abs(b[1] - a[1]))
    for t in range(steps + 1):
        pts.append((round(a[0] + (b[0] - a[0]) * t / steps), round(a[1] + (b[1] - a[1]) * t / steps)))
    return pts


def island(new):
    land, owner = arch.world([(65, 62, 52)], 51, threshold=0.14)
    img = arch.render(land, 51, k=4)
    px = img.load()
    k = 4

    def put(x, y, c, s=k):
        for dy in range(s):
            for dx in range(s):
                X, Y = x * k + dx, y * k + dy
                if 0 <= X < img.width and 0 <= Y < img.height:
                    px[X, Y] = c

    if new:
        cities = [(62, 58, 13, "capital"), (42, 86, 8, "city"), (88, 86, 8, "city")]
    else:
        cities = [(62, 58, 4, "city"), (34, 92, 4, "city"), (96, 92, 4, "city"), (40, 40, 3, "city"), (92, 44, 3, "city"),
                  (70, 102, 3, "city"), (52, 74, 3, "city")]
    roads = [((62, 58), (42, 86)), ((62, 58), (88, 86)), ((42, 86), (88, 86)), ((88, 86), (100, 60))]
    if not new:
        roads += [((62, 58), (40, 40)), ((62, 58), (92, 44)), ((70, 102), (96, 92)), ((52, 74), (62, 58))]
    road_cells = set()
    for a, b in roads:
        for (x, y) in line(a, b):
            if land[y][x]:
                road_cells.add((x, y))
                put(x, y, rgb(0xA88A5E))
    territory = set()
    for i, (cx, cy, r, kind) in enumerate(cities):
        if new:
            area = {c for c in blob(cx, cy, r, 60 + i) if land[c[1]][c[0]]}
            territory |= area
            for (x, y) in area:
                put(x, y, rgb(0xD9C9A4) if (x + y) % 5 else rgb(0xCDBB93))
            # Граница территории: забор, у столицы — каменная стена с башнями.
            for (x, y) in area:
                if any((x + dx, y + dy) not in area for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    put(x, y, rgb(0x8E8A84) if kind == "capital" else rgb(0x7A4A2A))
            # Дома кварталами.
            for j in range(int(len(area) / 9)):
                x, y = sorted(area)[int(arch.hash01(j, i, 5) * len(area))]
                if (x, y) in area and math.hypot(x - cx, y - cy) > 2:
                    put(x, y, rgb(0x6B3F22) if j % 3 else rgb(0x3E5C8A))
            if kind == "capital":
                for dx in range(-2, 3):
                    for dy in range(-2, 3):
                        put(cx + dx, cy + dy, rgb(0x5E5A66))
                put(cx, cy - 3, rgb(0xE2A04A))
        else:
            for dx in range(-1, 2):
                for dy in range(-1, 2):
                    put(cx + dx, cy + dy, rgb(0x1F2A44))
    if not new:
        # Круги безопасных зон.
        for (cx, cy, r, _) in cities:
            for a in range(0, 360, 4):
                x = cx * k + 2 + math.cos(math.radians(a)) * 3 * k
                y = cy * k + 2 + math.sin(math.radians(a)) * 3 * k
                if 0 <= x < img.width and 0 <= y < img.height:
                    px[int(x), int(y)] = (255, 252, 246)

    def dot(x, y, c):
        for dx in range(-3, 4):
            for dy in range(-3, 4):
                X, Y = x * k + 2 + dx, y * k + 2 + dy
                if 0 <= X < img.width and 0 <= Y < img.height:
                    px[X, Y] = (255, 252, 246) if max(abs(dx), abs(dy)) == 3 else c

    green, red, purple, grey = (0x2F, 0x6B, 0x4F), (0xA8, 0x43, 0x2F), (0x6A, 0x4E, 0x8C), (0x9A, 0x9A, 0x9A)
    wild = [(x, y) for y in range(N) for x in range(N) if land[y][x] and (x, y) not in territory and (x, y) not in road_cells]
    if new:
        tlist = sorted(territory)
        for j in range(16):
            x, y = tlist[int(arch.hash01(j, 7, 3) * len(tlist))]
            dot(x, y, green)
        rl = sorted(road_cells - territory)
        for j in range(5):
            x, y = rl[int(arch.hash01(j, 8, 3) * len(rl))]
            dot(x, y, green)
        for j in range(7):
            x, y = wild[int(arch.hash01(j, 9, 3) * len(wild))]
            dot(x, y, red)
        for j in range(4):
            x, y = wild[int(arch.hash01(j, 10, 3) * len(wild))]
            dot(x, y, purple)
    else:
        for j in range(18):
            x, y = wild[int(arch.hash01(j, 11, 3) * len(wild))]
            dot(x, y, red if j % 3 else grey)
    return img


# ---------- Монстры: звери зон и «долги» ----------

MON = {
    "wolf": (["....KK......KK..", "...KWWK....KWWK.", "...KWWWKKKKWWWK.", "..KWWWWWWWWWWWK.", "..KWEWWWWWWEWWK.",
              ".KWWWWWWWWWWWWWK", "KWWWWnWWWWWWWWK.", ".KKWWWWWWWWWWK..", "...KWWKKKKWWK...", "...KWK....KWK...", "...KK......KK..."],
             {"K": 0x2A2320, "W": 0xC9CED6, "E": 0xE5482B, "n": 0x2A2320}),
    "bear": (["..KK........KK..", ".KBBK......KBBK.", ".KBBBKKKKKKBBBK.", "KBBBBBBBBBBBBBBK", "KBBEBBBBBBBBEBBK",
              "KBBBBBnnnBBBBBBK", "KBBBBBBBBBBBBBBK", ".KBBBBBBBBBBBBK.", ".KBBKKBBBBKKBBK.", ".KBK..KBBK..KBK.", ".KK....KK....KK."],
             {"K": 0x2A2320, "B": 0x6B4A2E, "E": 0xF2D27A, "n": 0x2A2320}),
    "boar": (["................", "....KKKKKKKK....", "...KbbbbbbbbK...", "..KbbbbbbbbbbK..", ".KbEbbbbbbbbbbK.",
              "KWbbbbbbbbbbbbK.", "KbbbbbbbbbbbbbK.", ".KKbbbbbbbbbbK..", "..KbbKKKKbbK....", "..KbK....KbK....", "..KK......KK...."],
             {"K": 0x2A2320, "b": 0x8A5A34, "E": 0xE5482B, "W": 0xF4EFE4}),
    "jackal": (["..K.........K...", ".KJK.......KJK..", ".KJJKKKKKKKJJK..", "KJJJJJJJJJJJJK..", "KJEJJJJJJJEJJK..",
                ".KJJJJnJJJJJJJK.", "..KJJJJJJJJJJJJK", "..KJJJJJJJJJJK..", "...KJJKKKKJJK...", "...KJK....KJK...", "...KK......KK..."],
               {"K": 0x2A2320, "J": 0xC8AE7E, "E": 0x2A2320, "n": 0x2A2320}),
    "scorpion": (["..........KK....", ".........KSSK...", "..........KSK...", "...KK......KSK..", "..KSSK....KSSK..",
                  ".KSSSSKKKKSSK...", "KSESSSSSSSSK....", "KSSSSSSSSSSK....", ".KSKSKSKSKSK....", "..K.K.K.K.K.....", "................"],
                 {"K": 0x2A2320, "S": 0xB8651B, "E": 0xF2D27A}),
    "deadline": (["......KKKK......", ".....KNNNNK.....", "....KNNNNNNK....", "....KNEENEENK...", "...KNNNNNNNNK...",
                  "...KNNGGGGNNK...", "..KNNNNGGNNNNK..", "..KNNNGGGGNNNK..", ".KNNNNNNNNNNNNK.", ".KNKNKNKNKNKNNK.", "..K.K.K.K.K.KK.."],
                 {"K": 0x15131A, "N": 0x2B2B35, "E": 0xE5482B, "G": 0xD9A441}),
    "sloth": (["................", "................", "......KKKK......", "....KKllllKK....", "...KllllllllK...",
               "..KllEllllEllK..", "..KlllllllllK...", ".KllllllnnllllK.", ".KllllllllllllK.", "KllllllllllllllK", ".KKKKKKKKKKKKKK."],
              {"K": 0x2E4A36, "l": 0x7DB86A, "E": 0x1F2A44, "n": 0x2E4A36}),
    "lure": (["...K........K...", "...KK......KK...", "....KKKKKKKK....", "...KRRRRRRRRK...", "...KRYRRRRYRK...",
              "...KRRRnnRRRK...", "....KRRRRRRK....", "...KRRRRRRRRK.K.", "..KRRKRRRRKRRKRK", "...KK.KRRK.KK.K.", "......KK.KK....."],
             {"K": 0x2A1414, "R": 0xB5473A, "Y": 0xF2D27A, "n": 0x2A1414}),
}


def monster(name, k=4):
    rows, pal = MON[name]
    img = Image.new("RGBA", (16, len(rows)), (0, 0, 0, 0))
    for y, r in enumerate(rows):
        for x, c in enumerate(r):
            if c in pal:
                img.putpixel((x, y), rgb(pal[c]) + (255,))
    return img


def on(img, color, k=4, pad=4):
    bg = Image.new("RGBA", (img.width + pad * 2, img.height + pad * 2), rgb(color) + (255,))
    bg.alpha_composite(img, (pad, pad))
    return bg.resize((bg.width * k, bg.height * k), Image.NEAREST)


# ---------- Легенды: люди топа в полном комплекте одного из 9 образов ----------

LOOKS = ["mage", "warrior", "archer", "assassin", "baller", "coder", "sage", "illusionist", "master"]
HAIRS = [0x3B2A20, 0xC46A3A, 0xE0C080, 0x1A1A1A, 0x3B2A20, 0x6B4A2E, 0xC46A3A, 0x1A1A1A, 0xE0C080]
SKINS = [0xE8B892, 0xD9A27A, 0xF1C9A5, 0xB07850, 0x8A5A3A, 0xE8B892, 0xF1C9A5, 0xD9A27A, 0xB07850]
ACCENTS = [0x3E5C8A, 0xA8432F, 0x2F6B4F, 0x2B2B35, 0xD9772B, 0x2F6B4F, 0x6A4E8C, 0x2F6B4F, 0xD9A441]


def legend(i):
    return sp.person(LOOKS[i], HAIRS[i], SKINS[i], ACCENTS[i], half=False).img


if __name__ == "__main__":
    island(False).save(f"{OUT}/i_old.png")
    island(True).save(f"{OUT}/i_new.png")
    zones = {"wolf": 0xE6ECF0, "bear": 0x7E9A6A, "boar": 0x9DB06A, "jackal": 0xC2B56E, "scorpion": 0xE8CF8E}
    for n, c in zones.items():
        on(monster(n), c).save(f"{OUT}/m_{n}.png")
    for n in ("deadline", "sloth", "lure"):
        on(monster(n), 0x9DB06A).save(f"{OUT}/m_{n}.png")
    for i in range(9):
        on(legend(i), 0x9DB06A, k=2).save(f"{OUT}/l_{i}.png")
    print("world15h ok")
