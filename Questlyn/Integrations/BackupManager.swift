import Foundation
import Persistence

/// Копия БД (7.1): автоматически раз в сутки в «Файлы › На iPhone › Questlyn › Backups»; хранятся 7 последних.
/// Личная команда разработчика не поддерживает iCloud (11.11.2026), поэтому в iCloud Drive копия попадает вручную — «Поделиться» → «Сохранить в Файлы».
/// Если позже появится платный аккаунт и iCloud-контейнер, код сам начнёт класть копии туда.
nonisolated struct BackupFile: Identifiable, Hashable, Sendable {
    let url: URL
    let date: Date
    let bytes: Int
    var id: URL { url }
}

nonisolated enum BackupLocation: Equatable, Sendable {
    case iCloud, device

    var title: String {
        switch self {
        case .iCloud: "iCloud Drive › Questlyn"
        case .device: "Файлы › На iPhone › Questlyn"
        }
    }
}

nonisolated struct BackupManager: Sendable {
    static let containerIdentifier = "iCloud.valeravalera.Questlyn"
    static let keep = 7
    static let interval: TimeInterval = 24 * 3600
    private static let prefix = "questlyn-"

    let database: AppDatabase

    /// Папка копий: iCloud-контейнер, иначе Documents приложения. Вызывать не с главного потока — iCloud может отвечать медленно.
    static func folder() -> (URL, BackupLocation)? {
        let manager = FileManager.default
        if let cloud = manager.url(forUbiquityContainerIdentifier: containerIdentifier) {
            let folder = cloud.appending(path: "Documents/Backups", directoryHint: .isDirectory)
            if (try? manager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil { return (folder, .iCloud) }
        }
        guard let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let folder = documents.appending(path: "Backups", directoryHint: .isDirectory)
        guard (try? manager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return nil }
        return (folder, .device)
    }

    static func list(in folder: URL) -> [BackupFile] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix(prefix) && ["sqlite", "icloud"].contains($0.pathExtension) }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return BackupFile(url: url, date: values?.contentModificationDate ?? .distantPast, bytes: values?.fileSize ?? 0)
            }
            .sorted { $0.date > $1.date }
    }

    /// Новая копия; старые сверх семи удаляются.
    @discardableResult
    func backup(now: Date) throws -> BackupFile? {
        guard let (folder, _) = Self.folder() else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let url = folder.appending(path: "\(Self.prefix)\(formatter.string(from: now)).sqlite")
        // Сначала во временный файл, затем — в iCloud одним действием, чтобы синхронизировалась только целая копия.
        let temporary = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
        try database.backup(to: temporary)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: temporary, to: url)
        for old in Self.list(in: folder).dropFirst(Self.keep) { try? FileManager.default.removeItem(at: old.url) }
        return Self.list(in: folder).first { $0.url.lastPathComponent == url.lastPathComponent }
    }

    /// Раз в сутки при запуске или возврате в приложение.
    func backupIfNeeded(now: Date) {
        guard let (folder, _) = Self.folder() else { return }
        if let latest = Self.list(in: folder).first, now.timeIntervalSince(latest.date) < Self.interval { return }
        _ = try? backup(now: now)
    }

    /// Восстановление: файл из iCloud сначала скачивается (координированное чтение), потом заменяет данные.
    func restore(_ file: BackupFile) throws {
        let local = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: file.url, options: [], error: &coordinationError) { readable in
            do { try FileManager.default.copyItem(at: readable, to: local) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
        defer { try? FileManager.default.removeItem(at: local) }
        try database.restore(from: local)
    }
}
