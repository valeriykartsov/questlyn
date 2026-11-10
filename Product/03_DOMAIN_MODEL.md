# Questlyn — Доменная модель

Статус: **не составлена** — подробная модель (поля, связи, инварианты) готовится первым шагом реализации, см. [BACKLOG.md](BACKLOG.md), этап 0.

## Список доменов и сущностей — Рабочая гипотеза (обновлено 10.11.2026)

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
