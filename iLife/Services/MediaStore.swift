import Foundation
import SwiftData
import UIKit

/// Photos you add once for an exercise or food, reused everywhere that item appears
/// (plans, logs, the food list, live workouts). Backed by SwiftData → iCloud.
@MainActor
final class MediaStore: ObservableObject {
    static let shared = MediaStore()
    @Published private(set) var photos: [String: Data] = [:]
    private var container: ModelContainer?

    static func key(_ kind: String, _ name: String) -> String {
        kind + ":" + name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func attach(_ container: ModelContainer) {
        self.container = container
        reload()
    }

    func reload() {
        guard let container else { return }
        let ctx = ModelContext(container)
        let all = (try? ctx.fetch(FetchDescriptor<LibraryPhoto>())) ?? []
        var map: [String: Data] = [:]
        for p in all.sorted(by: { $0.updated < $1.updated }) {
            if let d = p.image { map[Self.key(p.kind, p.key)] = d }
        }
        photos = map
    }

    func photo(_ kind: String, _ name: String) -> Data? { photos[Self.key(kind, name)] }

    /// Save (or replace) the photo for an item.
    func set(_ kind: String, _ name: String, image: UIImage) {
        guard let container, !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let data = ImageTools.jpeg(image, maxSide: 900, quality: 0.8) else { return }
        let ctx = ModelContext(container)
        let k = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let existing = (try? ctx.fetch(FetchDescriptor<LibraryPhoto>(predicate: #Predicate { $0.kind == kind && $0.key == k }))) ?? []
        existing.forEach { ctx.delete($0) }
        ctx.insert(LibraryPhoto(kind: kind, key: k, image: data))
        try? ctx.save()
        photos[Self.key(kind, name)] = data
    }

    func remove(_ kind: String, _ name: String) {
        guard let container else { return }
        let ctx = ModelContext(container)
        let k = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let existing = (try? ctx.fetch(FetchDescriptor<LibraryPhoto>(predicate: #Predicate { $0.kind == kind && $0.key == k }))) ?? []
        existing.forEach { ctx.delete($0) }
        try? ctx.save()
        photos[Self.key(kind, name)] = nil
    }
}
