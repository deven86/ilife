import SwiftUI
import Charts
import UIKit

// MARK: - Rendering cards to image / PDF

@MainActor
enum Exporter {
    /// Renders a SwiftUI view into a high-resolution image.
    static func image<V: View>(_ view: V, width: CGFloat = 420) -> UIImage? {
        let r = ImageRenderer(content: view.frame(width: width).environment(\.colorScheme, .dark))
        r.scale = 3
        return r.uiImage
    }

    /// Renders a SwiftUI view into a single-page PDF (charts stay sharp).
    static func pdf<V: View>(_ view: V, width: CGFloat = 595, name: String) -> URL? {
        let r = ImageRenderer(content: view.frame(width: width).environment(\.colorScheme, .dark))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe(name) + ".pdf")
        var ok = false
        r.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            ok = true
        }
        return ok ? url : nil
    }

    /// Writes text (e.g. CSV) to a temporary file for sharing.
    static func file(_ text: String, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe(name))
        do { try text.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }

    static func safe(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
    }
}

// MARK: - Branded frame for every shared card

struct ShareFrame<Content: View>: View {
    let title: String
    let subtitle: String
    var accent: [Color] = [Color(red: 0.25, green: 0.85, blue: 0.95), Color(red: 0.3, green: 0.95, blue: 0.65)]
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ILifeLogo(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
            }
            content
            HStack {
                Spacer()
                Text("Made with iLife").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(
            ZStack {
                LinearGradient(colors: [Color(red: 0.04, green: 0.08, blue: 0.18), Color(red: 0.05, green: 0.17, blue: 0.24)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(accent[0].opacity(0.25)).frame(width: 340).blur(radius: 80).offset(x: -140, y: -200)
                Circle().fill(accent[1].opacity(0.2)).frame(width: 300).blur(radius: 90).offset(x: 160, y: 260)
            }
        )
    }
}

/// Solid card (materials don't render into images).
struct ShareBox: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
    }
}
extension View { func shareBox() -> some View { modifier(ShareBox()) } }

struct ShareStat: View {
    let value: String
    let label: String
    var color: Color = .white
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Simple bar or line chart for share cards.
struct ShareChart: View {
    let title: String
    let points: [DayValue]
    let color: Color
    var goal: Double = 0
    var line = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.white.opacity(0.8))
            Chart {
                ForEach(points) { p in
                    if line {
                        LineMark(x: .value("Day", p.date, unit: .day), y: .value(title, p.value))
                            .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.catmullRom)
                        PointMark(x: .value("Day", p.date, unit: .day), y: .value(title, p.value)).foregroundStyle(color).symbolSize(20)
                    } else {
                        BarMark(x: .value("Day", p.date, unit: .day), y: .value(title, p.value))
                            .foregroundStyle(LinearGradient(colors: [color, color.opacity(0.5)], startPoint: .top, endPoint: .bottom)).cornerRadius(3)
                    }
                }
                if goal > 0 { RuleMark(y: .value("Goal", goal)).foregroundStyle(.white.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3])) }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: max(1, points.count / 7))) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)).foregroundStyle(.white.opacity(0.6)) } }
            .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(.white.opacity(0.1)); AxisValueLabel().foregroundStyle(.white.opacity(0.6)) } }
            .chartYScale(domain: line ? yLine : 0...yMax)
            .frame(height: 110)
        }
        .shareBox()
    }

    private var yMax: Double { max((points.map(\.value).max() ?? 1), goal) * 1.15 }
    private var yLine: ClosedRange<Double> {
        let v = points.map(\.value)
        let lo = v.min() ?? 0, hi = v.max() ?? 1
        let pad = max((hi - lo) * 0.3, 1)
        return (lo - pad)...(hi + pad)
    }
}

// MARK: - Share button used across the app

/// Builds a card, then offers it as image + PDF (+ text) in the share sheet.
struct ShareMenuButton<Card: View>: View {
    let name: String
    var text: (() -> String)? = nil
    var extraFiles: (() -> [URL])? = nil
    @ViewBuilder let card: () -> Card
    @State private var items: [Any] = []
    @State private var show = false

    var body: some View {
        Menu {
            Button("Share as image", systemImage: "photo") { share(image: true, pdf: false) }
            Button("Share as PDF", systemImage: "doc.richtext") { share(image: false, pdf: true) }
            if text != nil { Button("Share as text", systemImage: "text.alignleft") { share(image: false, pdf: false, textOnly: true) } }
            if extraFiles != nil { Button("Share data (CSV)", systemImage: "tablecells") { share(image: false, pdf: false, files: true) } }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .sheet(isPresented: $show) { ShareSheet(items: items) }
    }

    private func share(image: Bool, pdf: Bool, textOnly: Bool = false, files: Bool = false) {
        var out: [Any] = []
        if image, let img = Exporter.image(card()) { out.append(img) }
        if pdf, let url = Exporter.pdf(card(), name: name) { out.append(url) }
        if textOnly, let t = text?() { out.append(t) }
        if files, let f = extraFiles?() { out += f }
        guard !out.isEmpty else { return }
        items = out
        show = true
        Haptics.tap()
    }
}

// MARK: - CSV

enum CSV {
    static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") { return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        return s
    }
    static func row(_ fields: [Any?]) -> String {
        fields.map { f -> String in
            switch f {
            case let d as Date: return d.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.colon))
            case let x as Double: return x == x.rounded() ? String(Int(x)) : String(format: "%.2f", x)
            case let i as Int: return String(i)
            case let b as Bool: return b ? "yes" : "no"
            case let s as String: return escape(s)
            case nil: return ""
            default: return escape("\(f!)")
            }
        }.joined(separator: ",")
    }
    static func table(_ header: [String], _ rows: [[Any?]]) -> String {
        ([header.joined(separator: ",")] + rows.map(row)).joined(separator: "\n") + "\n"
    }
}
