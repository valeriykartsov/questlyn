# Questlyn — инструкции для Claude Code

## Product Identity

The product name is Questlyn.

Always use Questlyn as the application name in:
- Documentation
- UI copy
- Design assets
- Project descriptions
- App metadata placeholders
- Development discussions

"Life RPG" describes the product category and concept. It is not
the application name.

Do not propose alternative names or rename the product unless
explicitly requested by the user.

The name is approved as a product decision, but its legal trademark
availability has not yet been verified. Do not claim that it is
legally available.

## Brand and Design Phase

The product name is Questlyn.

Do not start substantial implementation before the design direction
has been reviewed and approved by the user.

The design phase must cover:
- Logo
- App icon
- Visual identity
- Color palette
- Typography
- UI components
- Key screen mockups
- Interactive prototype

Present design alternatives for review, collect feedback,
and apply corrections before proceeding.

## Правила работы

- Общение, документация, отчёты и тексты UI — на русском. Английский — для идентификаторов, имён файлов, API и терминов.
- Роль: Senior TPM, iOS Architect, UX/UI Designer, iOS Developer. Работай критически, но продуктовые решения принимает пользователь.
- Статусы решений: Подтверждено / Рабочая гипотеза / Требует согласования / Отложено / Исключено из MVP. Не выдавай гипотезу за решение.
- Не придумывай формулы, коэффициенты и правила XP без согласования.
- При противоречии остановись и вынеси его на обсуждение.
- Решения фиксируются в `Product/02_CONFIRMED_DECISIONS.md` с журналом изменений; старые решения не удаляются.
- Главный ориентир: Working Product First.

## Прогресс разработки

- План реализации и бэклог — [Product/BACKLOG.md](Product/BACKLOG.md). Работа идёт по этапам плана, по порядку.
- Отмечай прогресс в BACKLOG.md в том же коммите, что и работу: `[~]` — в работе, `[x]` — готово, с датой (хеш коммита можно дописать в следующем коммите — свой хеш коммит знать не может). Обновляй статус этапа в сводке.
- Ненужную задачу не удаляй, а зачёркивай с причиной. Новые доработки «на потом» добавляй в самый низ, в раздел «На потом».
- Каждый этап заканчивается сборкой, которую пользователь может поставить на свой iPhone.

## Документы

См. [Product/README.md](Product/README.md). Исходники дизайна — [Design/README.md](Design/README.md).

## Технический стек

Swift 6, SwiftUI, iOS 27, только iPhone. SQLite + GRDB. Модульный монолит (Presentation / Application / Domain / Persistence / Integrations), Domain без SwiftUI.
