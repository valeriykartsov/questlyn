#!/usr/bin/env python3
"""Прототип мира «Побродить» этапа 15A для макетов: климатические зоны с севера на юг,
горы с перевалами, дороги с износом, автотайлинг переходов, глубина воды, свет ночью.

Рисует картинки «было / стало» в каталог, переданный аргументом. Алгоритмы — эскиз для
Swift-реализации (ExploreRenderer, IslandGenerator), числа — рабочие гипотезы.

    python3 Design/tools/explore15_mock.py <out_dir>
"""
import heapq
import math
import sys
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "."

# ---------- случайность и шум ----------

class Rnd:
    def __init__(self, seed):
        self.s = seed & 0xFFFFFFFFFFFFFFFF or 1

    def next(self):
        self.s ^= (self.s << 13) & 0xFFFFFFFFFFFFFFFF
        self.s ^= self.s >> 7
        self.s ^= (self.s << 17) & 0xFFFFFFFFFFFFFFFF
        return self.s

    def unit(self):
        return (self.next() >> 11) / float(1 << 53)

    def int(self, n):
        return self.next() % n


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

# ---------- мир ----------

W, H = 150, 240
ZONES = ["tundra", "taiga", "temperate", "steppe", "desert"]
ZONE_TITLES = ["Тундра", "Тайга", "Умеренная", "Степь", "Пустыня"]
WATER, LAND, MOUNTAIN, PEAK, ROAD = 0, 1, 2, 3, 4

n1 = value_noise(W, H, 18, 1)
n2 = value_noise(W, H, 7, 2)
ridge_n = value_noise(W, H, 16, 3)
forest_n = value_noise(W, H, 6, 4)
zone_jitter = value_noise(W, H, 10, 5)

centers = [(45, 42, 40), (106, 120, 44), (46, 198, 40)]
terrain = [[WATER] * W for _ in range(H)]
for y in range(H):
    for x in range(W):
        best = 0
        for cx, cy, r in centers:
            d = math.hypot(x - cx, (y - cy) * 1.05) / r
            best = max(best, 1 - d)
        v = best + (n1[y][x] - 0.5) * 0.55 + (n2[y][x] - 0.5) * 0.18
        if v > 0.12:
            terrain[y][x] = LAND


def inside(x, y):
    return 0 <= x < W and 0 <= y < H


def bfs_dist(sources_pred):
    dist = [[10 ** 6] * W for _ in range(H)]
    q = []
    for y in range(H):
        for x in range(W):
            if sources_pred(x, y):
                dist[y][x] = 0
                q.append((x, y))
    i = 0
    while i < len(q):
        x, y = q[i]
        i += 1
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if inside(nx, ny) and dist[ny][nx] > dist[y][x] + 1:
                dist[ny][nx] = dist[y][x] + 1
                q.append((nx, ny))
    return dist

coast = bfs_dist(lambda x, y: terrain[y][x] == WATER)      # для суши — от воды
depth = bfs_dist(lambda x, y: terrain[y][x] != WATER)      # для воды — от суши

# Горы: массивы там, где шум высоты велик, вдали от берега; высота плавно растёт к центру,
# вершины выше 14 px — под снегом.
mountain_n = value_noise(W, H, 13, 3)
hill_n = value_noise(W, H, 4, 6)
ELEV = [[0] * W for _ in range(H)]
for y in range(H):
    for x in range(W):
        if terrain[y][x] == LAND and coast[y][x] >= 4:
            h = mountain_n[y][x] + (ridge_n[y][x] - 0.5) * 0.15 + (hill_n[y][x] - 0.5) * 0.10
            if h > 0.70:
                terrain[y][x] = MOUNTAIN
                ELEV[y][x] = h
inner = bfs_dist(lambda x, y: terrain[y][x] != MOUNTAIN)
for y in range(H):
    for x in range(W):
        if terrain[y][x] == MOUNTAIN:
            raw = (ELEV[y][x] - 0.70) / 0.25 * 24 * min(1.0, inner[y][x] / 3)
            e = max(2, min(24, int(raw / 2) * 2 + 2))
            ELEV[y][x] = e
            if e >= 14:
                terrain[y][x] = PEAK


def zone_of(x, y):
    # Граница зон — волнистая, у самой границы клетки перемешаны (дизеринг).
    t = y / H + (zone_jitter[y][x] - 0.5) * 0.16 + (hash01(x, y, 61) - 0.5) * 0.025
    return max(0, min(4, int(t * 5)))

# Города: по 4–5 на остров, подальше друг от друга и от гор.
rnd = Rnd(1511)
cities = []
for idx, (cx, cy, r) in enumerate(centers):
    tries = 0
    count = 0
    while count < 5 and tries < 4000:
        tries += 1
        x, y = cx + rnd.int(2 * r) - r, cy + rnd.int(2 * r) - r
        if not inside(x, y) or terrain[y][x] != LAND or coast[y][x] < 2:
            continue
        if any(math.hypot(x - a, y - b) < 17 for a, b, _ in cities):
            continue
        if any(terrain[y + dy][x + dx] in (MOUNTAIN, PEAK) for dx in range(-3, 4) for dy in range(-3, 4) if inside(x + dx, y + dy)):
            continue
        cities.append((x, y, idx))
        count += 1

# Дороги: A* по суше, горы дорогие (перевал прорубается), вода закрыта.
def astar(a, b):
    sx, sy = a
    tx, ty = b
    openq = [(0, 0, sx, sy)]
    came = {(sx, sy): None}
    g = {(sx, sy): 0}
    while openq:
        _, cost, x, y = heapq.heappop(openq)
        if (x, y) == (tx, ty):
            break
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if not inside(nx, ny) or terrain[ny][nx] == WATER:
                continue
            t = terrain[ny][nx]
            step = {LAND: 1.0, ROAD: 0.6, MOUNTAIN: 6.0, PEAK: 40.0}[t]
            ng = g[(x, y)] + step
            if ng < g.get((nx, ny), 1e9):
                g[(nx, ny)] = ng
                came[(nx, ny)] = (x, y)
                heapq.heappush(openq, (ng + abs(nx - tx) + abs(ny - ty), ng, nx, ny))
    path = []
    p = (tx, ty)
    while p and p in came:
        path.append(p)
        p = came[p]
    return path[::-1]

WEAR_LEVELS = [(92, "Мощёная"), (64, "Грунтовая"), (34, "Зарастает"), (12, "Едва видна")]
road_wear = {}   # (x, y) -> индекс износа 0..3
road_list = []
for idx in range(len(centers)):
    group = [c for c in cities if c[2] == idx]
    # Минимальное остовное дерево по расстоянию + одно лишнее ребро.
    edges = sorted(((math.hypot(a[0] - b[0], a[1] - b[1]), i, j) for i, a in enumerate(group) for j, b in enumerate(group) if i < j))
    parent = list(range(len(group)))

    def find(i):
        while parent[i] != i:
            i = parent[i]
        return i
    chosen = []
    for d, i, j in edges:
        if find(i) != find(j):
            parent[find(i)] = find(j)
            chosen.append((i, j))
    for d, i, j in edges:
        if (i, j) not in chosen:
            chosen.append((i, j))
            break
    for k, (i, j) in enumerate(chosen):
        level = (k + idx) % 4
        path = astar(group[i][:2], group[j][:2])
        road_list.append((group[i][:2], group[j][:2], level, path))
        for p in path:
            if p not in road_wear or road_wear[p] > level:
                road_wear[p] = level

passes = set()
for (x, y), level in road_wear.items():
    if terrain[y][x] in (MOUNTAIN, PEAK):
        passes.add((x, y))

# ---------- палитры ----------

def rgb(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)

ZONE_PAL = {
    "tundra":    dict(g=(0xE6ECF0, 0xDCE3E8), d=0xC5CFD6, tree="snowpine", leaf=(0x2F4A3E, 0x27403A), dens=0.18),
    "taiga":     dict(g=(0x7E9A6A, 0x75915F), d=0x5E7A50, tree="spruce", leaf=(0x2E5A3E, 0x264E36), dens=0.62),
    "temperate": dict(g=(0x7FA552, 0x76994B), d=0x5E8540, tree="oak", leaf=(0x3E6B2E, 0x335C26), dens=0.45),
    "steppe":    dict(g=(0xC2B56E, 0xB8AA62), d=0x9C8E4E, tree="shrub", leaf=(0x7E8A46, 0x6E7A3C), dens=0.10),
    "desert":    dict(g=(0xE8CF8E, 0xDFC383), d=0xCDAE6C, tree="cactus", leaf=(0x5E8A4A, 0x4E7A3E), dens=0.05),
}
SAND = rgb(0xE3CF9A)
ROCK, ROCK_L, ROCK_R = rgb(0x9A9284), rgb(0x7A7368), rgb(0x625C53)
SNOW = rgb(0xF2F4F6)
WATER_OLD = rgb(0x3F6E9C)
WATER_DEEP, WATER_MID, WATER_SHALLOW, FOAM = rgb(0x2B5884), rgb(0x3F6E9C), rgb(0x6A9CC2), rgb(0xE6F0F4)
ROAD_C = [rgb(0xB9AE9A), rgb(0xA88A5E), rgb(0xA88A5E), rgb(0xA88A5E)]


def ground_color(x, y, new):
    z = ZONE_PAL[ZONES[zone_of(x, y)]]
    if not new:
        z = ZONE_PAL["temperate"]
    a, b = rgb(z["g"][0]), rgb(z["g"][1])
    return a if hash01(x, y, 9) < 0.5 else b


def tile_kind(x, y):
    """Тип клетки для рисования: water, sand, ground, mountain, peak."""
    if not inside(x, y):
        return "water"
    t = terrain[y][x]
    if t == WATER:
        return "water"
    if (x, y) in passes:
        return "ground"
    if t == MOUNTAIN:
        return "mountain"
    if t == PEAK:
        return "peak"
    if coast[y][x] <= 1:
        return "sand"
    return "ground"


def base_color(x, y, new):
    k = tile_kind(x, y)
    if k == "water":
        if not new:
            return WATER_OLD
        d = depth[y][x] if inside(x, y) else 9
        return WATER_SHALLOW if d <= 1 else (mix(WATER_SHALLOW, WATER_MID, 0.6) if d == 2 else (WATER_MID if d < 6 else WATER_DEEP))
    if k == "sand":
        return SAND
    if k in ("mountain", "peak"):
        if new and ZONES[zone_of(x, y)] == "desert":
            return rgb(0xC9A57A) if k == "mountain" else rgb(0xB88E62)
        return SNOW if k == "peak" else ROCK
    return ground_color(x, y, new)

# Мелкий шум для травы — пятна, а не шахматка клеток.
_FINE = value_noise(W * 3 + 3, H * 3 + 3, 5, 71)


def fine_noise(wx, wy):
    i, j = int((wx + 0.5) * 3), int((wy + 0.5) * 3)
    i, j = max(0, min(W * 3, i)), max(0, min(H * 3, j))
    return _FINE[j][i]

# ---------- изометрия ----------

TW, TH = 16, 8


def elev(x, y, new):
    k = tile_kind(x, y)
    if not new:
        return 0
    return ELEV[y][x] if k in ("mountain", "peak") else 0


class Canvas:
    def __init__(self, w, h, fill):
        self.img = Image.new("RGB", (w, h), fill)
        self.px = self.img.load()
        self.w, self.h = w, h

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[x, y] = c

    def get(self, x, y):
        return self.px[x, y] if 0 <= x < self.w and 0 <= y < self.h else (0, 0, 0)


def render_iso(x0, y0, n, new, night=False, show_roads=True, wear_override=None, region=None):
    """Изометрия квадрата n×n клеток с началом (x0, y0)."""
    pad = 30
    cw, ch = n * TW + pad * 2, n * TH + pad * 2
    cv = Canvas(cw, ch, WATER_DEEP if new else WATER_OLD)
    ox, oy = n * TW // 2 + pad, pad

    def center(lx, ly):
        return ox + (lx - ly) * TW // 2, oy + (lx + ly) * TH // 2 + TH // 2

    rnd = Rnd(77 + x0 * 13 + y0)
    if new:
        for _ in range(cw * ch // 90):
            cv.set(rnd.int(cw), rnd.int(ch), rgb(0x34628F) if rnd.unit() < 0.7 else rgb(0x5A86B0))
    else:
        for _ in range(cw * ch // 60):
            cv.set(rnd.int(cw), rnd.int(ch), rgb(0x4A7BAA) if rnd.unit() < 0.5 else rgb(0x36628D))
    items = []
    lights = []
    for d in range(2 * n - 1):
        for lx in range(n):
            ly = d - lx
            if not (0 <= ly < n):
                continue
            x, y = x0 + lx, y0 + ly
            kind = tile_kind(x, y)
            cx, cy = center(lx, ly)
            e = elev(x, y, new)
            col = base_color(x, y, new)
            if kind == "water" and not new:
                continue
            on_road = show_roads and (x, y) in road_wear
            wear = wear_override if (on_road and wear_override is not None) else road_wear.get((x, y))
            # Боковые грани поднятых клеток.
            if e:
                for dy in range(e):
                    for dx in range(-TW // 2, TW // 2):
                        side_c = ROCK_L if dx < 0 else ROCK_R
                        edge = TH // 2 - abs(dx) * TH // TW  # нижняя кромка ромба
                        cv.set(cx + dx, cy + edge - dy, shade(side_c, 0.92 + 0.08 * hash01(cx + dx, dy, 3)))
            for py in range(TH):
                half = (py + 1) * 2 if py < TH // 2 else (TH - py) * 2
                for dx in range(-half, half):
                    sx, sy = cx + dx, cy - TH // 2 + py - e
                    c = col
                    if new:
                        # Локальные координаты в клетке: −0,5…0,5.
                        ddx, ddy = dx + 0.5, py - TH / 2 + 0.5
                        fx = (ddx / (TW / 2) + ddy / (TH / 2)) / 2
                        fy = (ddy / (TH / 2) - ddx / (TW / 2)) / 2
                        hsh = hash01(sx, sy, 11)
                        # Автотайлинг: возле края с соседом другого типа — дизеринг в цвет соседа.
                        for (nx, ny, dist) in ((x - 1, y, fx + 0.5), (x + 1, y, 0.5 - fx), (x, y - 1, fy + 0.5), (x, y + 1, 0.5 - fy)):
                            nk = tile_kind(nx, ny)
                            if dist < 0.32 and nk != kind and not (kind == "water" and nk == "water"):
                                t = (0.32 - dist) / 0.32
                                if kind == "water" and nk != "water":
                                    c = mix(c, FOAM, 0.75) if dist < 0.09 and hsh < 0.8 else mix(c, WATER_SHALLOW, t * 0.8)
                                elif nk == "water":
                                    c = mix(c, rgb(0xEFE2BC), 0.6) if dist < 0.08 else c
                                elif nk in ("mountain", "peak") or kind in ("mountain", "peak"):
                                    pass
                                elif hsh < t * 0.55:
                                    c = base_color(nx, ny, new)
                        if kind == "ground":
                            wx, wy = x + fx, y + fy
                            v = fine_noise(wx, wy)
                            zp = ZONE_PAL[ZONES[zone_of(x, y)]]
                            g0, g1 = rgb(zp["g"][0]), rgb(zp["g"][1])
                            c = shade(g0, 1.04) if v + (hsh - 0.5) * 0.12 > 0.62 else (g0 if v > 0.42 else g1)
                            if ZONES[zone_of(x, y)] == "tundra" and (sx // 3 + sy) % 7 == 0 and hash01(sx // 6, sy // 3, 13) < 0.5:
                                c = rgb(0xCFD8DF)
                            if hash01(sx, sy, 5) < 0.08:
                                c = rgb(ZONE_PAL[ZONES[zone_of(x, y)]]["d"])
                        if kind == "water" and hash01(sx, sy, 6) < 0.025:
                            c = mix(c, (255, 255, 255), 0.35)
                        if kind == "sand" and hash01(sx, sy, 7) < 0.06:
                            c = shade(c, 0.92)
                        if kind == "mountain" and hash01(sx, sy, 14) < 0.12:
                            c = shade(c, 0.88)
                        if kind == "peak" and fy > 0.1 and hash01(sx, sy, 8) < 0.5:
                            c = rgb(0xD5DCE2)
                    # Дорога.
                    if on_road and wear is not None:
                        rx, ry = dx / (TW / 2), (py - TH / 2) / (TH / 2)
                        core = abs(rx) + abs(ry) < 0.82
                        if core:
                            hr = hash01(sx, sy, 21)
                            if wear == 0:
                                c = ROAD_C[0] if hr < 0.82 else rgb(0x8E8574)
                                if (sx + sy) % 4 == 0 and hr < 0.5:
                                    c = rgb(0xA79C87)
                            elif wear == 1:
                                c = ROAD_C[1] if hr < 0.9 else rgb(0x8E7450)
                            elif wear == 2:
                                c = ROAD_C[2] if hr < 0.5 else c
                            else:
                                c = ROAD_C[3] if hr < 0.18 else c
                    cv.set(sx, sy, c)
            # Предметы на клетке.
            if kind == "ground" and not on_road:
                z = ZONE_PAL[ZONES[zone_of(x, y)]] if new else ZONE_PAL["temperate"]
                if forest_n[y][x] > 0.6 and hash01(x, y, 31) < (z["dens"] if new else 0.5):
                    items.append((lx + ly, "tree", cx, cy, z, hash01(x, y, 32) < 0.5))
            if kind == "peak" or kind == "mountain":
                pass
        # конец диагонали
    city_set = {(c[0], c[1]) for c in cities}
    for (cxw, cyw, _) in cities:
        lx, ly = cxw - x0, cyw - y0
        for k, (ax, ay) in enumerate([(0, 0), (1, -1), (-1, 1), (1, 1), (-1, -1), (2, 0)]):
            if 0 <= lx + ax < n and 0 <= ly + ay < n:
                hx, hy = center(lx + ax, ly + ay)
                roof = [0xB8651B, 0x8A4B3A, 0x3E5C8A, 0x2F6B4F, 0x6B4FA3][k % 5]
                items.append((lx + ax + ly + ay + 0.5, "house", hx, hy, roof, k))
                if k < 3:
                    lights.append((hx, hy - 4))
    for depth_k, kind, ix, iy, *rest in sorted(items, key=lambda t: t[0]):
        if kind == "tree":
            draw_tree(cv, ix, iy, rest[0], rest[1], new)
        else:
            draw_house(cv, ix, iy, rest[0], 9 + (rest[1] % 3) * 2, night and new)
    if night:
        apply_night(cv, lights if new else [], new)
    return cv.img


def draw_tree(cv, x, y, z, dark, new):
    kind = z["tree"] if new else "oak"
    leaf = rgb(z["leaf"][1] if dark else z["leaf"][0])
    trunk = rgb(0x5C3A1E)
    if kind in ("spruce", "snowpine"):
        for k in range(2):
            cv.set(x, y - k, trunk)
        for dy in range(9):
            half = dy // 2
            for dx in range(-half, half + 1):
                c = leaf
                if kind == "snowpine" and (dy % 3 == 0 or (dx == -half and hash01(x + dx, dy, 41) < 0.5)):
                    c = SNOW
                cv.set(x + dx, y - 10 + dy, c)
        if new:
            for dx in range(-3, 4):
                cv.set(x + dx + 1, y + 1, shade(cv.get(x + dx + 1, y + 1), 0.8))
    elif kind == "shrub":
        for dy in range(3):
            for dx in range(-2 + (dy == 0), 3 - (dy == 0)):
                cv.set(x + dx, y - dy, leaf)
    elif kind == "cactus":
        for dy in range(7):
            cv.set(x, y - dy, leaf)
        for dy in range(3):
            cv.set(x - 2, y - 3 - dy, leaf)
            cv.set(x + 2, y - 2 - dy, leaf)
        cv.set(x - 1, y - 3, leaf)
        cv.set(x + 1, y - 2, leaf)
    else:
        for k in range(3):
            cv.set(x, y - k, trunk)
        for dy in range(5):
            half = dy + 1 if dy < 3 else 5 - dy
            for dx in range(-half, half + 1):
                c = leaf
                if new and dx < 0 and dy < 2:
                    c = mix(leaf, (255, 255, 255), 0.18)
                if new and dx > 0 and dy > 2:
                    c = shade(leaf, 0.85)
                cv.set(x + dx, y - 7 + dy, c)
        if new:
            for dx in range(-2, 4):
                cv.set(x + dx + 1, y + 1, shade(cv.get(x + dx + 1, y + 1), 0.8))


def draw_house(cv, x, y, roof, height, lit):
    roof = rgb(roof)
    for dy in range(height):
        for dx in range(-5, 6):
            cv.set(x + dx, y - dy, rgb(0xE9DCC0) if dx < 0 else rgb(0xCDBE9E))
    for k in range(3):
        cv.set(x - 2, y - k, rgb(0x5C3A1E))
    win = rgb(0xF2B35B) if lit else rgb(0x5C6B7A)
    cv.set(x + 2, y - height + 4, win)
    cv.set(x + 3, y - height + 4, win)
    for dy in range(5):
        half = 6 - dy
        for dx in range(-half, half + 1):
            cv.set(x + dx, y - height - dy, shade(roof, 0.85 if dx > 0 else 1.0))


def apply_night(cv, lights, new):
    tint = (40, 52, 96)
    for y in range(cv.h):
        for x in range(cv.w):
            r, g, b = cv.get(x, y)
            k = 0.42
            nr, ng, nb = int(r * k + tint[0] * 0.25), int(g * k + tint[1] * 0.25), int(b * k + tint[2] * 0.35)
            if new:
                glow = 0.0
                for lx, ly in lights:
                    d = math.hypot(x - lx, (y - ly) * 1.6)
                    if d < 34:
                        glow = max(glow, (1 - d / 34) ** 1.6)
                if glow > 0:
                    # Дизеринг краёв света — пиксельный стиль.
                    if hash01(x, y, 51) < glow * 1.4:
                        nr = int(nr + (r * 0.95 - nr) * glow + 70 * glow)
                        ng = int(ng + (g * 0.85 - ng) * glow + 38 * glow)
                        nb = int(nb + (b * 0.6 - nb) * glow)
            cv.set(x, y, (min(255, nr), min(255, ng), min(255, nb)))


def scale(img, k):
    return img.resize((img.width * k, img.height * k), Image.NEAREST)

# ---------- вид сверху ----------

def topdown(fog=False, hero=None, explored=None, k=2, zones_overlay=False):
    img = Image.new("RGB", (W, H))
    p = img.load()
    for y in range(H):
        for x in range(W):
            kind = tile_kind(x, y)
            if kind == "water":
                d = depth[y][x]
                c = WATER_SHALLOW if d <= 1 else (WATER_MID if d < 6 else WATER_DEEP)
            elif kind == "sand":
                c = SAND
            elif kind == "mountain":
                c = ROCK_L
            elif kind == "peak":
                c = SNOW
            else:
                z = ZONE_PAL[ZONES[zone_of(x, y)]]
                c = rgb(z["g"][0])
                if forest_n[y][x] > 0.6 and hash01(x, y, 31) < z["dens"] * 1.3:
                    c = rgb(z["leaf"][0])
            if (x, y) in road_wear:
                lv = road_wear[(x, y)]
                if lv <= 1 or (lv == 2 and (x + y) % 2 == 0) or (lv == 3 and (x + y) % 4 == 0):
                    c = ROAD_C[lv] if lv == 0 else rgb(0x9A7A4E)
            if fog and explored is not None and not explored(x, y):
                c = mix(c, rgb(0xE9E1D0), 0.86)
                if (x + y) % 6 == 0:
                    c = rgb(0xD8CDB6)
            p[x, y] = c
    img = scale(img, k)
    return img


def save(img, name):
    img.save(f"{OUT}/{name}")
    print(name, img.size)


if __name__ == "__main__":
    # Где зоны и острова — для подписей макетов.
    print("cities", len(cities), "roads", len(road_list), "passes", len(passes))
    save(topdown(k=2), "w_top.png")
    # Обзор карты мира с туманом: открыто — вокруг городов первого острова и часть второго.
    first = [c for c in cities if c[2] == 0] + [c for c in cities if c[2] == 1][:2]

    def explored(x, y):
        return any(math.hypot(x - a, y - b) < 19 for a, b, _ in first)
    save(topdown(fog=True, explored=explored, k=2), "w_fog.png")

    # Кадр для «было / стало»: граница умеренной зоны и степи на втором острове, с горами и дорогой.
    best, score = None, -1
    for (x, y, _) in cities:
        x0c, y0c = max(0, x - 22), max(0, y - 16)
        cells = [(xx, yy) for xx in range(x0c, x0c + 40) for yy in range(y0c, y0c + 40) if inside(xx, yy)]
        water = sum(1 for xx, yy in cells if terrain[yy][xx] == WATER) / len(cells)
        mount = sum(1 for xx, yy in cells if terrain[yy][xx] in (MOUNTAIN, PEAK)) / len(cells)
        zones = len({zone_of(xx, yy) for xx, yy in cells if terrain[yy][xx] != WATER})
        roads = sum(1 for c in cells if c in road_wear)
        if zone_of(x, y) != 2:
            continue
        sc = (1 - abs(water - 0.3) * 4) * 2 + min(mount, 0.08) * 8 + min(zones - 1, 1) * 0.6 + min(roads, 60) / 60
        if sc > score:
            best, score = (x, y), sc
    bx, by = best
    print("pass at", bx, by, ZONES[zone_of(bx, by)])
    x0, y0 = max(0, bx - 22), max(0, by - 16)
    save(scale(render_iso(x0, y0, 40, new=False, show_roads=False), 2), "i_before.png")
    save(scale(render_iso(x0, y0, 40, new=True), 2), "i_after.png")
    save(scale(render_iso(x0, y0, 40, new=False, show_roads=False, night=True), 2), "i_night_before.png")
    save(scale(render_iso(x0, y0, 40, new=True, night=True), 2), "i_night_after.png")

    # Кадры зон: по городу в каждой зоне.
    for zi, z in enumerate(ZONES):
        def purity(c):
            cells = [(xx, yy) for xx in range(c[0] - 11, c[0] + 11) for yy in range(c[1] - 11, c[1] + 11) if inside(xx, yy) and terrain[yy][xx] != WATER]
            return sum(1 for xx, yy in cells if zone_of(xx, yy) == zi) / max(1, len(cells))
        cand = sorted([c for c in cities if purity(c) > 0.5], key=lambda c: -purity(c))
        if not cand:
            # Без города — самая «чистая» точка суши зоны.
            pts = [(x, y, 0) for y in range(0, H, 4) for x in range(0, W, 4) if terrain[y][x] == LAND and zone_of(x, y) == zi]
            cand = sorted(pts, key=lambda c: -purity(c))[:1]
        if not cand:
            continue
        cx, cy, _ = cand[0]
        save(scale(render_iso(cx - 11, cy - 11, 22, new=True), 2), f"z_{z}.png")

    # Износ дорог: один и тот же участок с разным уровнем.
    rx, ry = None, None
    for (frm, to, lv, path) in road_list:
        if len(path) > 26:
            mx, my = path[len(path) // 2]
            if tile_kind(mx, my) == "ground" and zone_of(mx, my) == 2:
                rx, ry = mx, my
                break
    if rx is None:
        rx, ry = road_list[0][3][len(road_list[0][3]) // 2]
    for lv in range(4):
        save(scale(render_iso(rx - 8, ry - 8, 16, new=True, wear_override=lv), 2), f"r_{lv}.png")
