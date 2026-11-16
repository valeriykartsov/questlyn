#!/usr/bin/env python3
"""Прототип картинок для макетов 15B и 15G: сектор навыка (богаче / пустошь), болото вредного,
памятник Epic, монументы полезного, финальная башня, кадры анимации удара.

Берёт мир и рендер из explore15_mock.py и дорисовывает поверх по маске клеток.

    python3 Design/tools/explore15bg_mock.py <out_dir>
"""
import importlib.util
import math
import os
import sys
from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
HERE = os.path.dirname(os.path.abspath(__file__))
sys.argv = [sys.argv[0], OUT]
spec = importlib.util.spec_from_file_location("world", os.path.join(HERE, "explore15_mock.py"))
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)
spec2 = importlib.util.spec_from_file_location("sprites", os.path.join(HERE, "explore15_sprites.py"))
sp = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(sp)

TW, TH = 16, 8


def tile_mask(x0, y0, n):
    """Карта «пиксель → клетка» для кадра render_iso(x0, y0, n)."""
    pad = 30
    cw, ch = n * TW + pad * 2, n * TH + pad * 2
    ox, oy = n * TW // 2 + pad, pad
    mask = {}
    for ly in range(n):
        for lx in range(n):
            cx, cy = ox + (lx - ly) * TW // 2, oy + (lx + ly) * TH // 2 + TH // 2
            for py in range(TH):
                half = (py + 1) * 2 if py < TH // 2 else (TH - py) * 2
                for dx in range(-half, half):
                    mask[(cx + dx, cy - TH // 2 + py)] = (x0 + lx, y0 + ly)
    return mask, (ox, oy)


def center(lx, ly, origin):
    ox, oy = origin
    return ox + (lx - ly) * TW // 2, oy + (lx + ly) * TH // 2 + TH // 2


def find_frame(zone=2, water_max=0.05):
    """Кадр 22×22 в нужной зоне почти без воды и гор, с лесом."""
    best, score = None, -1
    for y0 in range(0, w.H - 22, 3):
        for x0 in range(0, w.W - 22, 3):
            cells = [(x, y) for x in range(x0, x0 + 22) for y in range(y0, y0 + 22)]
            land = [c for c in cells if w.tile_kind(*c) == "ground"]
            if len(land) < len(cells) * (1 - water_max):
                continue
            if sum(1 for c in land if w.zone_of(*c) == zone) < len(land) * 0.9:
                continue
            forest = sum(1 for (x, y) in land if w.forest_n[y][x] > 0.6)
            sc = forest + (100 if any(c in w.road_wear for c in cells) else 0)
            if sc > score:
                best, score = (x0, y0), sc
    return best


def recolor(img, mask, tiles, fn):
    px = img.load()
    for (x, y), t in mask.items():
        if t in tiles and 0 <= x < img.width and 0 <= y < img.height:
            px[x, y] = fn(px[x, y], x, y)


def wasteland(c, x, y):
    r, g, b = c[:3]
    grey = (r + g + b) // 3
    out = (int(grey * 0.9 + 30), int(grey * 0.82 + 18), int(grey * 0.6 + 8))
    if w.hash01(x, y, 91) < 0.04:
        out = (120, 104, 78)
    return out


def swamp(c, x, y):
    h = w.hash01(x, y, 93)
    base = (58, 74, 52) if h < 0.55 else (72, 86, 58)
    if h > 0.93:
        base = (104, 122, 88)
    if w.hash01(x // 3, y // 2, 94) < 0.18:
        base = (46, 62, 70)  # вода в болоте
    return base


def render_sector(kind):
    x0, y0 = FRAME
    img = w.render_iso(x0, y0, 22, new=True).convert("RGB")
    mask, origin = tile_mask(x0, y0, 22)
    d = ImageDraw.Draw(img)
    if kind == "rich":
        px = img.load()
        for (x, y), t in mask.items():
            if w.hash01(x, y, 95) < 0.035 and 0 <= x < img.width:
                px[x, y] = [(232, 180, 200), (242, 210, 122), (255, 252, 246)][int(w.hash01(x, y, 96) * 3)]
        # Флажки навыка.
        for (lx, ly) in [(6, 5), (14, 9), (9, 15)]:
            cx, cy = center(lx, ly, origin)
            d.line([(cx, cy), (cx, cy - 14)], fill=(92, 58, 30))
            d.polygon([(cx + 1, cy - 14), (cx + 9, cy - 11), (cx + 1, cy - 8)], fill=(184, 101, 27))
    elif kind == "waste":
        tiles = {t for t in mask.values()}
        recolor(img, mask, tiles, wasteland)
        # Деревья тоже засохли: перекрасить зелень вне маски тоже.
        px = img.load()
        for yy in range(img.height):
            for xx in range(img.width):
                r, g, b = px[xx, yy]
                if g > r + 12 and g > b and not (b > r + 30):
                    grey = (r + g + b) // 3
                    px[xx, yy] = (grey + 22, grey + 8, grey - 6)
        # Лёгкий туман — только над сушей (вода синее остального).
        px = img.load()
        for yy in range(img.height):
            for xx in range(img.width):
                r, g, b = px[xx, yy]
                if not (b > r + 30):
                    px[xx, yy] = (int(r * 0.82 + 210 * 0.18), int(g * 0.82 + 205 * 0.18), int(b * 0.82 + 195 * 0.18))
    elif kind == "swamp":
        cx0, cy0 = x0 + 11, y0 + 11
        tiles = {t for t in mask.values() if math.hypot((t[0] - cx0) * 1.0, (t[1] - cy0) * 1.3) + (w.hash01(*t, 97) - 0.5) * 3 < 6.5}
        recolor(img, mask, tiles, swamp)
        d = ImageDraw.Draw(img)
        for t in list(tiles)[::5]:
            cx, cy = center(t[0] - x0, t[1] - y0, origin)
            if w.hash01(*t, 98) < 0.5:
                d.line([(cx - 2, cy), (cx - 2, cy - 5)], fill=(96, 110, 60))
                d.line([(cx + 1, cy), (cx + 1, cy - 4)], fill=(120, 130, 70))
                d.point((cx - 2, cy - 6), fill=(110, 70, 40))
    return img


def monument(kind):
    """Монумент полезного: каменный постамент и символ вида."""
    s = sp.Sprite(20, 30)
    dr = ImageDraw.Draw(s.img)
    dr.polygon([(2, 24), (10, 28), (18, 24), (10, 20)], fill=(150, 144, 132, 255))
    dr.rectangle((5, 12, 15, 24), fill=(196, 190, 176, 255))
    dr.rectangle((10, 12, 15, 24), fill=(168, 162, 150, 255))
    dr.rectangle((4, 10, 16, 12), fill=(140, 134, 122, 255))
    sym = {"water": (62, 111, 163), "walk": (47, 107, 79), "stretch": (184, 101, 27), "veg": (168, 67, 47),
           "nap": (107, 79, 163), "custom": (217, 164, 65)}[kind]
    if kind == "water":
        dr.polygon([(10, 1), (14, 7), (10, 9), (6, 7)], fill=sym + (255,))
    elif kind == "walk":
        dr.rectangle((7, 4, 13, 6), fill=sym + (255,)); dr.rectangle((9, 1, 11, 9), fill=sym + (255,))
    elif kind == "stretch":
        dr.ellipse((6, 2, 14, 9), outline=sym + (255,), width=2)
    elif kind == "veg":
        dr.ellipse((6, 3, 14, 10), fill=sym + (255,)); dr.line([(10, 3), (12, 0)], fill=(47, 107, 79, 255), width=2)
    elif kind == "nap":
        dr.ellipse((6, 2, 14, 9), fill=sym + (255,)); dr.ellipse((9, 1, 16, 7), fill=(0, 0, 0, 0))
    else:
        dr.polygon([(10, 1), (12, 5), (16, 5), (13, 8), (14, 11), (10, 9), (6, 11), (7, 8), (4, 5), (8, 5)], fill=sym + (255,))
    s.px = s.img.load()
    return s


def epic_monument(ruin=False):
    s = sp.Sprite(26, 40)
    dr = ImageDraw.Draw(s.img)
    dr.polygon([(1, 34), (13, 39), (25, 34), (13, 29)], fill=(150, 144, 132, 255))
    if ruin:
        dr.rectangle((5, 20, 9, 34), fill=(201, 165, 122, 255))
        dr.rectangle((17, 14, 21, 34), fill=(184, 142, 98, 255))
        dr.rectangle((15, 12, 23, 14), fill=(168, 134, 94, 255))
        dr.rectangle((9, 30, 15, 33), fill=(184, 142, 98, 255))
    else:
        dr.rectangle((8, 8, 18, 33), fill=(214, 208, 196, 255))
        dr.rectangle((13, 8, 18, 33), fill=(186, 180, 168, 255))
        dr.polygon([(8, 8), (13, 2), (18, 8)], fill=(217, 164, 65, 255))
        dr.rectangle((10, 18, 16, 20), fill=(31, 42, 68, 255))
    s.px = s.img.load()
    return s


def boss_tower():
    s = sp.Sprite(34, 64)
    dr = ImageDraw.Draw(s.img)
    dr.rectangle((7, 14, 27, 60), fill=(27, 27, 34, 255))
    dr.rectangle((17, 14, 27, 60), fill=(20, 20, 26, 255))
    for x in range(7, 28, 5):
        dr.rectangle((x, 8, x + 2, 14), fill=(27, 27, 34, 255))
    dr.polygon([(5, 14), (17, 0), (29, 14)], fill=(122, 46, 46, 255))
    dr.rectangle((14, 46, 20, 60), fill=(122, 46, 46, 255))
    for (x, y) in [(11, 24), (21, 24), (16, 34)]:
        dr.rectangle((x, y, x + 2, y + 3), fill=(229, 72, 43, 255))
    s.px = s.img.load()
    return s


def strike_frames():
    """4 кадра анимации удара героя по NPC на траве."""
    hero = sp.with_shadow(sp.person("mage", 0x3B2A20, 0xE8B892, 0x2F6B4F, half=False))
    npc = sp.npc_full if hasattr(sp, "npc_full") else sp.with_shadow(sp.person("archer", 0xC46A3A, 0xF2D0B0, 0x3E5C8A, half=False))
    frames = []
    for f in range(4):
        bg = Image.new("RGBA", (150, 90), (127, 165, 82, 255))
        b = ImageDraw.Draw(bg)
        for i in range(260):
            x, y = int(w.hash01(i, 1, 7) * 150), int(w.hash01(i, 2, 7) * 90)
            b.point((x, y), fill=(118, 153, 75, 255))
        lunge = [0, 16, 8, 0][f]
        bg.alpha_composite(hero.img, (30 + lunge, 18))
        n = npc.img.copy()
        if f == 2:
            # Цель вспыхнула и вздрогнула.
            px = n.load()
            for yy in range(n.height):
                for xx in range(n.width):
                    r, g, bb, a = px[xx, yy]
                    if a and not (r < 60 and g < 60 and bb < 60 and a < 100):
                        px[xx, yy] = (min(255, r + 120), min(255, g + 120), min(255, bb + 120), a)
        bg.alpha_composite(n, (86 + (3 if f == 2 else 0), 18))
        if f == 1:
            # Дуга удара.
            b.arc((66, 12, 110, 60), start=-80, end=50, fill=(255, 252, 246, 255), width=3)
            b.arc((69, 15, 107, 57), start=-70, end=40, fill=(242, 210, 122, 255), width=1)
        if f >= 2:
            b.text((100, 6 - (f - 2) * 6), "-14", fill=(242, 210, 122, 255))
        frames.append(bg)
    return frames


if __name__ == "__main__":
    FRAME = find_frame()
    print("frame", FRAME)
    for kind in ("plain", "rich", "waste", "swamp"):
        img = render_sector(kind) if kind != "plain" else w.render_iso(FRAME[0], FRAME[1], 22, new=True).convert("RGB")
        img.save(f"{OUT}/b_{kind}.png", optimize=True)
    for k in ("water", "walk", "stretch", "veg", "nap", "custom"):
        monument(k).img.save(f"{OUT}/m_{k}.png")
    epic_monument().img.save(f"{OUT}/e_monument.png")
    epic_monument(True).img.save(f"{OUT}/e_ruin.png")
    boss_tower().img.save(f"{OUT}/boss.png")
    for i, f in enumerate(strike_frames()):
        f.save(f"{OUT}/s_{i}.png")
    print("ok")
