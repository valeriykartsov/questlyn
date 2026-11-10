import Foundation
import Observation
import Domain
import Application

/// Состояние приложения для Presentation. Все изменения идут через use cases Application.
@Observable
final class AppModel {
    private(set) var overview: TodayOverview?
    private(set) var isLoaded = false
    var errorMessage: String?

    private let store: any QuestlynStore
    private var timeZone: TimeZone { .current }

    init(store: any QuestlynStore) {
        self.store = store
    }

    var hero: Hero? { overview?.hero }
    var progress: HeroProgress { overview?.progress ?? HeroProgress(grants: [], classAttributes: []) }
    var activeProfessions: [Profession] { overview?.professions.filter(\.isActive) ?? [] }
    var skills: [Skill] { overview?.skills ?? [] }

    func skill(id: UUID?) -> Skill? { skills.first { $0.id == id } }
    func profession(id: UUID?) -> Profession? { overview?.professions.first { $0.id == id } }

    func reload() async {
        await run { [self] in
            overview = try await TodayService(store: store).overview(now: .now, timeZone: timeZone)
        }
        isLoaded = true
    }

    func startAdventure(name: String, catalogItemIds: [String], classTitle: String) async -> Bool {
        await run { [self] in
            try await OnboardingService(store: store).start(heroName: name, catalogItemIds: catalogItemIds, classTitle: classTitle, now: .now)
            await reload()
        }
    }

    func createSkill(title: String, professionId: UUID) async -> Skill? {
        var created: Skill?
        await run { [self] in
            created = try await SkillService(store: store).create(title: title, professionId: professionId, now: .now)
            await reload()
        }
        return created
    }

    func createQuest(_ draft: QuestDraft) async -> Bool {
        await run { [self] in
            try await QuestService(store: store).create(draft, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    func complete(questId: UUID) async -> CompletionReport? {
        var report: CompletionReport?
        await run { [self] in
            report = try await CompletionService(store: store).complete(questId: questId, now: .now, timeZone: timeZone)
            await reload()
        }
        return report
    }

    func undo(questId: UUID) async {
        await run { [self] in
            try await CompletionService(store: store).undo(questId: questId, now: .now)
            await reload()
        }
    }

    @discardableResult
    private func run(_ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            return true
        } catch let error as QuestlynError {
            errorMessage = error.description
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }
}
