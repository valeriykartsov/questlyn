public enum QuestlynError: Error, Equatable, Sendable {
    case emptyName
    case invalidProfessionCount
    case unknownCatalogItem(String)
    case heroAlreadyExists
    case heroNotFound
    case invalidStepGoal
    case emptyCheckIn
    case epicNeedsStep
    case invalidHarmStrength
    case questNotFound
    case skillNotFound
    case professionNotFound
    case alreadyCompleted
    case notCompleted
    case timeWithoutDate
    case lockedWhileCompleted
    case cannotMarkDate
    case notScheduled
    case alreadyMarked
    case noWeekdays
    case invalidTarget
    case habitNotFound
    case epicNotFound
    case epicHasOpenSteps
    case resetNotConfirmed
    case invalidProfessionAttributes
    case unknownActivityType
    case invalidDuration
    case cannotCorrectNight
    case invalidSleepInterval
}

extension QuestlynError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .emptyName: "Название не может быть пустым."
        case .invalidProfessionCount: "Выберите от одной до трёх профессий."
        case .unknownCatalogItem(let id): "Профессии «\(id)» нет в каталоге."
        case .heroAlreadyExists: "Герой уже создан."
        case .heroNotFound: "Герой не найден."
        case .invalidStepGoal: "Норма шагов — от 500 до 30 000."
        case .epicNeedsStep: "В Epic должен остаться хотя бы один шаг. Чтобы убрать его целиком — «Удалить Epic»."
        case .emptyCheckIn: "Отметьте настроение или что-нибудь в блоке «Здоровье»."
        case .invalidHarmStrength: "Сила привычки — 5, 10 или 20% HP."
        case .questNotFound: "Квест не найден."
        case .skillNotFound: "Навык не найден."
        case .professionNotFound: "Профессия не найдена."
        case .alreadyCompleted: "Квест уже выполнен."
        case .notCompleted: "Квест не выполнен."
        case .timeWithoutDate: "Время можно указать только вместе с датой."
        case .lockedWhileCompleted: "Приоритет и навык выполненного квеста не меняются. Сначала отмените выполнение."
        case .cannotMarkDate: "Отметить можно за сегодня и за вчера, недельный квест — за любой день этой недели."
        case .notScheduled: "В этот день квест не запланирован."
        case .alreadyMarked: "Уже отмечено."
        case .noWeekdays: "Выберите хотя бы один день недели."
        case .invalidTarget: "Цель — от 1 до 14 раз в неделю."
        case .habitNotFound: "Привычка не найдена."
        case .epicNotFound: "Epic не найден."
        case .epicHasOpenSteps: "Завершить Epic можно, когда все шаги выполнены."
        case .unknownActivityType: "Такого типа активности нет."
        case .invalidDuration: "Длительность — от 1 минуты до 24 часов."
        case .cannotCorrectNight: "Исправить можно только одну из последних 7 ночей."
        case .invalidSleepInterval: "Подъём должен быть позже отбоя, не позже текущего времени, а сон — не дольше 24 часов."
        case .invalidProfessionAttributes: "У профессии от 1 до 3 разных атрибутов: STR, END, INT, MNT, CHR."
        case .resetNotConfirmed: "Чтобы сбросить данные, введите слово СБРОС."
        }
    }
}
