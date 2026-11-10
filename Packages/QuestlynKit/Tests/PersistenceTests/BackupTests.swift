import Foundation
import Testing
import GRDB
import Domain
import Application
@testable import Persistence

/// 7.1: копия и восстановление БД.
struct BackupTests {
    let now = ISO8601DateFormatter().date(from: "2026-11-10T18:00:00Z")!

    @Test func backupAndRestoreRoundTrip() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try AppDatabase.onDisk(at: folder)
        let store = GRDBStore(database)
        try await OnboardingService(store: store).start(heroName: "Арин", catalogItemIds: ["software-engineer"], classTitle: "К",
                                                        now: now, timeZone: .gmt)
        let copy = folder.appending(path: "copy.sqlite")
        do { try database.backup(to: copy) } catch { Issue.record("backup: \(error)"); return }

        // После копии данные меняются, восстановление возвращает состояние копии.
        try await store.eraseAll()
        #expect(try await store.currentHero() == nil)
        do { try database.restore(from: copy) } catch { Issue.record("restore: \(error)"); return }
        #expect(try await store.currentHero()?.name == "Арин")
    }

    @Test func foreignFileIsRejected() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let other = folder.appending(path: "other.sqlite")
        let queue = try DatabaseQueue(path: other.path(percentEncoded: false))
        try queue.write { try $0.execute(sql: "CREATE TABLE note (id INTEGER)") }
        try queue.close()
        let database = try AppDatabase.inMemory()
        #expect(throws: AppDatabase.BackupError.self) { try database.restore(from: other) }
    }
}
