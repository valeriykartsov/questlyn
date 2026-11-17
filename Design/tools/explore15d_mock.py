#!/usr/bin/env python3
"""Прототип картинок для макетов 15D: торговец с шатром, ночные NPC (плащ, глаза, фонарь), ночная сцена.

    python3 Design/tools/explore15d_mock.py <out_dir>
"""
import importlib.util
import os
import sys
from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
HERE = os.path.dirname(os.path.abspath(__file__))
sys.argv = [sys.argv[0], OUT]
spec = importlib.util.spec_from_file_location("sprites", os.path.join(HERE, "explore15_sprites.py"))
sp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sp)


def merchant():
    """Шатёр в полоску, прилавок с мешками и торговец в шляпе — в масштабе полных персонажей."""
    s = Image.new("RGBA", (84, 76), (0, 0, 0, 0))
    d = ImageDraw.Draw(s)
    d.polygon([(2, 26), (42, 2), (82, 26)], fill=(184, 101, 27, 255))
    for x in range(6, 80, 10):
        d.polygon([(x, 26), (42, 4), (x + 5, 26)], fill=(244, 239, 228, 255))
    d.rectangle((8, 26, 76, 70), fill=(122, 74, 42, 255))
    d.rectangle((8, 56, 76, 61), fill=(217, 164, 65, 255))
    for x in (12, 24, 60):
        d.ellipse((x, 42, x + 11, 56), fill=(201, 165, 122, 255))
        d.line((x + 5, 42, x + 6, 39), fill=(92, 58, 30, 255), width=2)
    hero = sp.person("baller", 0x3B2A20, 0xC98E68, 0x6B4FA3, half=False)
    s.alpha_composite(hero.img, (30, 18))
    d.rectangle((36, 17, 56, 20), fill=(92, 58, 30, 255))
    d.rectangle((40, 11, 52, 17), fill=(92, 58, 30, 255))
    return s


def night(npc_outfit, accent):
    """Ночной NPC: тёмный плащ поверх, светящиеся глаза, фонарь в руке."""
    p = sp.person(npc_outfit, 0x1F1A16, 0xC98E68, accent, half=False)
    px = p.img.load()
    for y in range(p.h):
        for x in range(p.w):
            r, g, b, a = px[x, y]
            if not a:
                continue
            if 24 <= y <= 52 and 8 <= x <= 24:
                px[x, y] = (34, 30, 46, 255) if (x + y) % 5 else (48, 42, 62, 255)
            elif y < 24 and (r + g + b) // 3 < 90:
                px[x, y] = (28, 24, 36, 255)
    for (x, y) in [(13, 17), (18, 17)]:
        px[x, y] = (242, 210, 122, 255)
        px[x + 1, y] = (242, 210, 122, 255)
    out = sp.with_shadow(p)
    d = ImageDraw.Draw(out.img)
    d.line((28, 30, 28, 36), fill=(92, 58, 30, 255))
    d.rectangle((26, 36, 31, 42), fill=(242, 179, 91, 255))
    return out.img


if __name__ == "__main__":
    merchant().save(f"{OUT}/merchant.png")
    for k, (o, a) in enumerate([("coder", 0x3E5C8A), ("archer", 0x8A4B3A), ("warrior", 0x6B4FA3)]):
        night(o, a).save(f"{OUT}/night_{k}.png")
        sp.with_shadow(sp.person(o, 0x3B2A20, 0xE8B892, a, half=False)).img.save(f"{OUT}/day_{k}.png")
    print("ok")
