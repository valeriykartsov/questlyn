import Foundation
import Application
import Persistence

enum AppEnvironment {
    /// App Group — задел под виджеты и watchOS (02). Должен совпадать с `Questlyn.entitlements`.
    /// Если группа недоступна при подписи, AppDatabase откроет БД в Application Support.
    static let appGroupIdentifier: String? = "group.valeravalera.Questlyn"

    static func live() -> Result<AppModel, Error> {
        Result { AppModel(store: GRDBStore(try AppDatabase.onDisk(appGroupIdentifier: appGroupIdentifier))) }
    }

    static func preview() -> AppModel {
        // swiftlint:disable:next force_try
        AppModel(store: GRDBStore(try! AppDatabase.inMemory()))
    }
}
