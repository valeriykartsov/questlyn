import Foundation
import Testing
@testable import Domain

/// «Побродить», этап 14: бутылки, Чёрные башни, маяки, задания, предметы, страж и спутник.
struct ExploreStage14Tests {
    let utc = TimeZone(identifier: "UTC")!
    let last = LocalDate(year: 2026, month: 11, day: 10)

    func noon(_ day: LocalDate) -> Date { VitalsCalculator.date(day, LocalTime(hour: 12, minute: 0)!, timeZone: utc) }

    func input(days: Int) -> ExploreInput {
        let first = last.adding(days: -(days - 1))
        var events: [ExploreEvent] = []
        var random = ExploreRandom(5)
        for day in 0..<days {
            for _ in 0..<2 {
                events.append(ExploreEvent(title: "Событие \(random.int(10))", start: noon(first.adding(days: day)), minutes: 30,
                                           attendeeKeys: (0..<random.int(3)).map { _ in "p\(random.int(20))" }))
            }
        }
        let quests = (0..<12).map { (title: "Квест \($0)", priority: QuestPriority.medium, date: Optional(first.adding(days: $0 % days))) }
        let diary = (0..<12).map { ExploreDiaryNote(date: first.adding(days: $0 % days), mood: .good, note: "Заметка \($0)") }
        let epics = [ExploreEpic(title: "Тимлид", steps: 3, dates: [last]), ExploreEpic(title: "Переезд", steps: 2, dates: [last.adding(days: -1)]),
                     ExploreEpic(title: "Третий", steps: 1, dates: [last])]
        let streak = ExploreHabitDays(title: "Зарядка", days: Set((0..<8).map { last.adding(days: -$0) }))
        let short = ExploreHabitDays(title: "Чтение", days: Set((0..<5).map { last.adding(days: -$0) }))
        return ExploreInput(first: first, last: last, events: events, quests: quests, nights: [:], weekMoods: [:], hasCalendar: true, timeZone: utc)
            .with(diary: diary, epics: epics, habits: [streak, short])
    }

    @Test func newObjectsFollowRules() {
        let data = input(days: 10)
        let island = IslandGenerator.generate(data, seed: 3)
        #expect(island.regions.count == 1)
        // Бутылки — не больше 8, в воде у песка.
        #expect(!island.bottles.isEmpty && island.bottles.count <= ExploreRules.bottleCap)
        for bottle in island.bottles {
            #expect(!island.isLand(bottle.position))
            #expect([(1, 0), (-1, 0), (0, 1), (0, -1)].contains { island.terrain(at: TilePoint(bottle.position.x + $0.0, bottle.position.y + $0.1)) == .sand })
        }
        // Башни — до 2 на остров, вдали от старта, страж по числу шагов.
        #expect(island.towers.filter { !$0.isFinal }.count == 2)
        #expect(island.towers.filter { !$0.isFinal }.allSatisfy { $0.position.distance(to: island.start) >= ExploreRules.towerMinDistanceFromStart && island.isLand($0.position) })
        #expect(island.towers.first?.guardianHP == 85)
        // Маяк — только у серии от 7 дней.
        #expect(island.lighthouses.map(\.title) == ["Зарядка"])
        #expect(island.lighthouses.allSatisfy { island.terrain(at: $0.position) == .sand })
        // Задание — у каждого города, ссылки верные.
        // 15F: у города с поручением Epic обычного задания нет.
        #expect(island.tasks.count + Set(island.errands.map(\.cityId)).count == island.cities.count)
        for task in island.tasks {
            #expect(island.cities.contains { $0.id == task.cityId })
            if case let .reachVillage(id) = task.kind { #expect(island.villages.contains { $0.id == id }) }
        }
    }

    @Test func archipelagoKeepsObjectsOnTheirMonth() {
        let data = input(days: 40)
        let island = IslandGenerator.generate(data, seed: 9)
        #expect(island.regions.count == ExploreRules.chapterCount(days: 40))
        // 15H: башня Epic — на острове главы, где у Epic есть шаг.
        let ordinary = island.towers.filter { !$0.isFinal }
        #expect(!ordinary.isEmpty)
        for tower in ordinary {
            let region = island.regions.first { $0.contains(tower.position) }!
            let epic = data.epics.first { $0.title == tower.title }!
            #expect(epic.dates.contains { $0 >= region.first && $0 <= region.last })
        }
        for task in island.tasks {
            #expect(island.cities.contains { $0.id == task.cityId })
            if case let .reachVillage(id) = task.kind { #expect(island.villages.contains { $0.id == id }) }
        }
        #expect(Set(island.bottles.map(\.id)).count == island.bottles.count)
    }

    @Test func guardianAndCompanion() {
        let levels = Dictionary(uniqueKeysWithValues: Attribute.allCases.map { ($0, 1) })
        let hero = ExploreHero(levels: levels, hp: 125, maxHP: 125, mp: 125, maxMP: 125, rankLetter: "G", skills: [])
        var fight = Encounter(tier: .regular, hero: hero, heroHP: 125, heroMP: 125, seed: 1,
                              guardian: .init(title: "Тимлид", hp: ExploreRules.guardianHP(steps: 3)))
        #expect(fight.npcMaxHP == 85 && fight.opponentTitle == "Страж башни")
        fight.companionAssist(tier: .colleague)
        #expect(fight.npcHP == 85 - 12)
        fight.companionAssist(tier: .colleague)
        #expect(fight.npcHP == 85 - 12)
        fight.perform(.fight)
        // Урон стража — 12% HPmax с разбросом ±20%.
        #expect((125 - fight.heroHP) >= (125 * 0.12 * 0.8).rounded() && (125 - fight.heroHP) <= (125 * 0.12 * 1.2).rounded())
    }
}
