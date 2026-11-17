#!/usr/bin/env python3
"""15H: виды героя и корабля по направлению движения в изометрии (17.11.2026, на review).

Четыре направления изометрии: вправо-вниз и влево-вниз — герой лицом к зрителю (как сейчас, второе — зеркало),
вправо-вверх и влево-вверх — спиной (рисунок «со спины» строится из того же образа: лицо и очки закрыты
волосами, спереди одежды — без пуговиц и рисунка, оружие — за спиной в другой руке).
Корабль: нос вправо-вниз (как сейчас), вправо-вверх (новый рисунок: видна корма), влево — зеркала.

    python3 Design/tools/directions15h_mock.py <out_dir>
"""
import importlib.util
import os
import sys
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
HERE = os.path.dirname(os.path.abspath(__file__))
sys.argv = [sys.argv[0], OUT]
spec = importlib.util.spec_from_file_location("weapons", os.path.join(HERE, "weapons_mock.py"))
wm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wm)
sp = wm.sp


def back_rows(rows):
    """Вид со спины из рядов образа: голова — волосы до затылка, шея — кожа; на груди — без деталей."""
    rows = [list(r) for r in rows]
    for y in range(9, 22):
        xs = [x for x, c in enumerate(rows[y]) if c != "."]
        if not xs:
            continue
        a, b = xs[0], xs[-1]
        for x in range(a + 1, b):
            if rows[y][x] != "K":
                # Затылок: волосы с прядями; ниже уха — темнее.
                rows[y][x] = "h" if (y >= 19 or (x + y) % 7 == 0) else "H"
            elif 14 <= y <= 19:
                rows[y][x] = "H"
    # Спереди одежды: пуговицы, полосы, блики — цветом ткани ряда.
    for y in range(24, 36):
        counts = {}
        for c in rows[y]:
            if c not in ".KSs":
                counts[c] = counts.get(c, 0) + 1
        if not counts:
            continue
        main = max(counts, key=counts.get)
        for x in range(10, 22):
            if rows[y][x] in "WzLlGgQ":
                rows[y][x] = main
    return rows


def paint(rows, outfit, hair=0x3B2A20, skin=0xE8B892, accent=0x2F6B4F, weapon=None, back=False):
    pal = sp.palette(hair, skin, accent, outfit)
    pal.update(sp.EXTRA)
    pad = wm.PAD
    img = Image.new("RGBA", (32 + 2 * pad, 56), (0, 0, 0, 0))
    px = img.load()
    if weapon and back:
        # Со спины оружие — в другой руке (зеркально) и за телом.
        dx, dy = (0, 0) if weapon.__name__ in wm.UNSHIFTED else wm.HAND_SHIFT
        for t in weapon():
            x, y, c = (t[1], t[2], t[3]) if t[0] == "*" else t
            x, y = 31 - (x + dx), y + dy
            if -pad <= x < 32 + pad and 0 <= y < 56:
                px[x + pad, y] = wm.W_COLORS[c] + (255,)
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch != "." and ch in pal:
                px[x + pad, y] = pal[ch] + (255,)
    return img


def hero(outfit, weapon=None, back=False, **kw):
    if not back:
        return wm.compose(outfit, weapon, **kw)
    rows = wm.rows_of(outfit)
    if weapon:
        arms, plain = wm.rows_of("assassin"), wm.rows_of("coder")
        for y in range(24, 52):
            for x in range(32):
                if x < 10 or x > 21:
                    rows[y][x] = arms[y][x] if y <= 37 else plain[y][x]
    return paint(back_rows(rows), outfit, weapon=weapon, back=True, **kw)


def flip(img):
    return img.transpose(Image.FLIP_LEFT_RIGHT)


def walk(img, n=4):
    s = sp.Sprite(img.width, img.height)
    s.img = img.copy()
    s.px = s.img.load()
    return [f.img for f in sp.walk_frames(s, n)]


def ship_ne(frame=0, flag=0xA8432F, sails=2):
    """Корабль носом вправо-вверх: ближе к зрителю — корма с надстройкой, паруса видны с изнанки."""
    S = sp.Sprite(72, 64)
    rgb = sp.rgb
    hull, hull_d, deck, line = rgb(0x6B3F22), rgb(0x4E2E18), rgb(0xA87A4E), rgb(0x3B2414)
    cx, cy = 36, 44
    bow, stern = (cx + 22, cy - 11), (cx - 20, cy + 10)
    near = (4, 2)
    s1, s2 = (stern[0] + near[0], stern[1] + near[1]), (stern[0] - near[0], stern[1] - near[1])
    m1, m2 = (cx + near[0] + 2, cy + near[1] + 1), (cx - near[0] - 2, cy - near[1] - 1)
    deck_poly = [s2, m2, bow, m1, s1]
    drop = 10
    bottom = [(bow[0] - 4, bow[1] + drop - 2), (m1[0] - 1, m1[1] + drop), (s1[0] - 2, s1[1] + drop - 2), (s2[0] + 1, s2[1] + drop)]
    S.poly([s2, s1, m1, bow] + bottom, hull)
    S.poly([(s2[0], s2[1] + drop - 3), (s1[0], s1[1] + drop - 3), (m1[0], m1[1] + drop - 3), (bow[0] - 3, bow[1] + drop - 4)] + bottom, hull_d)
    # Транец — плоская корма к зрителю.
    S.poly([s2, s1, (s1[0], s1[1] + 6), (s2[0], s2[1] + 6)], rgb(0x5E3820))
    for x in range(s2[0] + 2, s1[0] - 1, 3):
        S.set(x, s2[1] + 3 + (x - s2[0]) // 2, rgb(0xF2B35B))
    S.poly(deck_poly, deck)
    from PIL import ImageDraw
    ImageDraw.Draw(S.img).line(deck_poly + [deck_poly[0]], fill=line + (255,))
    S.px = S.img.load()
    for k in range(-4, 5, 2):
        for t in range(0, 40):
            x, y = stern[0] + t + k, stern[1] - t // 2 + k // 2
            c = S.get(x, y)
            if c[3] and c[:3] == deck:
                S.set(x, y, sp.shade(deck, 0.88))
    # Надстройка на корме.
    for y in range(stern[1] - 7, stern[1] + 1):
        for x in range(stern[0] - 4, stern[0] + 6):
            S.set(x, y, rgb(0x7A4A2A) if x < stern[0] + 1 else rgb(0x5E3820))
    masts = [(cx + 7, cy - 4, 30)] + ([(cx - 8, cy + 4, 24)] if sails > 1 else [])
    bulge = [0, 1, 2, 1][frame % 4]
    for mx, my, mh in reversed(masts):
        for y in range(my - mh, my + 1):
            S.set(mx, y, line)
        for y0, y1, w in ((my - mh + 4, my - mh + 13, 9), (my - mh + 15, my - mh + 24, 11)):
            for y in range(y0, min(y1, my - 2) + 1):
                t = (y - y0) / max(1, (y1 - y0))
                b = int(round(bulge * (1 - (2 * t - 1) ** 2)))
                for x in range(mx - w - b, mx + w + 1 - b):
                    yy = y - (x - mx) // 5
                    edge = x in (mx - w - b, mx + w - b) or y == y0
                    c = rgb(0xD5CCB8) if edge else (rgb(0xE9E1CF) if x < mx else rgb(0xDCD3BF))
                    S.set(x, yy, c)
                S.set(mx, y, line)
    mx, my, mh = masts[0]
    for k in range(6):
        for j in range(3):
            S.set(mx + 1 + k, my - mh + j + (1 if (k + frame) % 4 == 0 else 0), rgb(flag))
    for k in range(8):
        S.set(bow[0] + k, bow[1] - 3 - k // 2, line)
    return S.img


def on(color, img, pad=6, k=3):
    bg = Image.new("RGBA", (img.width + pad * 2, img.height + pad * 2), sp.rgb(color) + (255,))
    bg.alpha_composite(img, (pad, pad))
    return bg.resize((bg.width * k, bg.height * k), Image.NEAREST)


def crew(ship, facing_right, rising, companion=True):
    """Герой и спутник на палубе: оба внутри борта; спутник ближе к корме."""
    out = ship.copy()
    hero_img = hero("warrior", wm.katana, back=rising).resize((26, 28), Image.NEAREST)
    mate = hero("archer", back=rising, hair=0xC46A3A, accent=0x8A5A3A).resize((26, 28), Image.NEAREST)
    if not facing_right:
        hero_img, mate = flip(hero_img), flip(mate)
    if rising:
        spots = [(30, 18), (18, 24)]
    else:
        spots = [(26, 18), (16, 12)]
    if companion:
        out.alpha_composite(mate, spots[1])
    out.alpha_composite(hero_img, spots[0])
    return out


if __name__ == "__main__":
    # Герой: 4 направления × кадр стоя, и шаг со спины.
    for name, outfit, weapon in (("warrior", "warrior", wm.katana), ("sage", "sage", None), ("coder", "coder", wm.spear)):
        front, back = hero(outfit, weapon), hero(outfit, weapon, back=True)
        views = [front, flip(front), back, flip(back)]
        for k, v in enumerate(views):
            on(0x9DB06A, v, k=2).save(f"{OUT}/h_{name}_{k}.png")
    for k, f in enumerate(walk(hero("warrior", wm.katana, back=True))):
        on(0x9DB06A, f, k=2).save(f"{OUT}/h_walk_back_{k}.png")
    # Корабль: 4 направления, с героем и спутником на палубе.
    se = sp.ship_iso(1).img
    ne = ship_ne(1)
    ships = [crew(se, True, False), crew(flip(se), False, False), crew(ne, True, True), crew(flip(ne), False, True)]
    for k, s in enumerate(ships):
        on(0x3F6E9C, s, k=2).save(f"{OUT}/s_{k}.png")
    print("directions ok")
