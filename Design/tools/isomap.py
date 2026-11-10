"""Генератор изометрической pixel-карты дня для макетов Questlyn (SVG-ассеты)."""
import json
import sys

HERO = [
    '...HHHH...', '..HHHHHH..', '..HSSSSH..', '..SESSES..',
    '..SSSSSS..', '...SSSS...', '..AAAAAA..', '.CCAAAACC.',
    '.CCCCCCCC.', '.SCCBBCCS.', '..CCBBCC..', '..CDCCDC..',
    '..PPPPPP..', '..PP..PP..', '..PP..PP..', '.KKK..KKK.',
]
PAL_HERO = dict(H='#3B2A20', S='#E8B892', E='#1F2A44', C='#2F6B4F', D='#24533D', B='#7A4A22', P='#3E4A63', K='#2A2320', A='#C9772A')
PAL_GUESTS = [
    dict(H='#C46A3A', S='#F0C4A0', E='#1F2A44', C='#3B5BDB', D='#2C45A8', B='#1F2A44', P='#4A5784', K='#2A2320', A='#E8ECF7'),
    dict(H='#1F1A16', S='#C98E68', E='#1F2A44', C='#8E4FB5', D='#6F3A8E', B='#1F2A44', P='#3E4A63', K='#2A2320', A='#F2B35B'),
    dict(H='#E0C27A', S='#F2D0B0', E='#1F2A44', C='#B8651B', D='#9A5214', B='#3B2A20', P='#5B6478', K='#2A2320', A='#2F6B4F'),
]

EVENTS = [  # (начало, конец в минутах, название, участники)
    (9 * 60, 9 * 60 + 15, 'Стендап', 2),
    (11 * 60, 12 * 60 + 30, 'Встреча с заказчиком', 2),
    (13 * 60, 13 * 60 + 30, 'Обед с Аней', 1),
    (15 * 60, 17 * 60, 'Работа над отчётом', 0),
    (16 * 60, 16 * 60 + 45, 'Созвон с командой', 3),
    (19 * 60, 20 * 60, 'Тренировка', 0),
]
QUESTS = [(10 * 60 + 30, True), (18 * 60, False)]  # (время начала, выполнен)
MOODS = [(8 * 60 + 10, '#2F6B4F'), (12 * 60 + 45, '#8E9AAF'), (14 * 60, '#E2A04A')]
NOW = 14 * 60 + 20


def h(n):
    n = (n ^ 61) ^ (n >> 16)
    n = (n * 9) & 0xFFFFFFFF
    n ^= n >> 4
    n = (n * 0x27D4EB2D) & 0xFFFFFFFF
    return (n ^ (n >> 15)) / 0xFFFFFFFF


def poly(pts, fill):
    return '<polygon points="%s" fill="%s"/>' % (' '.join('%.1f,%.1f' % p for p in pts), fill)


def build(W, H, t0, t1, hw, px, sky_h):
    hh = hw / 2
    x_of = lambda t: (t - t0) / (t1 - t0) * W
    rows = int((H - sky_h) / hh) + 3
    jr = rows // 2  # ряд дороги
    ground_y0 = sky_h
    cy_of = lambda j: ground_y0 + j * hh
    cx_of = lambda i, j: i * 2 * hw + (hw if j % 2 else 0)
    i_of = lambda x, j: round((x - (hw if j % 2 else 0)) / (2 * hw))

    flat, objs = [], []
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" shape-rendering="crispEdges">' % (W, H, W, H)]
    out.append('<rect width="%d" height="%d" fill="#E9E0CC"/>' % (W, H))
    # солнце (погода «ясно» — последняя метка настроения)
    sx = x_of(NOW)
    s = hw * 1.2
    out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#E2A04A"/>' % (sx - s / 2, sky_h * 0.25, s, s))

    occupied = set()
    # кластеры событий: пересечение или разрыв < 30 минут
    evs = sorted(EVENTS)
    clusters = []
    for e in evs:
        if clusters and e[0] < clusters[-1]['end']:
            c = clusters[-1]
            c['end'] = max(c['end'], e[1]); c['items'].append(e)
        else:
            clusters.append({'start': e[0], 'end': e[1], 'items': [e]})

    labels = []
    behind = [(-2, 0), (-2, 1), (-3, 0), (-2, -1), (-4, 0), (-3, 1), (-3, -1), (-4, 1), (-4, -1), (-5, 0)]
    front = [(2, 0), (2, 1), (3, 0), (2, -1), (3, 1), (4, 0)]
    gi = 0
    for ci, c in enumerate(clusters):
        mid = (c['start'] + c['end']) / 2
        if not (t0 <= mid <= t1):
            continue
        x = x_of(mid)
        dur = sum(e[1] - e[0] for e in c['items'])
        city = any(e[1] - e[0] > 30 for e in c['items'])
        k = len(c['items'])
        n = 2 if not city else min(10, 3 + dur // 30 + 2 * (k - 1))
        spots = (behind + front)[:n] if city else [(-2, 0), (2, 0)]
        for si, (dj, di) in enumerate(spots):
            j = jr + dj
            i = i_of(x, j) + di
            occupied.add((i, j))
            cx, cy = cx_of(i, j), cy_of(j)
            if city:
                Hb = hw * (1.0 + 2.2 * h(ci * 31 + si * 7 + 3)) * (1 + 0.3 * (k - 1))
                tall = Hb > hw * 2.2
                cols = ('#8A94B8', '#55638A', '#3E4A63') if tall else ('#EFE7D7', '#D6CBB3', '#B9AA86')
                objs.append((cy, cx, ('cube', cx, cy, Hb, cols)))
            else:
                objs.append((cy, cx, ('house', cx, cy, hw * 0.8)))
        guests = sum(e[3] for e in c['items'])
        for g in range(min(guests, 3)):
            gx = x + (g - (min(guests, 3) - 1) / 2) * 8 * px
            objs.append((cy_of(jr - 1) + 0.1, gx, ('sprite', gx, cy_of(jr - 1) + hh * 0.4, PAL_GUESTS[(gi) % 3])))
            gi += 1
        labels.append({'name': ' + '.join(e[2] for e in c['items']), 'x': round(x), 'start': c['start'], 'end': c['end'], 'city': city, 'guests': guests, 'k': k})

    # деревья (поздняя осень)
    for j in range(rows):
        if abs(j - jr) <= 3:
            continue
        for i in range(-1, int(W / (2 * hw)) + 2):
            if (i, j) in occupied:
                continue
            r = h(i * 1009 + j * 917)
            if r < 0.055:
                cx, cy = cx_of(i, j), cy_of(j)
                crown = ('#D98B3A', '#C2742A', '#A85F20') if r < 0.035 else ('#9AA155', '#7F8746', '#6A7139')
                objs.append((cy, cx, ('tree', cx, cy, crown)))

    # земля и дорога
    for j in range(rows):
        for i in range(-1, int(W / (2 * hw)) + 2):
            cx, cy = cx_of(i, j), cy_of(j)
            d = [(cx, cy - hh), (cx + hw, cy), (cx, cy + hh), (cx - hw, cy)]
            if j in (jr - 1, jr, jr + 1):
                past = cx <= x_of(NOW)
                col = ('#7E786A' if (i + j) % 2 else '#736D60') if past else ('#ABA698' if (i + j) % 2 else '#A29D8F')
            else:
                r = h(i * 131 + j * 71)
                col = '#C9B680' if r < 0.45 else ('#C2AE77' if r < 0.85 else '#B7A26C')
            flat.append(poly(d, col))
    out += flat

    # метки настроения
    for (t, col) in MOODS:
        if t0 <= t <= t1:
            mx = x_of(t)
            my = cy_of(jr - 1) + hh
            objs.append((my, mx, ('flag', mx, my, col)))

    qpos = []
    for (t, done) in QUESTS:
        if t0 <= t <= t1:
            qx = x_of(t)
            qy = cy_of(jr + 2) + hh
            objs.append((qy, qx, ('quest', qx, qy, done)))
            qpos.append(round(qx))

    # герой
    hx = x_of(NOW)
    if t0 <= NOW <= t1:
        objs.append((cy_of(jr + 1) + 0.2, hx, ('sprite', hx, cy_of(jr + 1) + hh * 0.6, PAL_HERO)))
        objs.append((cy_of(jr + 1) + 0.3, hx, ('marker', hx, cy_of(jr + 1) + hh * 0.6 - 16 * px - 3 * px)))

    objs.sort(key=lambda o: (o[0], o[1]))
    for _, _, o in objs:
        kind = o[0]
        if kind == 'cube':
            _, cx, cy, Hb, (ct, cl, cr) = o
            w = hw * 0.72; q = w / 2; Hb = Hb * 0.75
            out.append(poly([(cx - w, cy - Hb), (cx, cy + q - Hb), (cx, cy + q), (cx - w, cy)], cl))
            out.append(poly([(cx, cy + q - Hb), (cx + w, cy - Hb), (cx + w, cy), (cx, cy + q)], cr))
            out.append(poly([(cx, cy - q - Hb), (cx + w, cy - Hb), (cx, cy + q - Hb), (cx - w, cy - Hb)], ct))
            wy = cy - Hb + q + w * 0.5
            while wy < cy - w * 0.2:
                out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#F2B35B"/>' % (cx + w * 0.35, wy, max(1, w * 0.18), max(1, w * 0.25)))
                wy += w * 0.7
        elif kind == 'house':
            _, cx, cy, Hb = o
            w = hw * 0.6; q = w / 2; Hb = hw * 0.45
            out.append(poly([(cx - w, cy - Hb), (cx, cy + q - Hb), (cx, cy + q), (cx - w, cy)], '#E8DCC2'))
            out.append(poly([(cx, cy + q - Hb), (cx + w, cy - Hb), (cx + w, cy), (cx, cy + q)], '#CDBE9F'))
            ap = (cx, cy - Hb - w * 0.9)
            out.append(poly([(cx - w, cy - Hb), (cx, cy + q - Hb), ap], '#B8651B'))
            out.append(poly([(cx, cy + q - Hb), (cx + w, cy - Hb), ap], '#9A5214'))
        elif kind == 'tree':
            _, cx, cy, (ct, cl, cr) = o
            tw = hw * 0.5
            Hb = hw * 0.9
            base = cy - hw * 0.5
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#6B4F33"/>' % (cx - tw * 0.2, base, tw * 0.4, hw * 0.6))
            th = tw / 2
            out.append(poly([(cx - tw, base - Hb), (cx, base + th - Hb), (cx, base + th), (cx - tw, base)], cl))
            out.append(poly([(cx, base + th - Hb), (cx + tw, base - Hb), (cx + tw, base), (cx, base + th)], cr))
            out.append(poly([(cx, base - th - Hb), (cx + tw, base - Hb), (cx, base + th - Hb), (cx - tw, base - Hb)], ct))
        elif kind == 'flag':
            _, mx, my, col = o
            ph = hw * 2.2
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#3B2A20"/>' % (mx, my - ph, max(1, hw * 0.15), ph))
            out.append(poly([(mx + hw * 0.15, my - ph), (mx + hw * 1.1, my - ph + hw * 0.4), (mx + hw * 0.15, my - ph + hw * 0.8)], col))
        elif kind == 'quest':
            _, qx, qy, done = o
            ph = hw * 1.6; sw = hw * 1.3
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#3B2A20"/>' % (qx - hw * 0.08, qy - ph, max(1, hw * 0.16), ph))
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>' % (qx - sw / 2, qy - ph - sw * 0.8, sw, sw * 0.8, '#2F6B4F' if done else '#1F2A44'))
            if done:
                u = sw / 8
                for (a, b) in [(2, 3), (3, 4), (4, 3), (5, 2), (6, 1)]:
                    out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#FFFCF6"/>' % (qx - sw / 2 + a * u, qy - ph - sw * 0.8 + b * u * 0.8 + u * 0.6, u, u))
            else:
                u = sw / 8
                out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#E2A04A"/>' % (qx - u / 2, qy - ph - sw * 0.8 + u * 0.8, u, u * 3))
                out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#E2A04A"/>' % (qx - u / 2, qy - ph - sw * 0.8 + u * 4.6, u, u))
        elif kind == 'marker':
            _, mx, my = o
            out.append(poly([(mx - 2.5 * px, my - 2.5 * px), (mx + 2.5 * px, my - 2.5 * px), (mx, my + 0.5 * px)], '#E2A04A'))
        elif kind == 'sprite':
            _, fx, fy, pal = o
            x0, y0 = fx - 5 * px, fy - 16 * px
            for r, row in enumerate(HERO):
                for c, ch in enumerate(row):
                    if ch != '.':
                        out.append('<rect x="%.1f" y="%.1f" width="%s" height="%s" fill="%s"/>' % (x0 + c * px, y0 + r * px, px, px, pal[ch]))

    # освещение по времени суток
    def shade(a, b, col, op):
        a, b = max(a, t0), min(b, t1)
        if a < b:
            out.append('<rect x="%.1f" y="0" width="%.1f" height="%d" fill="%s" fill-opacity="%s"/>' % (x_of(a), x_of(b) - x_of(a), H, col, op))
    shade(0, 6 * 60 + 30, '#1F2A44', 0.38)
    shade(6 * 60 + 30, 8 * 60, '#C9772A', 0.12)
    shade(17 * 60 + 30, 19 * 60, '#C9772A', 0.14)
    shade(19 * 60, 24 * 60, '#1F2A44', 0.38)
    out.append('</svg>')
    return '\n'.join(out), labels, {'jr_y': round(cy_of(jr)), 'now_x': round(x_of(NOW)), 'quests': qpos}


if __name__ == '__main__':
    outdir = sys.argv[1]
    svg, lab, meta = build(358, 150, 0, 1440, 8, 1, 30)
    open(outdir + '/map_mini.svg', 'w').write(svg)
    print('mini', json.dumps(meta), json.dumps(lab, ensure_ascii=False))
    svg, lab, meta = build(390, 380, 7 * 60 + 30, 18 * 60 + 30, 14, 3, 60)
    open(outdir + '/map_big.svg', 'w').write(svg)
    print('big', json.dumps(meta), json.dumps(lab, ensure_ascii=False))
