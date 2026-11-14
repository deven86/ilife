import SwiftUI
import UIKit

// MARK: - Haptics

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func thump() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - Press + entrance animations

/// Buttons gently shrink when pressed.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Cards rise and fade in, one after another.
struct AppearModifier: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 22)
            .scaleEffect(shown || reduceMotion ? 1 : 0.97)
            .onAppear {
                guard !shown else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(index) * 0.06)) { shown = true }
            }
    }
}

extension View {
    func appear(_ index: Int = 0) -> some View { modifier(AppearModifier(index: index)) }
}

// MARK: - Celebration (confetti + banner)

@MainActor
final class Celebration: ObservableObject {
    static let shared = Celebration()
    @Published var burst = 0
    @Published var title = ""
    @Published var subtitle = ""
    @Published var icon = "trophy.fill"
    @Published var showing = false

    func fire(_ title: String, subtitle: String = "", icon: String = "trophy.fill") {
        self.title = title; self.subtitle = subtitle; self.icon = icon
        burst += 1
        Haptics.success()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { showing = true }
        let current = burst
        Task {
            try? await Task.sleep(for: .seconds(3.2))
            if current == burst { withAnimation(.easeOut(duration: 0.4)) { showing = false } }
        }
    }

    /// Fires only once per key per day (e.g. "steps").
    func fireOncePerDay(key: String, _ title: String, subtitle: String = "", icon: String = "trophy.fill") {
        let day = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        let k = "celebrated.\(key)"
        guard UserDefaults.standard.double(forKey: k) != day else { return }
        UserDefaults.standard.set(day, forKey: k)
        fire(title, subtitle: subtitle, icon: icon)
    }
}

struct CelebrationOverlay: View {
    @ObservedObject private var c = Celebration.shared
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        ZStack(alignment: .top) {
            ConfettiView(burst: c.burst, colors: [theme.current.accent, theme.current.accent2, .yellow, .white, .pink])
            if c.showing {
                HStack(spacing: 12) {
                    Image(systemName: c.icon).font(.title2).foregroundStyle(.yellow)
                        .symbolEffect(.bounce, value: c.burst)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title).font(.headline)
                        if !c.subtitle.isEmpty { Text(c.subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(theme.current.gradient, lineWidth: 1.5))
                .padding(.horizontal, 16).padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Lightweight confetti drawn in a Canvas; replays every time `burst` changes.
struct ConfettiView: View {
    let burst: Int
    let colors: [Color]
    @State private var start: Date?

    private struct Piece { let x: Double; let vx: Double; let vy: Double; let size: Double; let spin: Double; let color: Int; let delay: Double }
    private static let pieces: [Piece] = (0..<90).map { i in
        var g = SeededGenerator(seed: UInt64(i + 7))
        return Piece(x: Double.random(in: 0.1...0.9, using: &g), vx: Double.random(in: -0.25...0.25, using: &g),
                     vy: Double.random(in: 0.55...1.15, using: &g), size: Double.random(in: 6...12, using: &g),
                     spin: Double.random(in: 2...9, using: &g), color: Int.random(in: 0..<5, using: &g),
                     delay: Double.random(in: 0...0.35, using: &g))
    }

    var body: some View {
        Group {
            if let start {
                TimelineView(.animation) { ctx in
                    Canvas { context, size in
                        let t = ctx.date.timeIntervalSince(start)
                        for p in Self.pieces {
                            let life = t - p.delay
                            guard life > 0, life < 2.8 else { continue }
                            let x = (p.x + p.vx * life) * size.width
                            let y = (-0.05 + p.vy * life * 0.55 + 0.12 * life * life) * size.height
                            let alpha = max(0, 1 - life / 2.8)
                            var piece = context
                            piece.translateBy(x: x, y: y)
                            piece.rotate(by: .radians(life * p.spin))
                            piece.opacity = alpha
                            let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)
                            piece.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(colors[p.color % colors.count]))
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: burst) { _, _ in
            start = .now
            let token = burst
            Task {
                try? await Task.sleep(for: .seconds(3.3))
                if token == burst { start = nil }
            }
        }
    }
}

/// Deterministic generator so confetti layout is stable between frames.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}

// MARK: - Small animated pieces

/// Number that rolls to its new value.
struct RollingNumber: View {
    let value: Double
    var format: String = "%.0f"
    var font: Font = .title3.bold()
    var body: some View {
        Text(String(format: format, value))
            .font(font).monospacedDigit()
            .contentTransition(.numericText(value: value))
            .animation(.spring(response: 0.6, dampingFraction: 0.85), value: value)
    }
}

/// Soft pulsing glow behind important elements.
struct Glow: ViewModifier {
    let color: Color
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(on ? 0.75 : 0.25), radius: on ? 18 : 8)
            .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { on = true } }
    }
}

extension View {
    func glow(_ color: Color) -> some View { modifier(Glow(color: color)) }
}
