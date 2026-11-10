import Foundation
import GRDB

/// Локальная БД Questlyn (SQLite + GRDB). Схема — `Migrations.swift`.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Migrations.migrator.migrate(writer)
    }

    /// Файл БД на устройстве. App Group — задел под виджеты и watchOS (02).
    /// Если App Group недоступен (нет entitlement или подписи), БД лежит в Application Support.
    public static func onDisk(appGroupIdentifier: String?) throws -> AppDatabase {
        let directory = try databaseDirectory(appGroupIdentifier: appGroupIdentifier)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "questlyn.sqlite")
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let pool = try DatabasePool(path: url.path(percentEncoded: false), configuration: configuration)
        return try AppDatabase(pool)
    }

    /// БД в памяти — для тестов и превью.
    public static func inMemory() throws -> AppDatabase {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return try AppDatabase(DatabaseQueue(configuration: configuration))
    }

    static func databaseDirectory(appGroupIdentifier: String?) throws -> URL {
        if let appGroupIdentifier,
           let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return container.appending(path: "Database", directoryHint: .isDirectory)
        }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return support.appending(path: "Database", directoryHint: .isDirectory)
    }
}
