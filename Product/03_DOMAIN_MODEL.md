# Questlyn — Доменная модель

Статус: **v1 — Рабочая гипотеза** (`classSnapshot` — Подтверждено) (10.11.2026, BACKLOG 0.3). Подробно описаны сущности этапов 1–2. Остальные домены пока только перечислены — см. таблицу внизу.

Правила начислений — только из [07](07_FORMULAS.md) и [08](08_VITALS_AND_CHRONICLE.md). Здесь — структура данных и инварианты.

## Принципы

- **Факты — источник истины:** выполнение квеста (`QuestCompletion`), позже — Occurrence, Activity, сон, вредные привычки.
- **Производные данные** (`ProgressGrant`, уровни, ранг) пересчитываются из фактов по `ruleVersion`. Уровни и ранг в БД не хранятся: это проекция суммы начислений.
- Идентификаторы — UUID. Время — `Date` (UTC) + локальная дата `yyyy-MM-dd` + `timezoneId` там, где важен «день пользователя».
- XP — целое число сотых (`CentiXP`).

## Сущности этапа 1

### Hero

| Поле | Тип | Примечание |
|---|---|---|
| id | UUID | |
| name | String | непустое |
| classTitle | String | название класса задаёт пользователь (02) |
| createdAt | Date | |

Инварианты: в MVP один герой на БД. Внешность (волосы, кожа) — этап 3.

### Class

Не отдельная таблица: класс = название (`Hero.classTitle`) + набор активных профессий героя.

### Profession

| Поле | Тип | Примечание |
|---|---|---|
| id | UUID | |
| heroId | UUID → Hero | |
| title | String | |
| slot | Int 1…3 | 1 — основная профессия (задаёт цвет плаща) |
| catalogItemId, catalogVersion | String? | откуда скопирована; обновление каталога историю не меняет (02) |
| isActive | Bool | при смене профессии старая становится неактивной, её навыки — тоже (02) |
| createdAt | Date | |

`ProfessionAttribute` (professionId, order 1…3, attribute) — основной / вторичный / третичный.

Инварианты:
- Не больше 3 активных профессий; слоты активных профессий уникальны.
- У профессии 1–3 атрибута, без повторов; только STR, END, INT, MNT, CHR — FOC и DIS не выбираются (02).

### Attribute

Перечисление: STR, END, INT, MNT, CHR, FOC, DIS. Состояние атрибута (XP, уровень) — проекция суммы `ProgressGrant`. Пик XP (для спада, этап 3) — тоже проекция.

### Skill

| Поле | Тип | Примечание |
|---|---|---|
| id | UUID | |
| professionId | UUID → Profession | навык принадлежит одной профессии (02) |
| title | String | |
| isActive | Bool | |
| createdAt | Date | |

Mastery и Condition — этап 3.

### Quest

| Поле | Тип | Примечание |
|---|---|---|
| id | UUID | |
| title | String | непустое |
| details | String? | необязательное описание |
| priority | low / medium / high | по умолчанию medium; k = 0,5 / 1 / 1,5 (07) |
| skillId | UUID? → Skill | |
| dueDate | `yyyy-MM-dd`? | локальная дата |
| dueTime | `HH:mm`? | только вместе с dueDate |
| timezoneId | String | timezone на момент создания |
| createdAt | Date | создание не даёт XP |

Epic (epicId) добавится миграцией этапа 2.

### QuestCompletion — факт

| Поле | Тип | Примечание |
|---|---|---|
| id | UUID | это `sourceId` начислений |
| questId | UUID → Quest | |
| completedAt | Date | |
| localDate | `yyyy-MM-dd` | день пользователя |
| timezoneId | String | |
| undoneAt | Date? | отмена; строка не удаляется — нужна Летописи |
| classSnapshot | JSON | атрибуты профессии навыка и Class Multipliers на момент выполнения |

Инварианты:
- У квеста не больше одного активного (не отменённого) выполнения.
- Отмена удаляет начисления этого выполнения (07, раздел 1).
- **`classSnapshot` — Подтверждено** 10.11.2026: без снимка пересчёт по новой `ruleVersion` после смены профессии изменил бы Class Multiplier задним числом.

### ProgressGrant — производное

| Поле | Тип | Примечание |
|---|---|---|
| id | UUID | |
| sourceType | `questCompletion` (позже occurrence, activity) | |
| sourceId | UUID | |
| ruleVersion | String | `1.1` |
| targetKind | attribute / skill | |
| attribute | Attribute? | для targetKind = attribute |
| skillId | UUID? | для targetKind = skill |
| amountCenti | Int | |
| reason | JSON | для объяснимости: роль атрибута, доля, множители |
| createdAt | Date | |

Инварианты: уникально по (sourceType, sourceId, ruleVersion, target) — один факт даёт начисление ровно один раз.

### RankState — проекция

Не хранится. Вычисляется из уровней атрибутов и состава класса: очки S, ранг r, название (07, раздел 8). Меньше 10 очков — «Без ранга».

## Сущности этапа 2 (миграция `v2_habitsAndEpics`)

- **EpicQuest:** id, title, details?, deadline?, completedAt?, createdAt. `Quest.epicId` → не больше одного Epic. XP нет, только веха; завершается вручную, когда все шаги выполнены.
- **HabitDefinition** (`habit`): id, kind (daily / weekly), title, details?, skillId?, weekdays (daily, «1,2,…», 1 — понедельник), targetPerWeek (weekly, 1–14), time?, timezoneId, startDate (локальная дата создания), isActive, createdAt.
- **HabitOccurrence** (`habitOccurrence`) — факт: id (`sourceId` начислений), habitId, localDate, completedAt, timezoneId, undoneAt?, classSnapshot. У daily — не больше одной активной отметки в день (проверка в use case); у weekly — несколько.
- **Начисление DIS** — `ProgressGrant` с `sourceType = weeklyDiscipline` и детерминированным `sourceId` недели; одна неделя — одно начисление, DIS не ниже 0.

## Изменения этапа 3 (миграция `v3_honestProgress`)

- **Hero:** `hair` (dark / red / blond / black), `skin` (light / medium / tan / deep).
- **ProgressGrant:** `localDate` — дата факта (день выполнения, отметки; для DIS — понедельник после недели; для стартового бонуса — день создания героя). По ней считаются спад и форма навыка.
- **ProgressGrant, sourceType `onboardingBonus`:** стартовый бонус, `sourceId` = id героя, по одному начислению на атрибут.
- **SkillMastery** (`skillMastery`) — факт оценки: id, skillId, value 1–5, assessedAt. Текущее мастерство — последняя оценка.
- **AttributeState** (XP после спада, пик, граница, события спада) и **форма навыка** — проекции, не хранятся.
- **Смена профессий:** убранная профессия и её навыки получают `isActive = false`; та же профессия (пункт каталога или своё название) при возврате снова активна вместе с навыками.

## Изменения этапа 3.3 (миграция `v4_activities`)

- **Activity** (`activity`) — факт: id (`sourceId` начислений, `sourceType = activity`), templateId (шаблон из 02), skillId?, durationMinutes (1–1440), creditedMinutes (0–180, с учётом предела дня), localDate, startedAt, timezoneId, questCompletionId? (квест, закрытый активностью), classSnapshot, deletedAt?.
- Квест, закрытый активностью: от квеста — только FOC, навык и атрибуты — от Activity; отмена выполнения удаляет связанную активность.

## Изменения этапа 3.6 (миграция `v5_heroOutfit`)

- **Hero.appearance.outfit** (`hero.outfit`) — образ героя: mage / warrior / archer / assassin / baller / coder. Выбирается на шаге «Класс», меняется в настройках; на начисления не влияет. Уже созданным героям миграция ставит `coder`.
- Цвет акцента одежды не хранится — выводится из основной профессии (слот 1).

## Изменения этапа 4 (миграция `v6_vitals`)

- **SleepSession** (`sleepSession`) — факт сна: id, wakeDate (день пробуждения), durationMinutes, bedtimeDeviationMinutes?, startedAt?, endedAt?, source (`manual` / `health`), timezoneId, createdAt. Ручной ввод за ночь заменяет прежний ручной; записи из Apple Health за период синхронизации заменяются целиком.
- **StepDay** (`stepDay`) — шаги за день из Apple Health: date (ключ), steps, updatedAt.
- **VitalSettings** (`setting`, ключ `vitalSettings`, JSON) — окно сна и норма шагов.
- HP, MP, статусы «Ранен» и «Истощён», итог ночи — проекции (`VitalsCalculator`), не хранятся. Расход MP берётся из активных выполнений обычных квестов: отмена выполнения возвращает MP.

## Изменения этапа 5 (миграция `v7_chronicle`)

- **ChronicleEntry** (`chronicleEntry`) — веха Летописи: id, kind (`attributeLevel` / `rank` / `epicCompleted`), key (`level:INT:14`, `rank:4`, `epic:<id>`), title, occurredAt, localDate, ruleVersion, createdAt, cancelledAt?, recalculatedBy?. Вехи выводятся из начислений (уровни на конец дня со спадом, первое достижение) и сверяются при каждом обновлении: неподтверждённая веха зачёркивается (`cancelledAt`) или, если сменились правила, помечается «пересчитано» (`recalculatedBy`). Старые записи не удаляются.
- Остальная лента не хранится — собирается из фактов (выполнения, отметки, активности, сон, шаги, включая отменённые) и начислений.

## Изменения этапа 6A (миграция `v8_wellbeing`)

- **MoodEntry** (`moodEntry`) — отметка настроения: id, mood (`good` / `neutral` / `bad`), note?, isDaySummary (один на день), at, localDate, timezoneId, deletedAt?. Погода — проекция последней отметки за день.
- **HarmEntry** (`harmEntry`) — отметка блока «Здоровье»: id, kind (`smoking` / `fastFood` / `lateCaffeine` / `custom` / `alcohol`), customHabitId?, title и damagePercent на момент отметки, alcohol? (`little` / `lots`), at, localDate, timezoneId, deletedAt?. Удаление возвращает урон.
- **CustomHarmHabit** (`customHarmHabit`) — своя вредная привычка: id, title, damagePercent (5 / 10 / 20), isActive, createdAt.
- Урон HP, похмелье (действующий INT, MaxMP) и сгоревшая мана — проекции `VitalsCalculator`. События календаря не хранятся — читаются из EventKit.

## Карта дня (этап 6B, без миграции)

- **DayMap** — проекция дня: поселения из пересекающихся событий календаря (одно событие ≤ 30 мин — деревня, иначе город; плотность — число пересечений), маркеры квестов с временем, флажки настроения, «вне карты» (весь день, многодневные, квесты без времени), погода, сезон, час героя (только сегодня). Ничего не хранится.

## Карта недели (этап 7.0, без миграции)

- **WeekMap** — семь `DayMap` с понедельника, привалы сна и час героя в неделе. **SleepCamp** — проекция ночи: из Apple Health — реальный интервал; ручной ввод — длительность, заканчивающаяся в конце окна сна; без данных — окно сна с пометкой. Ничего не хранится.

## Список доменов — Рабочая гипотеза (обновлено 10.11.2026)

| Домен | Сущности | Откуда правила |
|---|---|---|
| Character | Hero (имя, внешность), Class | 02 |
| Profession | Profession, ProfessionCatalogItem (каталог в бандле с версией) | 02 |
| Attribute | Attribute (STR, END, INT, MNT, CHR, FOC, DIS), AttributeState (XP, пик) | 02, 07 |
| Skill | Skill (XP, Mastery, Condition, активен/неактивен) | 02, 07 |
| Quest | Quest (приоритет, описание, дата/время), EpicQuest, HabitDefinition (Daily / Weekly), Occurrence | 02, 07 |
| Activity | Activity, ActivityTemplate | 02, 07 |
| Progression | ProgressGrant (ledger, `sourceId`, `ruleVersion`), RankState | 07 |
| Vitals | SleepSession, HarmType, HarmEntry, StatusEffect (дебаф INT), Vitals — проекция HP/MP | 08 |
| Chronicle | ChronicleEntry (вехи); остальная лента — проекция фактов | 08 |
| Wellbeing | MoodEntry (+ State of Mind) | 02 |
| Calendar | CalendarEvent (EventKit, только чтение), Schedule | 02 |
| World | DayMap — проекция событий, квестов и настроения; Weather | 02 |
| Settings | SleepWindow, StepGoal, Theme | 02, 08 |
| Backup | BackupSnapshot (iCloud Drive), Export | 02 |

Принцип: факты — источник истины; ProgressGrant, Vitals, RankState, DayMap, лента Летописи — производные, пересчитываемые по `ruleVersion`.

## Журнал

- **10.11.2026** — v1: поля, связи и инварианты сущностей этапа 1, набросок этапа 2. `classSnapshot` в выполнении квеста — рабочая гипотеза.
- **10.11.2026** — `classSnapshot` подтверждён; «Без ранга» ниже G.
- **10.11.2026** — этап 2: Epic, привычки, отметки, начисление DIS по неделям.
- **10.11.2026** — этап 3: внешность, дата начисления, стартовый бонус, мастерство; спад и форма — проекции.
- **10.11.2026** — этап 3.6: образ героя (`outfit`).
- **11.11.2026** — этап 4: сон, шаги, настройки здоровья; HP и MP — проекции.
- **11.11.2026** — этап 5: вехи Летописи (`ChronicleEntry`).
- **11.11.2026** — этап 6A: настроение, отметки здоровья, свои вредные привычки.
