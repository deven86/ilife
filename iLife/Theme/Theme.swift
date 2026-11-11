import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case natureGlass, auroraGlow, darkElegance, sunsetDream, minimalClear
    var id: String { rawValue }

    var title: String {
        switch self {
        case .natureGlass: "Nature Glass"
        case .auroraGlow: "Aurora Glow"
        case .darkElegance: "Dark Elegance"
        case .sunsetDream: "Sunset Dream"
        case .minimalClear: "Minimal Clear"
        }
    }

    var accent: Color {
        switch self {
        case .natureGlass: Color(red: 0.25, green: 0.85, blue: 0.95)
        case .auroraGlow: Color(red: 0.35, green: 1.0, blue: 0.7)
        case .darkElegance: Color(red: 0.55, green: 0.6, blue: 1.0)
        case .sunsetDream: Color(red: 1.0, green: 0.6, blue: 0.35)
        case .minimalClear: Color(red: 0.2, green: 0.45, blue: 0.95)
        }
    }

    var colorScheme: ColorScheme { self == .minimalClear ? .light : .dark }

    /// 3x3 mesh colours for the wallpaper
    var mesh: [Color] {
        switch self {
        case .natureGlass:
            [.init(red: 0.05, green: 0.12, blue: 0.25), .init(red: 0.10, green: 0.25, blue: 0.40), .init(red: 0.15, green: 0.30, blue: 0.45),
             .init(red: 0.05, green: 0.25, blue: 0.30), .init(red: 0.12, green: 0.40, blue: 0.50), .init(red: 0.20, green: 0.45, blue: 0.60),
             .init(red: 0.02, green: 0.15, blue: 0.15), .init(red: 0.05, green: 0.25, blue: 0.25), .init(red: 0.08, green: 0.20, blue: 0.30)]
        case .auroraGlow:
            [.init(red: 0.02, green: 0.03, blue: 0.12), .init(red: 0.05, green: 0.10, blue: 0.25), .init(red: 0.15, green: 0.05, blue: 0.30),
             .init(red: 0.05, green: 0.45, blue: 0.35), .init(red: 0.10, green: 0.75, blue: 0.55), .init(red: 0.40, green: 0.20, blue: 0.60),
             .init(red: 0.02, green: 0.05, blue: 0.10), .init(red: 0.03, green: 0.15, blue: 0.20), .init(red: 0.05, green: 0.05, blue: 0.15)]
        case .darkElegance:
            [.init(red: 0.02, green: 0.02, blue: 0.06), .init(red: 0.06, green: 0.05, blue: 0.15), .init(red: 0.03, green: 0.03, blue: 0.10),
             .init(red: 0.05, green: 0.08, blue: 0.25), .init(red: 0.15, green: 0.10, blue: 0.40), .init(red: 0.05, green: 0.10, blue: 0.30),
             .init(red: 0.01, green: 0.01, blue: 0.04), .init(red: 0.04, green: 0.03, blue: 0.12), .init(red: 0.02, green: 0.02, blue: 0.08)]
        case .sunsetDream:
            [.init(red: 0.15, green: 0.10, blue: 0.35), .init(red: 0.35, green: 0.15, blue: 0.45), .init(red: 0.25, green: 0.12, blue: 0.40),
             .init(red: 0.85, green: 0.35, blue: 0.30), .init(red: 1.00, green: 0.55, blue: 0.25), .init(red: 0.90, green: 0.40, blue: 0.40),
             .init(red: 0.20, green: 0.08, blue: 0.20), .init(red: 0.40, green: 0.15, blue: 0.25), .init(red: 0.25, green: 0.10, blue: 0.25)]
        case .minimalClear:
            [.init(red: 0.93, green: 0.95, blue: 0.99), .init(red: 0.88, green: 0.92, blue: 0.98), .init(red: 0.95, green: 0.95, blue: 0.99),
             .init(red: 0.85, green: 0.90, blue: 0.97), .init(red: 0.97, green: 0.98, blue: 1.00), .init(red: 0.88, green: 0.90, blue: 0.97),
             .init(red: 0.92, green: 0.94, blue: 0.98), .init(red: 0.86, green: 0.90, blue: 0.96), .init(red: 0.94, green: 0.95, blue: 0.99)]
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    @Published var customWallpaper: UIImage?

    private var wallpaperURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("wallpaper.jpg")
    }

    init() {
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .natureGlass
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
                    .overlay(Color.black.opacity(themeManager.theme.colorScheme == .dark ? 0.35 : 0.05))
            } else {
                ThemeWallpaper(theme: themeManager.theme)
            }
        }
        .ignoresSafeArea()
    }
}

struct ThemeWallpaper: View {
    let theme: AppTheme
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate)
            let d = 0.08 * sin(t * 0.25)
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5 + d, 0.5 - d], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ], colors: theme.mesh)
        }
        .overlay(alignment: .bottom) {
            if theme == .natureGlass || theme == .sunsetDream { MountainRidge(tint: theme == .sunsetDream ? .black : Color(red: 0.02, green: 0.08, blue: 0.12)) }
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
