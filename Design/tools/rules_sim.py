"""Симуляция прогрессии Questlyn по Rule Set v1.1 (приоритет ×0,5/×1/×1,5, атрибуты без DEX). Запуск: python3 rules_sim.py [long]"""
import math

P = dict(
    QUEST_ATTR=10, QUEST_SKILL=10, QUEST_FOC=5,
    HABIT_ATTR=5, HABIT_SKILL=5,
    ACT_PER_HOUR=10,
    SPLIT={1: [1.0], 2: [0.7, 0.3], 3: [0.5, 0.3, 0.2]},
    MULT_STEP=0.25,
    GRACE=7, DECAY=0.02, FLOOR=0.7,
    DIS_K=0.6,
    COND_GRACE=7, COND_DECAY=3, COND_FLOOR=40, COND_RESTORE=20,
)
ATTRS = ['STR', 'END', 'INT', 'MNT', 'CHR', 'FOC', 'DIS']
PROFS = {'Программист': ['INT', 'MNT', 'CHR'], 'Атлет': ['STR', 'END', 'MNT']}


def level_of(xp):
    # стоимость уровня L→L+1 = 20 + 5L
    L = 0
    while xp >= 20 + 5 * L:
        xp -= 20 + 5 * L
        L += 1
    return L


def mult(a):
    n = sum(a in v for v in PROFS.values())
    return 1 + P['MULT_STEP'] * (n - 1) if n else 1.0


def weight(a):
    if a in ('FOC', 'DIS'):
        return 1.0
    n = sum(a in v for v in PROFS.values())
    return 1.0 if n else 0.5


class Hero:
    def __init__(self):
        self.xp = {a: 0.0 for a in ATTRS}
        self.peak = {a: 0.0 for a in ATTRS}
        self.last = {a: -999 for a in ATTRS}
        self.skill = {}
        self.cond = {}
        self.cond_last = {}

    def add(self, a, v, day):
        self.xp[a] += v
        self.peak[a] = max(self.peak[a], self.xp[a])
        if v > 0:
            self.last[a] = day

    def prof_grant(self, prof, skill, base_attr, base_skill, day):
        attrs = PROFS[prof]
        for a, share in zip(attrs, P['SPLIT'][len(attrs)]):
            self.add(a, base_attr * share * mult(a), day)
        self.skill[skill] = self.skill.get(skill, 0) + base_skill
        c = self.cond.get(skill, 100)
        self.cond[skill] = min(100, c + P['COND_RESTORE'])
        self.cond_last[skill] = day

    def decay(self, day):
        for a in ATTRS:
            if a == 'DIS':
                continue
            if day - self.last[a] > P['GRACE']:
                floor = self.peak[a] * P['FLOOR']
                self.xp[a] = max(floor, self.xp[a] * (1 - P['DECAY']))
        for s in self.cond:
            if day - self.cond_last[s] > P['COND_GRACE']:
                self.cond[s] = max(P['COND_FLOOR'], self.cond[s] - P['COND_DECAY'])

    def score(self):
        return sum(weight(a) * level_of(self.xp[a]) for a in ATTRS)


def dis_delta(daily_pcts, weekly_pcts, scheduled):
    vals = daily_pcts + weekly_pcts
    p = sum(vals) / len(vals)
    v = min(1.5, 0.5 + scheduled / 14)
    return p, max(-30, P['DIS_K'] * (p - 50) * v)


# Сценарий: 4 недели + 2 дня. Неделя 1 — разгон (85%), 2 — обычная (70%), 3 — отпуск без записей, 4 — возвращение (75%).
import sys
LONG = len(sys.argv) > 1
WEEK_RATE = [0.85, 0.70, 0.0, 0.75, 0.75] if not LONG else [0.75] * 52
acc = {}
def take(key, x):
    acc[key] = acc.get(key, 0) + x
    n = int(acc[key] + 1e-9)
    acc[key] -= n
    return n
hero = Hero()
rows = []
week_daily, week_sched = [], 0
week_runs = 0
for day in range(30 if not LONG else 364):
    w = day // 7
    wd = day % 7  # 0 = понедельник
    rate = WEEK_RATE[w]
    weekend = wd >= 5
    # квесты
    prog_q = 0 if weekend else take('prog', 3 * rate)
    life_q = take('life', rate)
    for qi in range(prog_q):
        size = 1.5 if qi == 2 else 1  # из трёх рабочих квестов один средний (M)
        hero.prof_grant('Программист', 'Отчётность', P['QUEST_ATTR'] * size, P['QUEST_SKILL'] * size, day)
        hero.add('FOC', P['QUEST_FOC'] * size, day)
    for _ in range(life_q):
        hero.add('FOC', P['QUEST_FOC'], day)
    if wd == 5 and take('ath', rate) > 0:
        hero.prof_grant('Атлет', 'Бег', P['QUEST_ATTR'], P['QUEST_SKILL'], day)
        hero.add('FOC', P['QUEST_FOC'], day)
    # привычки: зарядка (Атлет/ОФП) ежедневно, английский ежедневно (без профессии), чтение в будни (без профессии)
    sched = 2 + (0 if weekend else 1)
    done = min(sched, take('hab', sched * rate))
    if done >= 1:
        hero.prof_grant('Атлет', 'ОФП', P['HABIT_ATTR'], P['HABIT_SKILL'], day)
    week_daily.append(100 * done / sched)
    week_sched += sched
    # недельный квест «Бег 3 раза»: пробежка = Activity 40 мин, навык «Бег» профессии Атлет
    if wd in (1, 3, 6) and take('run', rate) > 0:
        hero.prof_grant('Атлет', 'Бег', P['ACT_PER_HOUR'] * 40 / 60, P['ACT_PER_HOUR'] * 40 / 60, day)
        week_runs += 1
    hero.decay(day)
    if wd == 6 or (day == 29 and not LONG):
        p, d = dis_delta(week_daily, [100 * min(week_runs, 3) / 3], week_sched)
        hero.xp['DIS'] = max(0, hero.xp['DIS'] + d)
        hero.peak['DIS'] = max(hero.peak['DIS'], hero.xp['DIS'])
        rows.append((day + 1, p, d, {a: level_of(hero.xp[a]) for a in ATTRS}, hero.score(), dict(hero.cond)))
        week_daily, week_sched, week_runs = [], 0, 0

print('Множители:', {a: mult(a) for a in ATTRS[:5]}, 'Веса:', {a: weight(a) for a in ATTRS})
print('| День | Неделя, % | ΔDIS XP | ' + ' | '.join(ATTRS) + ' | Очки ранга | Форма «Бег» |')
print('|' + '---|' * (len(ATTRS) + 5))
for d, p, dd, lv, sc, cond in (rows if not LONG else [r for r in rows if r[0] in (28, 56, 91, 182, 273, 364)]):
    print('| %d | %.0f | %+.0f | %s | %.1f | %d%% |' % (d, p, dd, ' | '.join(str(lv[a]) for a in ATTRS), sc, cond.get('Бег', 100)))
print('XP итог:', {a: round(hero.xp[a]) for a in ATTRS})
print('Навыки XP:', {k: round(v) for k, v in hero.skill.items()})
