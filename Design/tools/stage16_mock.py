#!/usr/bin/env python3
"""Этап 16: пираты в море и зал Чёрной башни с боссом (18.11.2026, на review).

    python3 Design/tools/stage16_mock.py <out_dir>
"""
import importlib.util
import math
import os
import sys
from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
HERE = os.path.dirname(os.path.abspath(__file__))
sys.argv = [sys.argv[0], OUT]


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


wm = load("weapons", "weapons_mock.py")
sp = wm.sp
rgb = sp.rgb


def boss(final=False):
    """Босс башни: воин в тёмном, катана, чёрная корона с алым камнем; ×1,5 к NPC."""
    img = wm.compose("warrior", wm.katana, hair=0x1A1A1A, skin=0xC9A27A, accent=0x2B2B35)
    px = img.load()
    pad = wm.PAD
    # Корона: зубцы над волосами (ряды 4–9).
    for x in range(10, 23):
        for y in (8, 9):
            px[x + pad, y] = (24, 22, 28, 255)
    for x in (10, 13, 16, 19, 22):
        for y in range(4 + (x % 2), 8):
            px[x + pad, y] = (24, 22, 28, 255)
    px[16 + pad, 7] = (229, 72, 43, 255)
    px[16 + pad, 8] = (229, 72, 43, 255)
    if final:
        aura = Image.new("RGBA", img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(aura)
        d.ellipse((pad - 2, 2, img.width - pad + 2, img.height - 2), fill=(106, 78, 140, 70))
        aura.alpha_composite(img)
        img = aura
    return img


def hall(boss_img, final=False):
    """Зал башни: тёмный каменный пол в изометрии, стены, факелы, герой у входа, босс у дальней стены."""
    W, H = 360, 250
    im = Image.new("RGBA", (W, H), (10, 10, 14, 255))
    d = ImageDraw.Draw(im)
    n, tw, th = 11, 26, 13
    ox, oy = W // 2, 40
    for y in range(n):
        for x in range(n):
            cx = ox + (x - y) * tw // 2
            cy = oy + (x + y) * th // 2
            shade = 52 + ((x * 7 + y * 13) % 3) * 6
            d.polygon([(cx, cy), (cx + tw // 2, cy + th // 2), (cx, cy + th), (cx - tw // 2, cy + th // 2)],
                      fill=(shade, shade - 4, shade + 4, 255), outline=(36, 34, 42, 255))
    # Задние стены.
    left = [(ox, oy), (ox - n * tw // 2, oy + n * th // 2), (ox - n * tw // 2, oy + n * th // 2 - 46), (ox, oy - 46)]
    right = [(ox, oy), (ox + n * tw // 2, oy + n * th // 2), (ox + n * tw // 2, oy + n * th // 2 - 46), (ox, oy - 46)]
    d.polygon(left, fill=(44, 40, 52, 255))
    d.polygon(right, fill=(34, 31, 40, 255))
    for k in range(1, 6):
        d.line([(ox - k * tw, oy + k * th - 30), (ox - k * tw, oy + k * th - 30 + 4)], fill=(60, 56, 68, 255))
    # Факелы со светом.
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    for (tx, ty) in ((ox - 70, oy + 6), (ox + 70, oy + 6), (ox - 130, oy + 36), (ox + 130, oy + 36)):
        for r in range(28, 0, -4):
            g.ellipse((tx - r, ty - r * 0.7, tx + r, ty + r * 0.7), fill=(242, 179, 91, int(10 + (28 - r) * 1.2)))
        d.rectangle((tx - 1, ty - 4, tx + 1, ty + 4), fill=(92, 58, 30, 255))
        d.ellipse((tx - 3, ty - 9, tx + 3, ty - 3), fill=(255, 210, 120, 255))
    im.alpha_composite(glow)
    if final:
        d2 = ImageDraw.Draw(im)
        d2.ellipse((ox - 40, oy + 40, ox + 40, oy + 70), outline=(106, 78, 140, 255), width=2)
    # Босс у дальней стены (×1,5 к герою), герой у входа.
    b = boss_img.resize((int(boss_img.width * 0.9), int(boss_img.height * 0.9)), Image.NEAREST)
    im.alpha_composite(b, (ox - b.width // 2, oy + 10))
    hero = wm.compose("coder", wm.spear).resize((int(52 * 0.6), int(56 * 0.6)), Image.NEAREST)
    im.alpha_composite(hero, (ox - hero.width // 2 - 6, oy + n * th - 52))
    return im


def pirate_ship(frame=1):
    ship = sp.ship_iso(frame, flag=0x15131A, sails=2)
    px = ship.img.load()
    for y in range(ship.h):
        for x in range(ship.w):
            c = px[x, y]
            if c[3] and c[:3] in {(255, 252, 246), (237, 230, 214), (227, 220, 203)}:
                px[x, y] = (40, 38, 44, 255) if c[:3] != (227, 220, 203) else (24, 22, 28, 255)
            elif c[3] and c[:3] in {(107, 63, 34), (78, 46, 24)}:
                px[x, y] = (74, 36, 30, 255) if c[:3] == (107, 63, 34) else (50, 24, 20, 255)
    # Череп на большом парусе.
    for (x, y) in ((40, 26), (41, 26), (42, 26), (39, 27), (43, 27), (40, 28), (42, 28), (41, 29)):
        ship.set(x, y, (244, 239, 228))
    return ship.img


def on(img, color, k=2, pad=6):
    bg = Image.new("RGBA", (img.width + pad * 2, img.height + pad * 2), rgb(color) + (255,))
    bg.alpha_composite(img, (pad, pad))
    return bg.resize((bg.width * k, bg.height * k), Image.NEAREST)


if __name__ == "__main__":
    b, bf = boss(), boss(final=True)
    on(b, 0x2B2B35, k=3).save(f"{OUT}/boss.png")
    on(bf, 0x2B2B35, k=3).save(f"{OUT}/boss_final.png")
    hall(b).resize((720, 500), Image.NEAREST).save(f"{OUT}/hall.png")
    hall(bf, final=True).resize((720, 500), Image.NEAREST).save(f"{OUT}/hall_final.png")
    on(pirate_ship(), 0x3F6E9C, k=3).save(f"{OUT}/pirates.png")
    print("stage16 ok")
