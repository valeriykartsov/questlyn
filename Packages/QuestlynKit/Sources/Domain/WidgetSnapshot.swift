import Foundation

/// Снимок данных для виджетов (этап 12): приложение пишет его в App Group после каждого обновления,
/// расширение только читает — без БД и блокировок файла. Только показ, отметок с виджета нет.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public struct Quest: Codable, Hashable, Sendable {
        public var title: String
        public var time: String?
        public var minutes: Int?
        public var isGhost: Bool
        public init(title: String, time: String?, minutes: Int?, isGhost: Bool) {
            self.title = title
            self.time = time
            self.minutes = minutes
            self.isGhost = isGhost
        }
    }

    public struct Habit: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var isWeekly: Bool
        public var doneToday: Bool
        public var weekDone: Int
        public var weekPlanned: Int
        /// Отметки по дням недели, пн…вс.
        public var marks: [Bool]
        public init(id: String, title: String, isWeekly: Bool, doneToday: Bool, weekDone: Int, weekPlanned: Int, marks: [Bool]) {
            self.id = id
            self.title = title
            self.isWeekly = isWeekly
            self.doneToday = doneToday
            self.weekDone = weekDone
            self.weekPlanned = weekPlanned
            self.marks = marks
        }
    }

    public struct Sleep: Codable, Hashable, Sendable {
        public var interval: String?
        public var duration: String
        public var quality: Int
        public var hpRestored: Int
        public init(interval: String?, duration: String, quality: Int, hpRestored: Int) {
            self.interval = interval
            self.duration = duration
            self.quality = quality
            self.hpRestored = hpRestored
        }
    }

    public var generatedAt: Date
    public var day: String
    public var heroName: String
    public var rankLetter: String
    public var hp: Int
    public var maxHP: Int
    public var mp: Int
    public var maxMP: Int
    public var mode: String
    public var quests: [Quest]
    public var ghosts: [String]
    public var habits: [Habit]
    public var sleep: Sleep?

    public init(generatedAt: Date, day: String, heroName: String, rankLetter: String, hp: Int, maxHP: Int, mp: Int, maxMP: Int,
                mode: String, quests: [Quest], ghosts: [String], habits: [Habit], sleep: Sleep?) {
        self.generatedAt = generatedAt
        self.day = day
        self.heroName = heroName
        self.rankLetter = rankLetter
        self.hp = hp
        self.maxHP = maxHP
        self.mp = mp
        self.maxMP = maxMP
        self.mode = mode
        self.quests = quests
        self.ghosts = ghosts
        self.habits = habits
        self.sleep = sleep
    }

    public static let appGroup = "group.valeravalera.Questlyn"
    public static let fileName = "widget-snapshot.json"
    public static let mapFileName = "widget-map.png"

    public static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent("Widgets", isDirectory: true)
    }

    public static func load() -> WidgetSnapshot? {
        guard let url = directory?.appendingPathComponent(fileName), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    public func save(map: Data?) throws {
        guard let directory = Self.directory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
        if let map { try map.write(to: directory.appendingPathComponent(Self.mapFileName), options: .atomic) }
    }

    public static let sample = WidgetSnapshot(
        generatedAt: .now, day: "Чт, 12 ноя", heroName: "Арин", rankLetter: "D", hp: 142, maxHP: 175, mp: 232, maxMP: 280, mode: "Фарм",
        quests: [.init(title: "Слайды для ретро", time: "15:00", minutes: 120, isGhost: false), .init(title: "Сдать отчёт", time: "18:00", minutes: 30, isGhost: false)],
        ghosts: ["Оплатить интернет"],
        habits: [.init(id: "sample", title: "Пробежка 3 раза", isWeekly: true, doneToday: false, weekDone: 1, weekPlanned: 3,
                       marks: [true, false, false, false, false, false, false])],
        sleep: .init(interval: "23:40–07:10", duration: "7 ч 30 мин", quality: 85, hpRestored: 43))
}
