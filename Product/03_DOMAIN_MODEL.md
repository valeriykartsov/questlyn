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

## Сущности этапа 2 (набросок)

- **EpicQuest:** id, title, details?, deadline?, completedAt?. Quest.epicId → не больше одного Epic. XP нет, только веха.
- **HabitDefinition:** id, kind (daily / weekly), title, details?, skillId?, weekdays (daily) или targetCount (weekly), timezoneId, isActive.
- **Occurrence:** id, habitId, localDate, completedAt?, undoneAt?. Факт для DIS и начислений привычки.

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
