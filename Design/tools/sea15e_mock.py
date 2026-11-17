#!/usr/bin/env python3
"""15E: море — шторм, течения привычек, обломки и доски, морской змей Epic, встречные корабли, верфь (17.11.2026, на review).

    python3 Design/tools/sea15e_mock.py <out_dir>
"""
import importlib.util
import math
import os
import sys
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
HERE = os.path.dirname(os.path.abspath(__file__))
sys.argv = [sys.argv[0], OUT]


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


arch = load("arch", "archipelago15h_mock.py")
sp = load("sprites", "explore15_sprites.py")
rgb = arch.rgb


def sea_map():
    """Схема моря между тремя главами: шторм, течения, обломки, встречный корабль, змей."""
    arch.W, arch.H = 150, 200
    land, owner = arch.world([(36, 34, 26), (112, 92, 28), (44, 164, 26)], 61, threshold=0.14)
    k = 3
    img = arch.render(land, 61, k=k)
    px = img.load()

    def put(x, y, c, a=1.0):
        for dy in range(k):
            for dx in range(k):
                X, Y = x * k + dx, y * k + dy
                if 0 <= X < img.width and 0 <= Y < img.height:
                    o = px[X, Y]
                    px[X, Y] = tuple(round(o[i] * (1 - a) + c[i] * a) for i in range(3))

    # Шторм у второго острова: тёмная вода, косой дождь.
    cx, cy, r = 80, 70, 13
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            d = math.hypot(x - cx, y - cy)
            if 0 <= x < 150 and 0 <= y < 200 and not land[y][x] and d <= r:
                put(x, y, (24, 32, 52), 0.55 * (1 - d / r / 1.4))
                if (x * 3 + y * 7) % 11 == 0:
                    put(x, y, (200, 214, 230), 0.8)
    # Течения: полосы между островами со стрелками.
    for (a, b) in (((58, 52), (96, 76)), ((98, 116), (62, 146))):
        steps = int(math.hypot(b[0] - a[0], b[1] - a[1]))
        for t in range(steps):
            x = round(a[0] + (b[0] - a[0]) * t / steps)
            y = round(a[1] + (b[1] - a[1]) * t / steps)
            for w in (-1, 0, 1):
                if not land[y][x + w]:
                    put(x + w, y, (127, 180, 214), 0.55)
            if t % 7 == 3:
                put(x, y, (240, 246, 250), 1)
    # Обломки — доски.
    for (x, y) in ((70, 34), (22, 92), (128, 140), (90, 182)):
        for dx in range(-1, 2):
            put(x + dx, y, (138, 90, 52), 1)
        put(x, y - 1, (107, 74, 46), 1)
    # Встречный корабль и змей.
    for dy in range(-1, 2):
        for dx in range(-2, 3):
            put(30 + dx, 120 + dy, (107, 63, 34), 1)
    put(30, 118, (255, 252, 246), 1)
    for t in range(18):
        x = 100 + t
        y = 168 + round(math.sin(t / 2.2) * 3)
        put(x, y, (46, 107, 79), 1)
        put(x, y + 1, (31, 74, 54), 1)
    put(118, 167, (229, 72, 43), 1)
    return img


def wreck():
    s = sp.Sprite(24, 14)
    for (x0, y0, n) in ((2, 7, 14), (6, 9, 14), (4, 4, 12)):
        for i in range(n):
            x, y = x0 + i, y0 + i // 4
            s.set(x, y, rgb(0x8A5A34))
            s.set(x, y + 1, rgb(0x6B4A2E))
    for (x, y) in ((8, 7), (14, 9), (12, 5)):
        s.set(x, y, rgb(0x3B2414))
    # Бочка.
    for y in range(2, 7):
        for x in range(17, 21):
            s.set(x, y, rgb(0xB8651B) if y not in (3, 5) else rgb(0x5E3820))
    return s.img


def serpent(frame=0):
    s = sp.Sprite(48, 28)
    body, dark, belly = rgb(0x2E6B4F), rgb(0x1F4A36), rgb(0x9DB06A)
    for hump in range(3):
        cx = 8 + hump * 13
        lift = (hump + frame) % 2
        for a in range(0, 181, 6):
            for w in range(4):
                x = round(cx + math.cos(math.radians(a)) * (6 - w * 0.4))
                y = round(20 - lift * 2 - math.sin(math.radians(a)) * (8 - w))
                s.set(x, y, body if w < 3 else belly)
        for x in range(cx - 6, cx + 7):
            s.set(x, 21, rgb(0xB8D3E6))
    # Голова с глазом и гребнем.
    for y in range(4, 11):
        for x in range(40, 47):
            if (x - 43) ** 2 + (y - 7) ** 2 <= 11:
                s.set(x, y, body)
    for y in range(9, 21):
        s.set(41, y, body)
        s.set(42, y, dark)
    s.set(44, 6, rgb(0xE5482B))
    for x in range(40, 47, 2):
        s.set(x, 3, rgb(0xA8432F))
    return s.img


def storm():
    s = sp.Sprite(40, 30)
    for (cx, cy, r) in ((12, 9, 7), (22, 7, 8), (30, 10, 6)):
        for y in range(30):
            for x in range(40):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    s.set(x, y, rgb(0x4A5368) if y < cy else rgb(0x3D4354))
    for i in range(14):
        x, y = 6 + i * 2, 16 + (i * 5) % 9
        for t in range(4):
            s.set(x - t, y + t, rgb(0xC9D6E6))
    for (x, y) in ((22, 14), (21, 15), (22, 16), (21, 17), (20, 18)):
        s.set(x, y, rgb(0xF2D27A))
    return s.img


def current():
    s = sp.Sprite(40, 16)
    for t in range(36):
        x, y = 2 + t, 12 - t // 4
        s.set(x, y, rgb(0x7FB4D6))
        s.set(x, y - 1, rgb(0xB8D3E6))
        if t % 9 == 6:
            for k in range(3):
                s.set(x - k, y - 1 - k, rgb(0xF4F8FB))
                s.set(x - k, y + 1 - k // 2, rgb(0xF4F8FB))
    return s.img


def other_ship():
    ship = sp.ship_iso(1, flag=0x2F6B4F, sails=1)
    return sp.mirror(ship).img


def upgraded(sails=False, hull=False, hold=False, mast=False, cannons=False, frame=1):
    """Корабль с улучшениями верфи: каждое видно на рисунке."""
    ship = sp.ship_iso(frame, flag=0xA8432F, sails=2)
    px = ship.img.load()
    W, H = ship.w, ship.h
    white = {(255, 252, 246), (237, 230, 214), (227, 220, 203)}
    hull_c = {(107, 63, 34), (78, 46, 24)}
    for y in range(H):
        for x in range(W):
            c = px[x, y]
            if c[3] == 0:
                continue
            rgb3 = c[:3]
            # Паруса: серые, без полос.
            if sails and rgb3 in white:
                px[x, y] = (168, 173, 181, 255) if rgb3 == (255, 252, 246) else (150, 155, 164, 255) if rgb3 == (237, 230, 214) else (122, 127, 136, 255)
            # Корпус: перекрашен в серо-чёрный (борт и тень борта).
            if hull and rgb3 in hull_c:
                px[x, y] = (58, 58, 64, 255) if rgb3 == (107, 63, 34) else (36, 36, 41, 255)
    if cannons:
        # Пушки: чёрные стволы из портов вдоль борта к зрителю.
        for t in range(5, 40, 7):
            x, y = 10 + t, 40 + t // 2
            for k in range(4):
                ship.set(x - k, y + 1 + k // 2, (24, 24, 30))
                ship.set(x - k, y + 2 + k // 2, (60, 60, 70))
            ship.set(x + 1, y, (229, 72, 43))
    if hold:
        # Трюм: ящики и бочки горкой на палубе.
        for (bx, by, c) in ((17, 38, (184, 101, 27)), (23, 41, (201, 168, 120)), (29, 44, (184, 101, 27)), (20, 34, (201, 168, 120))):
            for dy in range(5):
                for dx in range(5):
                    edge = dx in (0, 4) or dy in (0, 4)
                    ship.set(bx + dx, by + dy, (59, 36, 20) if edge else c)
    if mast:
        # Мачта с трубой: «воронье гнездо» на грот-мачте, подзорная труба блестит.
        mx, top = 40, 15
        for dx in range(-4, 5):
            ship.set(mx + dx, top, (59, 36, 20))
            ship.set(mx + dx, top + 1, (122, 74, 42))
            ship.set(mx + dx, top + 2, (59, 36, 20))
        for k in range(5):
            ship.set(mx + 2 + k, top - 1 - k // 2, (217, 164, 65))
        ship.set(mx + 7, top - 3, (255, 248, 210))
    return ship.img


def on(img, color, k=3, pad=4):
    bg = Image.new("RGBA", (img.width + pad * 2, img.height + pad * 2), rgb(color) + (255,))
    bg.alpha_composite(img, (pad, pad))
    return bg.resize((bg.width * k, bg.height * k), Image.NEAREST)


if __name__ == "__main__":
    sea_map().save(f"{OUT}/sea_map.png")
    on(wreck(), 0x3F6E9C).save(f"{OUT}/sea_wreck.png")
    on(serpent(0), 0x3F6E9C, k=3).save(f"{OUT}/sea_serpent.png")
    on(storm(), 0x2B3E5C).save(f"{OUT}/sea_storm.png")
    on(current(), 0x3F6E9C).save(f"{OUT}/sea_current.png")
    on(other_ship(), 0x3F6E9C, k=2).save(f"{OUT}/sea_other.png")
    variants = [("base", {}), ("sails", {"sails": True}), ("hull", {"hull": True}), ("hold", {"hold": True}),
                ("mast", {"mast": True}), ("cannons", {"cannons": True}),
                ("all", {"sails": True, "hull": True, "hold": True, "mast": True, "cannons": True})]
    for name, opts in variants:
        on(upgraded(**opts), 0x3F6E9C, k=2).save(f"{OUT}/up_{name}.png")
    print("sea ok")


def crew_scene():
    """Корабль с героем и спутником на палубе (экипаж — значками в окне, не фигурами)."""
    ship = upgraded(frame=1)
    out = Image.new("RGBA", (ship.width + 40, ship.height + 20), rgb(0x3F6E9C) + (255,))
    out.alpha_composite(ship, (20, 10))
    wm = load("weapons", "weapons_mock.py")
    hero = wm.compose("warrior", wm.katana).resize((26, 28), Image.NEAREST)
    mate = wm.compose("archer", hair=0xC46A3A, accent=0x8A5A3A).resize((26, 28), Image.NEAREST)
    out.alpha_composite(mate, (20 + 16, 10 + 12))
    out.alpha_composite(hero, (20 + 26, 10 + 18))
    return out


def moored():
    """Корабль у причала стартового острова — пока квест не выполнен: без парусов, у мостков."""
    ship = sp.ship_iso(0, sails=1)
    px = ship.img.load()
    for y in range(ship.h):
        for x in range(ship.w):
            c = px[x, y]
            if c[3] and c[:3] in {(255, 252, 246), (237, 230, 214), (227, 220, 203)}:
                px[x, y] = (0, 0, 0, 0)
    out = Image.new("RGBA", (ship.w + 30, ship.h + 10), rgb(0x3F6E9C) + (255,))
    # Мостки.
    for t in range(26):
        for w in range(4):
            x, y = 2 + t, 50 + t // 2 + w
            out.putpixel((x, y), (138, 90, 52, 255) if t % 4 else (94, 56, 32, 255))
    out.alpha_composite(ship.img, (20, 0))
    return out


if __name__ == "__main__":
    on(crew_scene(), 0x3F6E9C, k=3, pad=0).save(f"{OUT}/crew_scene.png")
    on(moored(), 0x3F6E9C, k=3, pad=0).save(f"{OUT}/ship_moored.png")
    print("crew ok")
