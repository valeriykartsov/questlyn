import SwiftUI
import Domain

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
    @AppStorage("appTheme") private var theme: AppTheme = .system
    /// Размеры шрифтов считаются через UIFontMetrics — при смене размера текста пересобираем экраны.
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Экран загрузки — один раз за запуск процесса: при возврате из фона RootView не пересоздаётся (8.2).
    @State private var isShowingSplash = true

    enum AppTab: String { case today, journal, hero, calendar }

    /// В отладке вкладку можно задать аргументом запуска `-QuestlynTab journal` — для проверки экранов в симуляторе.
    @State private var tab: AppTab = {
        #if DEBUG
        if let value = UserDefaults.standard.string(forKey: "QuestlynTab"), let tab = AppTab(rawValue: value) { return tab }
        #endif
        return .today
    }()

    var body: some View {
        Group {
            #if DEBUG
            // `-QuestlynPreview onboardingClass | appearance | health | checkin | map | settings` — экраны, до которых в симуляторе не дойти без нажатий.
            if let preview = UserDefaults.standard.string(forKey: "QuestlynPreview"), model.isLoaded {
                switch preview {
                case "appearance": NavigationStack { AppearanceEditorView(model: model) }
                case "graph": HeroGraphView(model: model)
                case "health": NavigationStack { HealthSettingsView(model: model) }
                case "checkin": CheckInView(model: model)
                case "map": MapOverviewView(model: model)
                case "settings": SettingsView(model: model)
                case "gallery": NavigationStack { ComponentGallery() }
                case "splash": SplashView(finish: {}, frozen: true)
                case "explore": ExploreFlowView(model: model)
                case "pathLandscape": PathLandscapeView(model: model, day: model.today, events: model.agendaEvents)
                case "rhythm": NavigationStack { DayRhythmSettingsView(model: model) }
                case "sleepFix": SleepCorrectionView(model: model, wakeDate: model.today.adding(days: -1))
                default: OnboardingView(model: model, debugClassStep: true)
                }
            } else { content }
            #else
            content
            #endif
        }
        .id(typeSize)
        .overlay {
            if isShowingSplash {
                SplashView { withAnimation(.easeOut(duration: 0.2)) { isShowingSplash = false } }
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(theme.scheme)
        .task {
            await model.reload()
            await model.refreshBackups(createIfNeeded: true)
        }
        .alert("Не получилось", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder private var content: some View {
        Group {
            if !model.isLoaded {
                QColor.paper.ignoresSafeArea()
            } else if model.hero == nil {
                OnboardingView(model: model)
            } else {
                TabView(selection: $tab) {
                    Tab("Сегодня", systemImage: "sun.max", value: AppTab.today) { TodayView(model: model) }
                    Tab("Журнал", systemImage: "book.closed", value: AppTab.journal) { JournalView(model: model) }
                    Tab("Календарь", systemImage: "calendar", value: AppTab.calendar) { CalendarView(model: model) }
                    Tab("Герой", systemImage: "person.crop.circle", value: AppTab.hero) { HeroView(model: model) }
                }
                .tint(QColor.amber)
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
