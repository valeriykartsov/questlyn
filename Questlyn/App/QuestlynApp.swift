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

    var body: some View {
        Group {
            if !model.isLoaded {
                QColor.paper.ignoresSafeArea()
            } else if model.hero == nil {
                OnboardingView(model: model)
            } else {
                TabView {
                    Tab("Сегодня", systemImage: "sun.max") { TodayView(model: model) }
                    Tab("Герой", systemImage: "person.crop.circle") { HeroView(model: model) }
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
