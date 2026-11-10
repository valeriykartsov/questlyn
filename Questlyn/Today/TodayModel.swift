import Foundation
import Observation
import Domain
import Application

@Observable
final class TodayModel {
    private(set) var overview: TodayOverview?
    private(set) var errorMessage: String?
    private let service: TodayService

    init(service: TodayService) {
        self.service = service
    }

    func load(now: Date = .now, timeZone: TimeZone = .current) async {
        do {
            overview = try await service.overview(now: now, timeZone: timeZone)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Уровни атрибутов. До этапа 1 начислений нет — все нули.
    var attributeLevels: [(Attribute, Int)] {
        Attribute.allCases.map { ($0, 0) }
    }
}
