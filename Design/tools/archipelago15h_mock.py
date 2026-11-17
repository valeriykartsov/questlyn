#!/usr/bin/env python3
"""15H: формирование архипелага «Побродить» — варианты вместо «остров = месяц» (17.11.2026, на review).

Карты сверху в стиле макета 15A (общий шум суши на весь мир, заливы, проливы, островки, климат с севера
на юг), точки — объекты острова. Числа на схемах — иллюстрация, не формулы.

    python3 Design/tools/archipelago15h_mock.py <out_dir>
"""
import math
import os
import sys
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
W, H = 150, 240


def hash01(x, y, k=0):
    h = (x * 374761393 + y * 668265263 + k * 2147483647) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return (h ^ (h >> 16)) / 0xFFFFFFFF


def value_noise(w, h, cell, k):
    gw, gh = w // cell + 2, h // cell + 2
    g = [[hash01(i, j, k) for i in range(gw)] for j in range(gh)]
    out = [[0.0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            fx, fy = x / cell, y / cell
            i, j = int(fx), int(fy)
            tx, ty = fx - i, fy - j
            tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
            a = g[j][i] * (1 - tx) + g[j][i + 1] * tx
            b = g[j + 1][i] * (1 - tx) + g[j + 1][i + 1] * tx
            out[y][x] = a * (1 - ty) + b * ty
    return out


def rgb(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255)


def mix(a, b, t):
    return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(3))


ZONE = [(0xE6ECF0, 0x3F5E4A), (0x7E9A6A, 0x2E5A3E), (0x9DB06A, 0x5F8A43), (0xC2B56E, 0x8E8A4E), (0xE8CF8E, 0xB89E62)]


def world(centers, seed, threshold=0.12):
    """Суша — максимум «капель» вокруг центров + шум: берега общие, между островами — проливы."""
    n1, n2 = value_noise(W, H, 18, seed), value_noise(W, H, 7, seed + 1)
    land = [[False] * W for _ in range(H)]
    owner = [[-1] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            best, who = -9, -1
            for k, (cx, cy, r) in enumerate(centers):
                v = 1 - math.hypot(x - cx, (y - cy) * 1.05) / r
                if v > best:
                    best, who = v, k
            v = best + (n1[y][x] - 0.5) * 0.55 + (n2[y][x] - 0.5) * 0.18
            if v > threshold and 2 <= x < W - 2 and 2 <= y < H - 2:
                land[y][x] = True
                owner[y][x] = who
    return land, owner


def render(land, seed, k=2, tint=None, owner=None):
    forest = value_noise(W, H, 6, seed + 4)
    mount = value_noise(W, H, 13, seed + 3)
    jitter = value_noise(W, H, 10, seed + 5)
    # Расстояние до воды / до суши — пена и глубина.
    INF = 10 ** 6
    coast = [[INF] * W for _ in range(H)]
    depth = [[INF] * W for _ in range(H)]
    for grid, pred in ((coast, lambda x, y: not land[y][x]), (depth, lambda x, y: land[y][x])):
        q = [(x, y) for y in range(H) for x in range(W) if pred(x, y)]
        for (x, y) in q:
            grid[y][x] = 0
        i = 0
        while i < len(q):
            x, y = q[i]
            i += 1
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and grid[ny][nx] > grid[y][x] + 1:
                    grid[ny][nx] = grid[y][x] + 1
                    q.append((nx, ny))
    img = Image.new("RGB", (W * k, H * k))
    px = img.load()
    for y in range(H):
        for x in range(W):
            if land[y][x]:
                z = max(0, min(4, int((y / H + (jitter[y][x] - 0.5) * 0.16 + (hash01(x, y, 61) - 0.5) * 0.025) * 5)))
                grass, wood = rgb(ZONE[z][0]), rgb(ZONE[z][1])
                if coast[y][x] <= 1:
                    c = rgb(0xE3CF9A)
                elif coast[y][x] >= 4 and mount[y][x] > 0.72:
                    c = rgb(0xF2F4F6) if mount[y][x] > 0.8 else (rgb(0xA8865E) if z == 4 else rgb(0x7A7368))
                elif forest[y][x] > 0.62 and hash01(x, y, 9) < 0.7:
                    c = wood
                else:
                    c = grass
                if tint is not None and owner is not None and owner[y][x] >= 0:
                    c = mix(c, tint[owner[y][x]], 0.18)
            else:
                d = depth[y][x]
                c = rgb(0x7FB4D6) if d <= 1 else rgb(0x4F86B8) if d <= 4 else rgb(0x3F6E9C) if d <= 10 else rgb(0x335F8A)
            for dy in range(k):
                for dx in range(k):
                    px[x * k + dx, y * k + dy] = c
    return img


def dots(img, points, k=2):
    """Объекты: город — тёмный квадрат 3×3, сундук — оранжевая точка, NPC — серая, башня — чёрная с красным."""
    px = img.load()
    colors = {"city": (0x1F, 0x2A, 0x44), "chest": (0xB8, 0x65, 0x1B), "npc": (0x9A, 0x9A, 0x9A),
              "tower": (0x14, 0x14, 0x18), "fire": (0xE5, 0x48, 0x2B)}
    for (x, y, kind) in points:
        s = 3 if kind in ("city", "tower") else 2
        for dy in range(-s, s + 1):
            for dx in range(-s, s + 1):
                X, Y = x * k + dx, y * k + dy
                if 0 <= X < img.width and 0 <= Y < img.height:
                    edge = abs(dx) == s or abs(dy) == s
                    px[X, Y] = (255, 252, 246) if edge and kind in ("city", "tower") else colors[kind]
        if kind == "tower":
            px[x * k, y * k] = (0xE5, 0x48, 0x2B)


def scatter(land, owner, island, counts, seed, avoid=None):
    """Равномерно по суше острова: города не ближе 9 клеток, остальное — не ближе 4."""
    cells = [(x, y) for y in range(H) for x in range(W) if land[y][x] and owner[y][x] == island]
    out = []
    i = 0
    for kind, n, gap in (("city", counts[0], 10), ("chest", counts[1], 4), ("npc", counts[2], 4)):
        placed = 0
        tries = 0
        while placed < n and tries < 4000 and cells:
            tries += 1
            i += 1
            x, y = cells[int(hash01(i, seed, 7) * len(cells)) % len(cells)]
            if all(math.hypot(x - a, y - b) >= gap for (a, b, _) in out):
                out.append((x, y, kind))
                placed += 1
    return out


def crowded(land, owner, island, counts, seed):
    """Перегруженный остров: города и сундуки вплотную (как последний месяц сейчас)."""
    cells = [(x, y) for y in range(H) for x in range(W) if land[y][x] and owner[y][x] == island]
    out = []
    i = 0
    for kind, n, gap in (("city", counts[0], 5), ("chest", counts[1], 2), ("npc", counts[2], 2)):
        placed, tries = 0, 0
        while placed < n and tries < 6000:
            tries += 1
            i += 1
            x, y = cells[int(hash01(i, seed, 3) * len(cells)) % len(cells)]
            if all(math.hypot(x - a, y - b) >= gap for (a, b, _) in out):
                out.append((x, y, kind))
                placed += 1
    return out


def save(img, name):
    img.save(os.path.join(OUT, name))


if __name__ == "__main__":
    # ---------- Сейчас: остров = месяц, размер по дням, ноябрь короткий, но с данными внутри ----------
    centers = [(42, 40, 30), (104, 118, 44), (46, 200, 26)]
    land, owner = world(centers, 11)
    img = render(land, 11)
    pts = scatter(land, owner, 0, (2, 4, 2), 1) + scatter(land, owner, 1, (4, 6, 4), 2) + crowded(land, owner, 2, (12, 22, 9), 3)
    dots(img, pts)
    save(img, "now.png")

    # ---------- A: главы равного объёма — 4 острова, у каждого одинаковая доля событий, квестов и отметок ----------
    centers = [(40, 38, 33), (108, 92, 34), (44, 150, 34), (106, 206, 33)]
    land, owner = world(centers, 21)
    img = render(land, 21)
    pts = []
    for i in range(4):
        pts += scatter(land, owner, i, (4, 7, 4), 10 + i)
    pts.append((112, 214, "tower"))
    dots(img, pts)
    save(img, "a_chapters.png")

    # ---------- B: острова сфер героя — STR, END, INT, MNT, CHR вокруг цитадели DIS ----------
    centers = [(38, 42, 30), (112, 46, 27), (118, 132, 33), (74, 204, 31), (30, 140, 28), (76, 118, 9)]
    land, owner = world(centers, 31, threshold=0.16)
    tints = [rgb(0xB5473A), rgb(0xD9772B), rgb(0x3E5C8A), rgb(0x6A4E8C), rgb(0xC9A23A), rgb(0x222222)]
    img = render(land, 31, tint=tints, owner=owner)
    pts = scatter(land, owner, 0, (2, 7, 2), 31) + scatter(land, owner, 1, (2, 5, 2), 32) + scatter(land, owner, 2, (3, 9, 2), 33)
    pts += scatter(land, owner, 3, (2, 4, 3), 34) + scatter(land, owner, 4, (5, 3, 8), 35)
    pts.append((76, 118, "tower"))
    dots(img, pts)
    save(img, "b_spheres.png")

    # ---------- C: материк недель + островки особых мест ----------
    centers = [(44, 36, 30), (80, 64, 30), (100, 104, 30), (70, 140, 30), (50, 176, 28), (90, 206, 28),
               (128, 30, 8), (18, 108, 7), (134, 160, 8), (20, 222, 7)]
    land, owner = world(centers, 41, threshold=0.10)
    img = render(land, 41)
    pts = []
    for i in range(6):
        pts += scatter(land, owner, i, (2, 4, 2), 40 + i)
    pts += [(128, 30, "tower"), (134, 160, "tower"), (96, 212, "tower")]
    dots(img, pts)
    save(img, "c_mainland.png")
    print("maps ok")
