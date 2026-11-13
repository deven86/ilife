import SwiftUI

struct ILifeLogo: View {
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [.cyan, .blue, .green.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "figure.mind.and.body").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .cyan.opacity(0.5), radius: size * 0.2)
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    var delta: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
                .frame(width: 38, height: 38).background(color.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value).font(.title3.bold()).contentTransition(.numericText())
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
                if let delta { Text(delta).font(.caption2.bold()).foregroundStyle(delta.hasPrefix("↓") ? .orange : .green) }
            }
            Spacer(minLength: 0)
        }
        .glassCard(cornerRadius: 18, padding: 12)
    }
}

struct ProgressRing: View {
    let progress: Double
    var color: Color = .green
    var lineWidth: CGFloat = 10
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(AngularGradient(colors: [color.opacity(0.6), color], center: .center), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.8), value: progress)
        }
    }
}

struct SectionTitle: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if let trailing { Text(trailing).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

extension Double {
    var clean: String { self == 0 ? "–" : (self.rounded() == self ? String(Int(self)) : String(format: "%.1f", self)) }
    var grouped: String { self == 0 ? "–" : Int(self).formatted() }
}

func percentChange(_ now: Double, _ before: Double) -> String? {
    guard before > 0, now > 0 else { return nil }
    let p = (now - before) / before * 100
    return (p >= 0 ? "↑ " : "↓ ") + String(format: "%.0f%%", abs(p))
}

/// Adaptive grid: 2 columns on iPhone, 4 on iPad.
struct AdaptiveGrid<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var size
    @ViewBuilder var content: Content
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: size == .regular ? 4 : 2), spacing: 12) {
            content
        }
    }
}

/// Card linking to the Transformation journey (used on Home and Health).
struct TransformationCard: View {
    let photos: [ProgressPhoto]   // newest first
    var body: some View {
        NavigationLink { TransformationView() } label: {
            HStack(spacing: 12) {
                HStack(spacing: -14) {
                    ForEach(Array(photos.prefix(3).enumerated()), id: \.offset) { _, p in
                        Group {
                            if let d = p.thumbnail, let img = UIImage(data: d) { Image(uiImage: img).resizable().scaledToFill() }
                            else { Color.gray.opacity(0.3) }
                        }
                        .frame(width: 46, height: 60).clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                    }
                    if photos.isEmpty {
                        Image(systemName: "figure.stand").font(.title).foregroundStyle(.white)
                            .frame(width: 46, height: 60).background(LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom),
                                                                     in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Transformation").font(.headline)
                    let today = photos.contains { Calendar.current.isDateInToday($0.date) }
                    Text(photos.isEmpty ? "Start your photo journey" : (today ? "Today's photo done ✓ · \(photos.count) photos" : "Take today's photo · \(photos.count) so far"))
                        .font(.caption).foregroundStyle(today ? Color.green : Color.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .glassCard()
    }
}
