import SwiftUI
import Domain
import Application

/// Библиотека компонентов в коде (7.4): все токены и основные элементы на одном экране — проверка тем и Dynamic Type.
struct ComponentGallery: View {
    @State private var appearance = HeroAppearance.default

    private let colors: [(String, Color)] = [
        ("paper", QColor.paper), ("sheet", QColor.sheet), ("ink", QColor.ink), ("inkSecondary", QColor.inkSecondary),
        ("line", QColor.line), ("amber", QColor.amber), ("forest", QColor.forest), ("hp", QColor.hp), ("mp", QColor.mp),
        ("debuffINT", QColor.debuffINT), ("warmFill", QColor.warmFill), ("coolFill", QColor.coolFill),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.screen) {
                section("Цвета") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: QSpacing.m) {
                        ForEach(colors, id: \.0) { name, color in
                            VStack(spacing: QSpacing.xs) {
                                RoundedRectangle(cornerRadius: QRadius.small).fill(color).frame(height: 40)
                                    .overlay(RoundedRectangle(cornerRadius: QRadius.small).strokeBorder(QColor.line))
                                Text(name).font(QFont.text(11)).foregroundStyle(QColor.inkSecondary)
                            }
                        }
                    }
                }
                section("Шрифты") {
                    Text("Literata 30 · заголовок экрана").font(QFont.title(30))
                    Text("Literata 18 · заголовок секции").font(QFont.title(18))
                    Text("SF Pro 15 · основной текст").font(QFont.text(15))
                    Text("SF Pro 12 · подпись").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                    CapsHeader(title: "Заголовок-капс")
                }
                section("Кнопки") {
                    Button("Основное действие") {}.buttonStyle(PrimaryButtonStyle())
                    Button("Второстепенное") {}.buttonStyle(SecondaryButtonStyle())
                }
                section("Состояние и прогресс") {
                    VitalsCard(vitals: VitalsState(hp: 62, maxHP: 175, mp: 0, maxMP: 120))
                    ProgressBar(fraction: 0.6, color: QColor.amber)
                    HStack { PriorityBars(priority: .low); PriorityBars(priority: .medium); PriorityBars(priority: .high) }
                }
                section("Герой") {
                    HeroStage(appearance: appearance, scale: 2, height: 136)
                    OutfitPicker(appearance: $appearance)
                }
            }
            .padding(QSpacing.screen)
        }
        .paperScreen()
        .navigationTitle("Компоненты")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            Text(title).font(QFont.title(18))
            content()
        }
        .padding(QSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheetCard()
    }
}
