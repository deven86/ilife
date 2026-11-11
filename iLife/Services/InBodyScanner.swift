import Foundation
import Vision
import UIKit
import PDFKit

/// Reads an InBody result sheet (photo, scan or PDF) with on-device OCR and pulls out the key numbers.
/// Everything runs on the device — the report never leaves the phone.
struct InBodyResult {
    var weightKg: Double?
    var skeletalMuscleKg: Double?
    var bodyFatKg: Double?
    var bodyFatPercent: Double?
    var bmi: Double?
    var totalBodyWaterL: Double?
    var visceralFatLevel: Double?
    var bmrKcal: Double?
    var inBodyScore: Double?
    var testDate: Date?
    var rawText: String = ""

    var foundCount: Int {
        [weightKg, skeletalMuscleKg, bodyFatKg, bodyFatPercent, bmi, totalBodyWaterL, visceralFatLevel, bmrKcal, inBodyScore]
            .compactMap { $0 }.count
    }
}

enum InBodyScanner {

    private struct Line { let text: String; let box: CGRect }

    /// Labels as printed on InBody 270/370/570/770 sheets (English), with plausible value ranges.
    private static let fields: [(key: WritableKeyPath<InBodyResult, Double?>, labels: [String], range: ClosedRange<Double>)] = [
        (\.skeletalMuscleKg, ["skeletal muscle mass", "smm"], 10...80),
        (\.bodyFatPercent, ["percent body fat", "pbf", "body fat percentage"], 2...70),
        (\.bodyFatKg, ["body fat mass"], 1...150),
        (\.totalBodyWaterL, ["total body water", "tbw"], 15...90),
        (\.visceralFatLevel, ["visceral fat level", "visceral fat"], 1...30),
        (\.bmrKcal, ["basal metabolic rate", "bmr"], 800...4000),
        (\.inBodyScore, ["inbody score", "fitness score"], 30...120),
        (\.bmi, ["body mass index", "bmi"], 10...60),
        (\.weightKg, ["weight"], 25...250),
    ]

    static func images(fromPDF data: Data, maxPages: Int = 3) -> [UIImage] {
        guard let doc = PDFDocument(data: data) else { return [] }
        return (0..<min(doc.pageCount, maxPages)).compactMap { i in
            guard let page = doc.page(at: i) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2048 / max(bounds.width, bounds.height)
            return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        }
    }

    static func scan(_ images: [UIImage]) async -> InBodyResult {
        var lines: [Line] = []
        for img in images { lines += await recognize(img) }
        return parse(lines)
    }

    private static func recognize(_ image: UIImage) async -> [Line] {
        guard let cg = image.cgImage else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
            try? handler.perform([request])
            return (request.results ?? []).compactMap { o in
                o.topCandidates(1).first.map { Line(text: $0.string, box: o.boundingBox) }
            }
        }.value
    }

    private static func numbers(in s: String) -> [Double] {
        let pattern = #"\d{1,4}(?:[.,]\d{1,2})?"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap {
            Double(ns.substring(with: $0.range).replacingOccurrences(of: ",", with: "."))
        }
    }

    private static func parse(_ lines: [Line]) -> InBodyResult {
        var result = InBodyResult()
        result.rawText = lines.map(\.text).joined(separator: "\n")
        var used = Set<Int>()

        for field in fields {
            guard result[keyPath: field.key] == nil else { continue }
            for (i, line) in lines.enumerated() where !used.contains(i) {
                let lower = line.text.lowercased()
                guard field.labels.contains(where: { lower.contains($0) }) else { continue }
                // Avoid "Weight Control" / "Target Weight" rows matching plain "weight".
                if field.key == \InBodyResult.weightKg && (lower.contains("control") || lower.contains("target")) { continue }

                // 1) value printed on the same text line
                if let v = numbers(in: line.text).first(where: { field.range.contains($0) }) {
                    result[keyPath: field.key] = v; used.insert(i); break
                }
                // 2) nearest number to the right on the same row
                let rowCandidates = lines.enumerated().filter { j, other in
                    j != i && abs(other.box.midY - line.box.midY) < max(0.012, line.box.height * 0.8) && other.box.minX > line.box.minX
                }.sorted { $0.element.box.minX < $1.element.box.minX }
                if let hit = rowCandidates.lazy.compactMap({ c in
                    numbers(in: c.element.text).first(where: { field.range.contains($0) })
                }).first {
                    result[keyPath: field.key] = hit; used.insert(i); break
                }
                // 3) number directly below (column layouts)
                let below = lines.filter { $0.box.maxY < line.box.minY && line.box.minY - $0.box.maxY < 0.04 && abs($0.box.midX - line.box.midX) < 0.08 }
                    .sorted { $0.box.maxY > $1.box.maxY }
                if let v = below.lazy.compactMap({ numbers(in: $0.text).first(where: { field.range.contains($0) }) }).first {
                    result[keyPath: field.key] = v; used.insert(i); break
                }
            }
        }

        // Derive what can be derived
        if result.bodyFatPercent == nil, let fat = result.bodyFatKg, let w = result.weightKg, w > 0 {
            result.bodyFatPercent = (fat / w * 1000).rounded() / 10
        }
        if result.bodyFatKg == nil, let pbf = result.bodyFatPercent, let w = result.weightKg {
            result.bodyFatKg = (w * pbf / 10).rounded() / 10
        }
        result.testDate = detectDate(in: result.rawText)
        return result
    }

    private static func detectDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let ns = text as NSString
        return detector.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap(\.date).first { $0 < .now && $0 > Date.now.addingTimeInterval(-5 * 365 * 86400) }
    }
}
