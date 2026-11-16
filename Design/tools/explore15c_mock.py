#!/usr/bin/env python3
"""Прототип картинок для макетов 15C: карта сокровищ (обрывки), клад, пещера (вход и тёмная подкарта),
смотровая площадка с подзорной трубой, туман карты мира до и после.

    python3 Design/tools/explore15c_mock.py <out_dir>
"""
import importlib.util
import math
import os
import random
import sys
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
HERE = os.path.dirname(os.path.abspath(__file__))
sys.argv = [sys.argv[0], OUT]
spec = importlib.util.spec_from_file_location("world", os.path.join(HERE, "explore15_mock.py"))
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)
spec2 = importlib.util.spec_from_file_location("sprites", os.path.join(HERE, "explore15_sprites.py"))
sp = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(sp)

R = random.Random(15)


def parchment_map():
    """Карта сокровищ: остров сверху в тонах пергамента, крестик, три обрывка (один не найден)."""
    top = w.topdown(k=1).crop((60, 70, 150, 170))  # средний остров
    top = top.resize((top.width * 3, top.height * 3), Image.NEAREST)
    px = top.load()
    for y in range(top.height):
        for x in range(top.width):
            r, g, b = px[x, y][:3]
            water = b > r + 20
            grey = (r + g + b) // 3
            px[x, y] = (214, 196, 156) if water else (int(150 + grey * 0.3), int(118 + grey * 0.28), int(76 + grey * 0.18))
    d = ImageDraw.Draw(top)
    # Пунктир пути и крестик.
    pts = [(60, 220), (100, 190), (140, 170), (170, 140), (195, 120)]
    for a, b in zip(pts, pts[1:]):
        for t in range(0, 10, 2):
            x = a[0] + (b[0] - a[0]) * t / 10
            y = a[1] + (b[1] - a[1]) * t / 10
            d.ellipse((x - 2, y - 2, x + 2, y + 2), fill=(122, 46, 46))
    d.line((188, 113, 204, 129), fill=(168, 40, 30), width=5)
    d.line((204, 113, 188, 129), fill=(168, 40, 30), width=5)
    # Три обрывка: рваные края, третий не найден.
    pieces = []
    third = top.width // 3
    for k in range(3):
        crop = top.crop((k * third - 4 if k else 0, 0, min(top.width, (k + 1) * third + 4), top.height)).convert("RGBA")
        piece = Image.new("RGBA", crop.size, (0, 0, 0, 0))
        piece.paste(crop, (0, 0))
        mask = Image.new("L", piece.size, 0)
        md = ImageDraw.Draw(mask)
        poly = [(R.randint(0, 6), 0)]
        for y in range(0, top.height, 10):
            poly.append((R.randint(0, 7), y))
        poly.append((R.randint(0, 6), top.height))
        right = [(piece.width - R.randint(0, 7), y) for y in range(top.height, -1, -10)]
        md.polygon(poly + right, fill=255)
        piece.putalpha(mask)
        pieces.append(piece)
    full = Image.new("RGBA", (top.width + 60, top.height + 30), (0, 0, 0, 0))
    for k, piece in enumerate(pieces):
        if k == 2:
            # Не найденный — пунктирный контур.
            outline = Image.new("RGBA", piece.size, (0, 0, 0, 0))
            od = ImageDraw.Draw(outline)
            for y in range(0, piece.height, 8):
                od.line((4, y, 4, y + 4), fill=(122, 104, 78, 255), width=2)
                od.line((piece.width - 5, y, piece.width - 5, y + 4), fill=(122, 104, 78, 255), width=2)
            full.alpha_composite(outline, (k * (third + 18) + 10, 12))
        else:
            shadow = Image.new("RGBA", piece.size, (92, 70, 40, 255))
            shadow.putalpha(piece.split()[3].point(lambda a: 60 if a else 0))
            full.alpha_composite(shadow, (k * (third + 18) + 14, 16))
            full.alpha_composite(piece.rotate(R.uniform(-3, 3), resample=Image.BICUBIC), (k * (third + 18) + 10, 12))
    whole = top.convert("RGBA")
    return full, whole


def treasure_chest(opened=False):
    s = sp.Sprite(22, 18)
    d = ImageDraw.Draw(s.img)
    d.rectangle((2, 7, 19, 16), fill=(122, 74, 42, 255))
    d.rectangle((2, 7, 19, 9), fill=(217, 164, 65, 255))
    d.rectangle((9, 9, 12, 13), fill=(242, 210, 122, 255))
    if opened:
        d.polygon([(2, 7), (6, 0), (23, 0), (19, 7)], fill=(150, 96, 56, 255))
        for i in range(10):
            d.point((5 + i, 6 - i % 3), fill=(255, 226, 120, 255))
    else:
        d.rectangle((2, 3, 19, 7), fill=(150, 96, 56, 255))
        d.rectangle((2, 3, 19, 4), fill=(217, 164, 65, 255))
    s.px = s.img.load()
    return s


def fragment_icon():
    s = sp.Sprite(14, 14)
    d = ImageDraw.Draw(s.img)
    d.polygon([(1, 2), (12, 1), (13, 12), (3, 13)], fill=(214, 196, 156, 255), outline=(150, 118, 76, 255))
    d.line((4, 5, 8, 9), fill=(168, 40, 30, 255), width=2)
    d.line((8, 5, 4, 9), fill=(168, 40, 30, 255), width=2)
    s.px = s.img.load()
    return s


def cave_map(n=24, seed=7):
    """Клеточный автомат: 1 — стена, 0 — пол; связная пещера."""
    r = random.Random(seed)
    g = [[1 if r.random() < 0.45 or x in (0, n - 1) or y in (0, n - 1) else 0 for x in range(n)] for y in range(n)]
    for _ in range(4):
        new = [[0] * n for _ in range(n)]
        for y in range(n):
            for x in range(n):
                walls = sum(g[y + dy][x + dx] if 0 <= x + dx < n and 0 <= y + dy < n else 1 for dx in (-1, 0, 1) for dy in (-1, 0, 1))
                new[y][x] = 1 if walls >= 5 else 0
        g = new
    return g


def render_cave(lit_radius=9.0):
    n = 24
    g = cave_map(n)
    floor = [(x, y) for y in range(n) for x in range(n) if g[y][x] == 0]
    hero = min(floor, key=lambda t: t[0] + t[1])
    chests = [max(floor, key=lambda t: t[0] - t[1]), max(floor, key=lambda t: t[1] - t[0])]
    exit_ = max(floor, key=lambda t: t[0] + t[1])
    pad = 40
    cw, ch = n * 16 + pad * 2, n * 8 + pad * 2 + 20
    img = Image.new("RGB", (cw, ch), (10, 10, 14))
    px = img.load()
    ox, oy = n * 8 + pad, pad + 20

    def center(x, y):
        return ox + (x - y) * 8, oy + (x + y) * 4 + 4

    for d in range(2 * n - 1):
        for x in range(n):
            y = d - x
            if not 0 <= y < n:
                continue
            cx, cy = center(x, y)
            wall = g[y][x] == 1
            e = 10 if wall else 0
            if wall:
                for dy in range(e):
                    for dx in range(-8, 8):
                        edge = 4 - abs(dx) // 2
                        px[cx + dx, cy + edge - dy] = (54, 46, 40) if dx < 0 else (42, 36, 32)
            for py in range(8):
                half = (py + 1) * 2 if py < 4 else (8 - py) * 2
                for dx in range(-half, half):
                    sx, sy = cx + dx, cy - 4 + py - e
                    h = w.hash01(sx, sy, 3)
                    c = ((74, 64, 56) if h < 0.5 else (66, 58, 50)) if wall else ((56, 44, 34) if h < 0.6 else (48, 38, 30))
                    if not wall and w.hash01(sx, sy, 9) < 0.02:
                        c = (110, 150, 170)  # кристаллы
                    px[sx, sy] = c
    d = ImageDraw.Draw(img)
    # Сундуки-тайники и выход.
    for (x, y) in chests:
        cx, cy = center(x, y)
        chest = sp.Sprite(12, 10)
        cd = ImageDraw.Draw(chest.img)
        cd.rectangle((1, 3, 10, 9), fill=(122, 74, 42, 255))
        cd.rectangle((1, 3, 10, 4), fill=(217, 164, 65, 255))
        img.paste(chest.img, (cx - 6, cy - 9), chest.img)
    ex, ey = center(*exit_)
    d.ellipse((ex - 7, ey - 14, ex + 7, ey), fill=(242, 210, 122))
    d.ellipse((ex - 4, ey - 11, ex + 4, ey - 3), fill=(255, 252, 230))
    # Герой с факелом.
    hx, hy = center(*hero)
    hero_s = sp.with_shadow(sp.person("mage", 0x3B2A20, 0xE8B892, 0x2F6B4F))
    img.paste(hero_s.img, (hx - hero_s.w // 2, hy - hero_s.h + 2), hero_s.img)
    # Темнота вне света.
    dark = img.load()
    for y in range(ch):
        for x in range(cw):
            dist = math.hypot((x - hx) / 16, (y - hy + 8) / 8)
            light = max(0.18, 1 - max(0, dist - lit_radius * 0.6) / (lit_radius * 0.6))
            # Выход светится сам.
            light = max(light, max(0.0, 1 - math.hypot((x - ex) / 30, (y - ey) / 18)))
            r, g_, b = dark[x, y]
            warm = 1 + 0.25 * light
            dark[x, y] = (min(255, int(r * light * warm)), min(255, int(g_ * light * (1 + 0.1 * light))), int(b * light))
    return img


def cave_entrance():
    s = sp.Sprite(30, 26)
    d = ImageDraw.Draw(s.img)
    d.polygon([(0, 25), (6, 6), (15, 0), (24, 6), (29, 25)], fill=(122, 115, 104, 255))
    d.polygon([(15, 0), (24, 6), (29, 25), (15, 25)], fill=(98, 92, 83, 255))
    d.ellipse((8, 10, 22, 30), fill=(14, 12, 16, 255))
    d.rectangle((7, 21, 9, 25), fill=(92, 58, 30, 255))
    d.point((8, 20), fill=(242, 179, 91, 255))
    s.px = s.img.load()
    return s


def lookout():
    s = sp.Sprite(24, 30)
    d = ImageDraw.Draw(s.img)
    d.rectangle((3, 14, 5, 29), fill=(92, 58, 30, 255))
    d.rectangle((18, 14, 20, 29), fill=(92, 58, 30, 255))
    d.polygon([(0, 14), (12, 9), (23, 14), (12, 19)], fill=(154, 116, 80, 255))
    d.line((4, 22, 19, 22), fill=(110, 82, 52, 255), width=1)
    # Труба на треноге.
    d.line((12, 9, 9, 3), fill=(60, 60, 70, 255), width=1)
    d.line((12, 9, 15, 3), fill=(60, 60, 70, 255), width=1)
    d.line((8, 2, 19, -1 + 3), fill=(217, 164, 65, 255), width=3)
    s.px = s.img.load()
    return s


def fog_reveal():
    """Карта мира (сверху): туман до и после взгляда в трубу (радиус 30)."""
    base = w.topdown(k=2)
    explored_small = lambda x, y: math.hypot(x - 100, y - 125) < 12
    explored_big = lambda x, y: math.hypot(x - 100, y - 125) < 30 or explored_small(x, y)
    return w.topdown(fog=True, explored=explored_small, k=2), w.topdown(fog=True, explored=explored_big, k=2)


if __name__ == "__main__":
    pieces, whole = parchment_map()
    pieces.save(f"{OUT}/t_pieces.png")
    whole.save(f"{OUT}/t_whole.png")
    treasure_chest().img.save(f"{OUT}/t_chest.png")
    treasure_chest(True).img.save(f"{OUT}/t_chest_open.png")
    fragment_icon().img.save(f"{OUT}/t_fragment.png")
    render_cave().save(f"{OUT}/c_cave.png")
    cave_entrance().img.save(f"{OUT}/c_entrance.png")
    lookout().img.save(f"{OUT}/l_lookout.png")
    before, after = fog_reveal()
    before.crop((100, 150, 300, 350)).save(f"{OUT}/l_before.png")
    after.crop((100, 150, 300, 350)).save(f"{OUT}/l_after.png")
    print("ok")
