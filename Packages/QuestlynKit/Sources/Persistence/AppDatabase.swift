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
        try onDisk(at: databaseDirectory(appGroupIdentifier: appGroupIdentifier))
    }

    /// БД в указанной папке — для тестов перезапуска.
    static func onDisk(at directory: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "questlyn.sqlite")
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let pool = try DatabasePool(path: url.path(percentEncoded: false), configuration: configuration)
        return try AppDatabase(pool)
    }

    /// Удалить все таблицы и данные, затем применить миграции к пустой БД.
    func eraseAndMigrate() async throws {
        try await writer.erase()
        try Migrations.migrator.migrate(writer)
    }

    /// Резервная копия (7.1): согласованная копия всей БД в файл, даже если в это время идут записи.
    public func backup(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let destination = try DatabaseQueue(path: url.path(percentEncoded: false))
        try writer.backup(to: destination)
        try destination.close()
    }

    /// Восстановление из копии: данные копии заменяют текущие, затем — миграции до текущей схемы.
    public func restore(from url: URL) throws {
        // Копия из БД в режиме WAL наследует его, поэтому открываем без readonly (иначе SQLite не создаст -shm).
        let source = try DatabaseQueue(path: url.path(percentEncoded: false))
        let isQuestlyn = try source.read { try $0.tableExists("hero") && $0.tableExists("progressGrant") }
        guard isQuestlyn else { throw BackupError.notQuestlynBackup }
        try source.backup(to: writer)
        try source.close()
        try Migrations.migrator.migrate(writer)
    }

    public enum BackupError: Error, Sendable { case notQuestlynBackup }

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
