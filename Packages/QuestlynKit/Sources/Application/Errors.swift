public enum QuestlynError: Error, Equatable, Sendable {
    case emptyName
    case invalidProfessionCount
    case unknownCatalogItem(String)
    case heroAlreadyExists
    case heroNotFound
    case invalidStepGoal
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
        case .questNotFound: "Квест не найден."
        case .skillNotFound: "Навык не найден."
        case .professionNotFound: "Профессия не найдена."
        case .alreadyCompleted: "Квест уже выполнен."
        case .notCompleted: "Квест не выполнен."
        case .timeWithoutDate: "Время можно указать только вместе с датой."
        case .lockedWhileCompleted: "Приоритет и навык выполненного квеста не меняются. Сначала отмените выполнение."
        case .cannotMarkDate: "Отметить можно только за сегодня и за вчера."
        case .notScheduled: "В этот день квест не запланирован."
        case .alreadyMarked: "Уже отмечено."
        case .noWeekdays: "Выберите хотя бы один день недели."
        case .invalidTarget: "Цель — от 1 до 14 раз в неделю."
        case .habitNotFound: "Привычка не найдена."
        case .epicNotFound: "Epic не найден."
        case .epicHasOpenSteps: "Завершить Epic можно, когда все шаги выполнены."
        case .unknownActivityType: "Такого типа активности нет."
        case .invalidDuration: "Длительность — от 1 минуты до 24 часов."
        case .invalidProfessionAttributes: "У профессии от 1 до 3 разных атрибутов: STR, END, INT, MNT, CHR."
        case .resetNotConfirmed: "Чтобы сбросить данные, введите слово СБРОС."
        }
    }
}
