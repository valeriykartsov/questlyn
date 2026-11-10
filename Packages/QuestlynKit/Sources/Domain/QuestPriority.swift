/// Приоритет · сложность квеста (02, вариант Б). По умолчанию «Средний».
public enum QuestPriority: String, CaseIterable, Codable, Sendable {
    case low
    case medium
    case high

    public static let `default`: QuestPriority = .medium

    /// Множитель k в половинах: 1 → ×0,5, 2 → ×1, 3 → ×1,5. Целые — чтобы расчёт был точным.
    public var multiplierInHalves: Int {
        switch self {
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }

    /// k как число — для отображения.
    public var multiplier: Double { Double(multiplierInHalves) / 2 }
}
