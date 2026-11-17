import Foundation
import Testing
@testable import Domain

/// Этап 15F: поручения Epic на досках и главный город главы.
struct ExploreStage15FTests {
    let utc = TimeZone(identifier: "UTC")!
    let last = LocalDate(year: 2026, month: 11, day: 10)

    func input(days: Int = 50) -> ExploreInput {
        let first = last.adding(days: -(days - 1))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var events: [ExploreEvent] = []
        for day in 0..<days {
            let date = first.adding(days: day)
            for k in 0..<3 {
                let start = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 9 + k))!
                events.append(ExploreEvent(title: ["Стендап", "Ретро", "Кино", "Обед \(day)"][day % 2 == 0 ? k : 3], start: start, minutes: 30, attendeeKeys: ["p\(k)"]))
            }
        }
        let quests = (0..<20).map { (title: "Квест \($0)", priority: QuestPriority.medium, date: Optional(first.adding(days: $0 * 2))) }
        var data = ExploreInput(first: first, last: last, events: events, quests: quests, nights: [:], weekMoods: [:], hasCalendar: true, timeZone: utc)
        data.epics = [ExploreEpic(title: "Сайт", steps: 5, dates: [last.adding(days: -2)], stepTitles: ["Макет", "Вёрстка", "Тексты", "Запуск", "Реклама"]),
                      ExploreEpic(title: "Книга", steps: 1, dates: [first.adding(days: 3)], stepTitles: ["Глава 1"])]
        return data
    }

    @Test func errandsFollowEpicStepsAndEndAtTheTower() {
        let island = IslandGenerator.generate(input(), seed: 4)
        let site = island.errands.first { $0.epicTitle == "Сайт" }
        #expect(site != nil)
        guard let site else { return }
        #expect(site.steps.map(\.title).prefix(3) == ["Макет", "Вёрстка", "Тексты"])
        #expect(site.steps.count == ExploreRules.errandSteps + 1)
        guard case let .tower(towerId) = site.steps.last!.kind else { Issue.record("финал — не башня"); return }
        #expect(island.towers[towerId].title == "Сайт")
        // Ссылки на объекты — в пределах мира, у города поручения нет обычного задания.
        for step in site.steps {
            switch step.kind {
            case let .reachVillage(id): #expect(island.villages.contains { $0.id == id })
            case let .bring(chest): #expect(island.chests.indices.contains(chest))
            default: break
            }
        }
        #expect(island.cities.indices.contains(site.cityId) && !island.tasks.contains { $0.cityId == site.cityId })
        #expect(island.tasks.map(\.id) == Array(island.tasks.indices))
        let book = island.errands.first { $0.epicTitle == "Книга" }
        #expect(book?.steps.count == 2)
    }

    @Test func mainCityIsCapitalOrBusiest() {
        let island = IslandGenerator.generate(input(), seed: 4)
        for region in island.regions {
            guard let city = island.mainCity(of: region) else { continue }
            #expect(region.contains(city.center))
            let local = island.cities.filter { region.contains($0.center) }
            #expect(city.isCapital || (!local.contains(where: \.isCapital) && local.allSatisfy { $0.events <= city.events }))
        }
    }
}
