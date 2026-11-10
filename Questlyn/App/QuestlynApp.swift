import SwiftUI

@main
struct QuestlynApp: App {
    @State private var environment: Result<AppModel, Error>

    init() {
        QFont.registerBundledFonts()
        _environment = State(initialValue: AppEnvironment.live())
    }

    var body: some Scene {
        WindowGroup {
            switch environment {
            case .success(let model):
                RootView(model: model)
            case .failure(let error):
                StartupErrorView(message: error.localizedDescription)
            }
        }
    }
}

/// Нет героя — онбординг, иначе вкладки.
struct RootView: View {
    @Bindable var model: AppModel

    enum AppTab: String { case today, journal, hero }

    /// В отладке вкладку можно задать аргументом запуска `-QuestlynTab journal` — для проверки экранов в симуляторе.
    @State private var tab: AppTab = {
        #if DEBUG
        if let value = UserDefaults.standard.string(forKey: "QuestlynTab"), let tab = AppTab(rawValue: value) { return tab }
        #endif
        return .today
    }()

    var body: some View {
        Group {
            if !model.isLoaded {
                QColor.paper.ignoresSafeArea()
            } else if model.hero == nil {
                OnboardingView(model: model)
            } else {
                TabView(selection: $tab) {
                    Tab("Сегодня", systemImage: "sun.max", value: AppTab.today) { TodayView(model: model) }
                    Tab("Журнал", systemImage: "book.closed", value: AppTab.journal) { JournalView(model: model) }
                    Tab("Герой", systemImage: "person.crop.circle", value: AppTab.hero) { HeroView(model: model) }
                }
                .tint(QColor.amber)
            }
        }
        .task { await model.reload() }
        .alert("Не получилось", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
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
