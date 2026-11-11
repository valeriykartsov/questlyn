# Questlyn — исходники дизайна

Копия холста https://claude.ai/artifact/KFPLKV8L44qP9Wnw3D4TLC (приватный) на 10.11.2026.

- `canvas/` — артборды холста (`*.dc.html`) и раскладка `canvas.json`. Это HTML-макеты формата Design Canvas; страница холста и `support.js` поставляются типом артефакта и здесь не хранятся, поэтому файлы — справочник по вёрстке, текстам и данным экранов, а не самостоятельные страницы.
- `assets/` — изометрическая карта дня (SVG), сгенерирована `tools/isomap.py`.
- `tools/rules_sim.py` — симуляция прогрессии по Rule Set v1.1 (см. `Product/07_FORMULAS.md`, раздел 10). При реализации перенести в тесты правил Domain.

Раскладка холста по рядам пути пользователя (CJM, 11.11.2026): 1 Знакомство (бренд, онбординг, класс и образ героя) · 2 Утро (сон, «Сегодня», миниатюра дня) · 3 План дня (журнал, календарь, создание квестов, Epic, привычек) · 4 Действие (активность, награда, самочувствие) · 5 Мир (карта дня и состояния) · 6 Итоги и рост (герой, навыки, Летопись, HP/MP) · 7 Настройки · 8 Тёмная тема · 9 Интерактивный прототип · Архив (направления A–C, варианты героя A–D, заменённые экраны). Нижний ряд (11.11.2026): `TodaySleep`, `JournalHeader`, `CalendarWeek`, `CalendarMonth`, `SettingsCalendars`, `MapFull` — пункты 9–12, утверждены и реализованы. Ряд этапа 8 (11.11.2026, на review): `SleepEdit`, `SleepEntry`, `MapCallout`, `EpicProfession`, `JournalEpicColor`, `WeeklyUnmark`, `SkillActivity`, `ActivitySkillAuto`, `Splash` — макеты 8.17–8.25. Все утверждённые: образы `HeroOutfits`, `HeroOutfits2`, выбор образа `OnbClassLook`, герой `EHero`, карта `MapStates` и `MapStrip`, Activity `ActivityNew` и `QuestDoneActivity`.

Токены: светлая тема — бумага #F5F0E6, лист #FFFCF6, чернила #1F2A44, янтарь #B8651B, лес #2F6B4F; HP #A8432F, MP #3E6FA3, дебаф INT #6B4FA3. Тёмная — ночь #0F1424, сумерки #182036, звезда #E8ECF7, сияние #4FD1C5, костёр #F2B35B. Шрифты — Literata + Inter.
