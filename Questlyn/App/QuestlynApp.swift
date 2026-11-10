import SwiftUI
import Persistence

@main
struct QuestlynApp: App {
    @State private var environment: AppEnvironment

    init() {
        QFont.registerBundledFonts()
        _environment = State(initialValue: AppEnvironment.live())
    }

    var body: some Scene {
        WindowGroup {
            switch environment {
            case .ready(let dependencies):
                TodayView(model: TodayModel(service: dependencies.todayService))
            case .failed(let message):
                StartupErrorView(message: message)
            }
        }
    }
}

/// Не удалось открыть БД — показываем причину, а не падаем.
struct StartupErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: QSpacing.l) {
            Text("Не удалось открыть данные")
                .font(QFont.title(22))
            Text(message)
                .font(QFont.text(13))
                .foregroundStyle(QColor.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(QSpacing.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(QColor.paper)
        .foregroundStyle(QColor.ink)
    }
}
