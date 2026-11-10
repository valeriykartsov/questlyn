# Questlyn — исходники дизайна

Копия холста https://claude.ai/artifact/KFPLKV8L44qP9Wnw3D4TLC (приватный) на 10.11.2026.

- `canvas/` — артборды холста (`*.dc.html`) и раскладка `canvas.json`. Это HTML-макеты формата Design Canvas; страница холста и `support.js` поставляются типом артефакта и здесь не хранятся, поэтому файлы — справочник по вёрстке, текстам и данным экранов, а не самостоятельные страницы.
- `assets/` — изометрическая карта дня (SVG), сгенерирована `tools/isomap.py`.
- `tools/rules_sim.py` — симуляция прогрессии по Rule Set v1.1 (см. `Product/07_FORMULAS.md`, раздел 10). При реализации перенести в тесты правил Domain.

Раскладка холста по рядам: 1 Бренд · 2 Онбординг · 3 День героя · 4 Квесты · 5 Герой · 6 Тёмная тема · 7 Интерактивный прототип · 8 На review (`ActivityNew`, `QuestDoneActivity`, `HeroSprites`, `NinjaHero`, `EHero`, `HeroOutfits`, `OnbClassLook`, `MapStates`, `MapStrip` — добавлены 10.11.2026, ждут решения; `NinjaHero` — персонаж Villager3 из набора Ninja Adventure, CC0, Pixel-Boy и AAA; `EHero` — собственный рисунок в пропорциях LPC, без чужих ассетов; `HeroOutfits` и `OnbClassLook` — образы героя и их выбор на шаге «Класс», утверждены 10.11.2026; `MapStates` — состояния карты дня D-4 (изометрия), `MapStrip` — 2D-миниатюра дня для «Сегодня»; утверждены 11.11.2026) · Архив. Актуальные экраны: `TodayV2`, `HeroV2`, `RewardV2`, `MoodV2` и остальные из рядов 1–7; `Today`, `Hero`, `Reward`, `Mood`, `Main`, `DirA–C` — архив.

Токены: светлая тема — бумага #F5F0E6, лист #FFFCF6, чернила #1F2A44, янтарь #B8651B, лес #2F6B4F; HP #A8432F, MP #3E6FA3, дебаф INT #6B4FA3. Тёмная — ночь #0F1424, сумерки #182036, звезда #E8ECF7, сияние #4FD1C5, костёр #F2B35B. Шрифты — Literata + Inter.
