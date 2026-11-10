import Foundation
import Application
import Persistence

/// Composition root: собирает Persistence → Application для Presentation.
struct AppDependencies {
    let database: AppDatabase
    let todayService: TodayService

    init(database: AppDatabase) {
        self.database = database
        todayService = TodayService(
            heroes: GRDBHeroRepository(database),
            quests: GRDBQuestRepository(database)
        )
    }
}

enum AppEnvironment {
    case ready(AppDependencies)
    case failed(String)

    /// App Group — задел под виджеты и watchOS (02). Должен совпадать с `Questlyn.entitlements`.
    /// Если группа недоступна при подписи, AppDatabase откроет БД в Application Support.
    static let appGroupIdentifier: String? = "group.valeravalera.Questlyn"

    static func live() -> AppEnvironment {
        do {
            return .ready(AppDependencies(database: try AppDatabase.onDisk(appGroupIdentifier: appGroupIdentifier)))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func preview() -> AppDependencies {
        // swiftlint:disable:next force_try
        AppDependencies(database: try! AppDatabase.inMemory())
    }
}
