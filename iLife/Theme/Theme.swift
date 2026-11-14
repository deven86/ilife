import SwiftUI

private func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

enum AppTheme: String, CaseIterable, Identifiable {
    case natureGlass, auroraGlow, darkElegance, sunsetDream, minimalClear
    case oceanDepth, neonPulse, lavaEnergy, roseGold, forestMist, midnightGold, cosmicViolet
    var id: String { rawValue }

    var title: String {
        switch self {
        case .natureGlass: "Nature Glass"
        case .auroraGlow: "Aurora Glow"
        case .darkElegance: "Dark Elegance"
        case .sunsetDream: "Sunset Dream"
        case .minimalClear: "Minimal Clear"
        case .oceanDepth: "Ocean Depth"
        case .neonPulse: "Neon Pulse"
        case .lavaEnergy: "Lava Energy"
        case .roseGold: "Rose Gold"
        case .forestMist: "Forest Mist"
        case .midnightGold: "Midnight Gold"
        case .cosmicViolet: "Cosmic Violet"
        }
    }

    var mood: String {
        switch self {
        case .natureGlass: "Calm · mountain air"
        case .auroraGlow: "Northern lights"
        case .darkElegance: "Quiet · focused"
        case .sunsetDream: "Warm · golden hour"
        case .minimalClear: "Light · clean"
        case .oceanDepth: "Deep · cool"
        case .neonPulse: "Electric · gym night"
        case .lavaEnergy: "High energy"
        case .roseGold: "Soft · premium"
        case .forestMist: "Fresh · green"
        case .midnightGold: "Black & gold"
        case .cosmicViolet: "Space · dreamy"
        }
    }

    var accent: Color {
        switch self {
        case .natureGlass: c(0.25, 0.85, 0.95)
        case .auroraGlow: c(0.35, 1.0, 0.7)
        case .darkElegance: c(0.55, 0.6, 1.0)
        case .sunsetDream: c(1.0, 0.6, 0.35)
        case .minimalClear: c(0.2, 0.45, 0.95)
        case .oceanDepth: c(0.2, 0.75, 1.0)
        case .neonPulse: c(1.0, 0.25, 0.75)
        case .lavaEnergy: c(1.0, 0.42, 0.15)
        case .roseGold: c(1.0, 0.62, 0.62)
        case .forestMist: c(0.45, 0.9, 0.5)
        case .midnightGold: c(1.0, 0.8, 0.3)
        case .cosmicViolet: c(0.75, 0.55, 1.0)
        }
    }

    /// Second colour for gradients, rings and glows.
    var accent2: Color {
        switch self {
        case .natureGlass: c(0.3, 0.95, 0.65)
        case .auroraGlow: c(0.45, 0.6, 1.0)
        case .darkElegance: c(0.85, 0.5, 1.0)
        case .sunsetDream: c(1.0, 0.35, 0.5)
        case .minimalClear: c(0.3, 0.75, 0.95)
        case .oceanDepth: c(0.25, 0.95, 0.85)
        case .neonPulse: c(0.2, 0.9, 1.0)
        case .lavaEnergy: c(1.0, 0.8, 0.2)
        case .roseGold: c(1.0, 0.82, 0.6)
        case .forestMist: c(0.75, 0.95, 0.35)
        case .midnightGold: c(1.0, 0.55, 0.25)
        case .cosmicViolet: c(0.4, 0.75, 1.0)
        }
    }

    var gradient: LinearGradient { LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing) }

    var colorScheme: ColorScheme { self == .minimalClear ? .light : .dark }

    /// 3x3 mesh colours for the wallpaper
    var mesh: [Color] {
        switch self {
        case .natureGlass:
            [c(0.05, 0.12, 0.25), c(0.10, 0.25, 0.40), c(0.15, 0.30, 0.45),
             c(0.05, 0.25, 0.30), c(0.12, 0.40, 0.50), c(0.20, 0.45, 0.60),
             c(0.02, 0.15, 0.15), c(0.05, 0.25, 0.25), c(0.08, 0.20, 0.30)]
        case .auroraGlow:
            [c(0.02, 0.03, 0.12), c(0.05, 0.10, 0.25), c(0.15, 0.05, 0.30),
             c(0.05, 0.45, 0.35), c(0.10, 0.75, 0.55), c(0.40, 0.20, 0.60),
             c(0.02, 0.05, 0.10), c(0.03, 0.15, 0.20), c(0.05, 0.05, 0.15)]
        case .darkElegance:
            [c(0.02, 0.02, 0.06), c(0.06, 0.05, 0.15), c(0.03, 0.03, 0.10),
             c(0.05, 0.08, 0.25), c(0.15, 0.10, 0.40), c(0.05, 0.10, 0.30),
             c(0.01, 0.01, 0.04), c(0.04, 0.03, 0.12), c(0.02, 0.02, 0.08)]
        case .sunsetDream:
            [c(0.15, 0.10, 0.35), c(0.35, 0.15, 0.45), c(0.25, 0.12, 0.40),
             c(0.85, 0.35, 0.30), c(1.00, 0.55, 0.25), c(0.90, 0.40, 0.40),
             c(0.20, 0.08, 0.20), c(0.40, 0.15, 0.25), c(0.25, 0.10, 0.25)]
        case .minimalClear:
            [c(0.93, 0.95, 0.99), c(0.88, 0.92, 0.98), c(0.95, 0.95, 0.99),
             c(0.85, 0.90, 0.97), c(0.97, 0.98, 1.00), c(0.88, 0.90, 0.97),
             c(0.92, 0.94, 0.98), c(0.86, 0.90, 0.96), c(0.94, 0.95, 0.99)]
        case .oceanDepth:
            [c(0.00, 0.10, 0.25), c(0.00, 0.22, 0.42), c(0.02, 0.15, 0.35),
             c(0.00, 0.30, 0.50), c(0.05, 0.50, 0.65), c(0.00, 0.28, 0.48),
             c(0.00, 0.05, 0.14), c(0.00, 0.12, 0.25), c(0.00, 0.06, 0.16)]
        case .neonPulse:
            [c(0.05, 0.00, 0.12), c(0.25, 0.00, 0.35), c(0.05, 0.05, 0.25),
             c(0.55, 0.00, 0.45), c(0.20, 0.10, 0.60), c(0.00, 0.40, 0.60),
             c(0.03, 0.00, 0.08), c(0.10, 0.00, 0.25), c(0.00, 0.10, 0.22)]
        case .lavaEnergy:
            [c(0.10, 0.02, 0.02), c(0.35, 0.05, 0.02), c(0.18, 0.03, 0.05),
             c(0.75, 0.18, 0.05), c(1.00, 0.45, 0.10), c(0.70, 0.12, 0.10),
             c(0.06, 0.01, 0.02), c(0.25, 0.04, 0.03), c(0.10, 0.02, 0.04)]
        case .roseGold:
            [c(0.25, 0.12, 0.18), c(0.45, 0.25, 0.30), c(0.30, 0.15, 0.22),
             c(0.70, 0.42, 0.42), c(0.90, 0.65, 0.55), c(0.65, 0.38, 0.42),
             c(0.18, 0.08, 0.14), c(0.35, 0.18, 0.24), c(0.22, 0.10, 0.16)]
        case .forestMist:
            [c(0.03, 0.12, 0.08), c(0.08, 0.25, 0.15), c(0.05, 0.18, 0.14),
             c(0.10, 0.38, 0.22), c(0.25, 0.55, 0.35), c(0.12, 0.35, 0.28),
             c(0.02, 0.07, 0.05), c(0.05, 0.16, 0.10), c(0.03, 0.10, 0.08)]
        case .midnightGold:
            [c(0.02, 0.02, 0.03), c(0.08, 0.06, 0.02), c(0.03, 0.03, 0.04),
             c(0.20, 0.14, 0.03), c(0.45, 0.32, 0.08), c(0.15, 0.10, 0.04),
             c(0.01, 0.01, 0.02), c(0.06, 0.04, 0.02), c(0.02, 0.02, 0.03)]
        case .cosmicViolet:
            [c(0.04, 0.02, 0.14), c(0.14, 0.06, 0.32), c(0.06, 0.05, 0.22),
             c(0.30, 0.12, 0.55), c(0.50, 0.30, 0.80), c(0.15, 0.20, 0.55),
             c(0.02, 0.01, 0.08), c(0.08, 0.04, 0.20), c(0.03, 0.04, 0.14)]
        }
    }

    /// Theme chosen automatically from the time of day.
    static func forNow() -> AppTheme {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11: .natureGlass
        case 11..<16: .oceanDepth
        case 16..<19: .sunsetDream
        case 19..<22: .auroraGlow
        default: .darkElegance
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    /// The theme the user picked.
    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    /// Follow the time of day instead of a fixed theme.
    @Published var autoByTime: Bool {
        didSet { UserDefaults.standard.set(autoByTime, forKey: "themeAuto") }
    }
    @Published var customWallpaper: UIImage?

    /// The theme actually on screen.
    var current: AppTheme { autoByTime ? AppTheme.forNow() : theme }

    private var wallpaperURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("wallpaper.jpg")
    }

    init() {
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .natureGlass
        autoByTime = UserDefaults.standard.bool(forKey: "themeAuto")
        if let data = try? Data(contentsOf: wallpaperURL) { customWallpaper = UIImage(data: data) }
    }

    func setWallpaper(_ image: UIImage?) {
        customWallpaper = image
        try? FileManager.default.createDirectory(at: wallpaperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let image, let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: wallpaperURL, options: .completeFileProtection)
        } else {
            try? FileManager.default.removeItem(at: wallpaperURL)
        }
    }
}

/// Full-screen animated wallpaper behind every screen.
struct WallpaperView: View {
    @EnvironmentObject var themeManager: ThemeManager
    var body: some View {
        ZStack {
            if let image = themeManager.customWallpaper {
                Image(uiImage: image).resizable().scaledToFill()
                    .overlay(Color.black.opacity(themeManager.current.colorScheme == .dark ? 0.35 : 0.05))
            } else {
                ThemeWallpaper(theme: themeManager.current)
            }
        }
        .ignoresSafeArea()
    }
}

struct ThemeWallpaper: View {
    let theme: AppTheme
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if animated && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    layers(t: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                layers(t: 0)
            }
        }
        .overlay(alignment: .bottom) {
            if theme == .natureGlass || theme == .sunsetDream || theme == .forestMist {
                MountainRidge(tint: theme == .sunsetDream ? .black : c(0.02, 0.08, 0.10))
            }
        }
    }

    private func layers(t: Double) -> some View {
        let d = Float(0.09 * sin(t * 0.25))
        let e = Float(0.06 * cos(t * 0.18))
        return ZStack {
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5 + e, 0], [1, 0],
                [0, 0.5 + d], [0.5 + d, 0.5 - d], [1, 0.5 - e],
                [0, 1], [0.5 - e, 1], [1, 1]
            ], colors: theme.mesh)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                Circle().fill(theme.accent.opacity(0.30)).frame(width: w * 0.9)
                    .position(x: w * (0.25 + 0.20 * sin(t * 0.11)), y: h * (0.22 + 0.10 * cos(t * 0.09)))
                    .blur(radius: 90)
                Circle().fill(theme.accent2.opacity(0.25)).frame(width: w * 0.8)
                    .position(x: w * (0.80 + 0.15 * cos(t * 0.08)), y: h * (0.62 + 0.14 * sin(t * 0.07)))
                    .blur(radius: 100)
            }
            .allowsHitTesting(false)
        }
    }
}

/// Simple layered mountain silhouette, drawn in code (no stock images needed).
struct MountainRidge: View {
    let tint: Color
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Path { p in
                    p.move(to: .init(x: 0, y: h * 0.72))
                    p.addLine(to: .init(x: w * 0.18, y: h * 0.55)); p.addLine(to: .init(x: w * 0.32, y: h * 0.66))
                    p.addLine(to: .init(x: w * 0.55, y: h * 0.48)); p.addLine(to: .init(x: w * 0.75, y: h * 0.63))
                    p.addLine(to: .init(x: w, y: h * 0.52)); p.addLine(to: .init(x: w, y: h)); p.addLine(to: .init(x: 0, y: h))
                }.fill(tint.opacity(0.45))
                Path { p in
                    p.move(to: .init(x: 0, y: h * 0.82))
                    p.addLine(to: .init(x: w * 0.25, y: h * 0.70)); p.addLine(to: .init(x: w * 0.45, y: h * 0.80))
                    p.addLine(to: .init(x: w * 0.70, y: h * 0.68)); p.addLine(to: .init(x: w, y: h * 0.78))
                    p.addLine(to: .init(x: w, y: h)); p.addLine(to: .init(x: 0, y: h))
                }.fill(tint.opacity(0.7))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Glass

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 16
    @ViewBuilder
    func body(content: Content) -> some View {
        let shaped = content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
        if #available(iOS 26.0, *) {
            shaped.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            shaped
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
        }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 22, padding: CGFloat = 16) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, padding: padding))
    }

    /// Standard screen chrome: wallpaper behind a scrolling stack.
    func iLifeScreen() -> some View {
        self.scrollContentBackground(.hidden).background { WallpaperView() }
    }
}
