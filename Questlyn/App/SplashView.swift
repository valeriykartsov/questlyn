import SwiftUI

/// Экран загрузки (8.2, макет 8.25, вариант A «Вспышка»): «Пиксельная Q», искра в правом верхнем углу вспыхивает,
/// мерцает и гаснет. Только при запуске с нуля, ~0,9 с, касание — пропустить, при «Уменьшении движения» — без искры.
struct SplashView: View {
    let finish: () -> Void
    /// В отладке — застыть на кадре вспышки (проверка скриншотом).
    var frozen = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoOpacity = 0.0
    @State private var sparkScale = 0.0
    @State private var sparkTurn = 0.0
    @State private var sparkOpacity = 0.0
    @State private var isDone = false

    private static let rows = [".XXXXX..", "XX...XX.", "XX...XX.", "XX...XX.", "XX.XXXX.", "XX..XX..", ".XXXXXX.", "......XX"]
    private let cell: CGFloat = 12
    private let qColor = Color(light: 0xB8651B, dark: 0x4FD1C5)
    private let sparkColor = Color(hex: 0xF2B35B)

    var body: some View {
        ZStack {
            QColor.paper.ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack(alignment: .topLeading) {
                    logo
                    spark
                        .scaleEffect(sparkScale)
                        .rotationEffect(.degrees(sparkTurn))
                        .opacity(sparkOpacity)
                        .offset(x: cell * 8 - 20, y: -8)
                }
                .frame(width: cell * 8, height: cell * 8, alignment: .topLeading)
                Text("Questlyn").font(QFont.title(22, weight: .bold)).foregroundStyle(QColor.ink)
            }
            .opacity(logoOpacity)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: end)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Questlyn")
        .accessibilityAddTraits(.isImage)
        .task { await play() }
    }

    private var logo: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, char in
                        Rectangle().fill(char == "X" ? qColor : .clear).frame(width: cell, height: cell)
                    }
                }
            }
        }
    }

    /// Четырёхлучевая пиксельная искра 28×28.
    private var spark: some View {
        ZStack {
            Rectangle().fill(sparkColor).frame(width: 4, height: 28)
            Rectangle().fill(sparkColor).frame(width: 28, height: 4)
            Rectangle().fill(sparkColor).frame(width: 12, height: 12)
            Rectangle().fill(Color(hex: 0xFFFCF6)).frame(width: 6, height: 6)
        }
        .frame(width: 28, height: 28)
    }

    private func play() async {
        if frozen {
            logoOpacity = 1; sparkScale = 1.3; sparkOpacity = 1
            return
        }
        withAnimation(.easeOut(duration: 0.15)) { logoOpacity = 1 }
        guard !reduceMotion else {
            try? await Task.sleep(for: .milliseconds(700))
            end()
            return
        }
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.easeOut(duration: 0.12)) { sparkScale = 1.3; sparkOpacity = 1 }
        try? await Task.sleep(for: .milliseconds(140))
        withAnimation(.easeInOut(duration: 0.14)) { sparkScale = 0.85; sparkTurn = 20 }
        try? await Task.sleep(for: .milliseconds(140))
        withAnimation(.easeInOut(duration: 0.12)) { sparkScale = 1.05; sparkTurn = 45 }
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.easeIn(duration: 0.14)) { sparkScale = 0; sparkTurn = 90; sparkOpacity = 0 }
        try? await Task.sleep(for: .milliseconds(180))
        end()
    }

    private func end() {
        guard !isDone, !frozen else { return }
        isDone = true
        finish()
    }
}
