public enum QuestlynError: Error, Equatable, Sendable {
    case emptyName
    case invalidProfessionCount
    case unknownCatalogItem(String)
    case heroAlreadyExists
    case heroNotFound
    case questNotFound
    case skillNotFound
    case professionNotFound
    case alreadyCompleted
    case notCompleted
    case timeWithoutDate
}

extension QuestlynError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .emptyName: "Название не может быть пустым."
        case .invalidProfessionCount: "Выберите от одной до трёх профессий."
        case .unknownCatalogItem(let id): "Профессии «\(id)» нет в каталоге."
        case .heroAlreadyExists: "Герой уже создан."
        case .heroNotFound: "Герой не найден."
        case .questNotFound: "Квест не найден."
        case .skillNotFound: "Навык не найден."
        case .professionNotFound: "Профессия не найдена."
        case .alreadyCompleted: "Квест уже выполнен."
        case .notCompleted: "Квест не выполнен."
        case .timeWithoutDate: "Время можно указать только вместе с датой."
        }
    }
}
