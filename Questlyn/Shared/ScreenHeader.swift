import SwiftUI
import Domain
import Application

/// Общая шапка вкладок (макеты 8.11–8.12): подзаголовок, крупный заголовок, справа «Летопись» и настройки.
struct ScreenHeader: View {
    let model: AppModel
    let subtitle: String
    let title: String
    @State private var isShowingChronicle = false
    @State private var isShowingSettings = false

    var body: some View {
        HStack(alignment: .bottom, spacing: QSpacing.m) {
            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                Text(subtitle).font(QFont.text(13)).foregroundStyle(QColor.inkSecondary).lineLimit(1)
                Text(title).font(QFont.title(30)).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            roundButton("book.pages", label: "Летопись") { isShowingChronicle = true }
            roundButton("gearshape", label: "Настройки") { isShowingSettings = true }
        }
        .sheet(isPresented: $isShowingChronicle) { ChronicleSheet(model: model) }
        .sheet(isPresented: $isShowingSettings) { SettingsView(model: model) }
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(QColor.ink)
                .frame(width: 44, height: 44)
                .background(QColor.sheet, in: Circle())
                .overlay(Circle().strokeBorder(QColor.lineStrong))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Летопись в отдельном листе — открывается из шапки любой вкладки.
struct ChronicleSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                ChronicleView(model: model)
                    .padding(.horizontal, QSpacing.screen)
                    .padding(.vertical, QSpacing.l)
            }
            .paperScreen()
            .navigationTitle("Летопись героя")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .refreshable { await model.loadChronicle() }
        }
        .tint(QColor.amber)
    }
}
