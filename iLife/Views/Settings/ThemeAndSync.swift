import SwiftUI
import PhotosUI
import CoreData
import CloudKit

// MARK: - Theme gallery

struct ThemeGalleryView: View {
    @EnvironmentObject var theme: ThemeManager
    @State private var wallpaperItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $theme.autoByTime.animation(.easeInOut(duration: 0.6))) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Follow the time of day", systemImage: "sun.and.horizon.fill").font(.headline)
                            Text("Fresh in the morning, ocean at midday, sunset in the evening, aurora at night.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .glassCard()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                    ForEach(Array(AppTheme.allCases.enumerated()), id: \.element.id) { i, t in
                        let selected = !theme.autoByTime && theme.theme == t && theme.customWallpaper == nil
                        Button {
                            Haptics.tap()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                theme.autoByTime = false
                                theme.theme = t
                                theme.setWallpaper(nil)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                ThemeWallpaper(theme: t, animated: false)
                                    .frame(height: 170)
                                    .overlay(alignment: .bottomLeading) { preview(t).padding(10) }
                                    .overlay(alignment: .topTrailing) {
                                        if selected {
                                            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.white, t.accent).padding(8)
                                        }
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title).font(.subheadline.bold())
                                    Text(t.mood).font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.ultraThinMaterial)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(selected ? AnyShapeStyle(t.gradient) : AnyShapeStyle(Color.white.opacity(0.15)), lineWidth: selected ? 3 : 1))
                            .shadow(color: selected ? t.accent.opacity(0.5) : .clear, radius: 12)
                        }
                        .buttonStyle(PressStyle())
                        .appear(i)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your own wallpaper").font(.headline)
                    PhotosPicker(selection: $wallpaperItem, matching: .images) {
                        Label("Choose a photo", systemImage: "photo.on.rectangle")
                    }
                    if theme.customWallpaper != nil {
                        Button("Remove custom wallpaper", role: .destructive) { withAnimation { theme.setWallpaper(nil) } }
                    }
                    Text("Colours and buttons still follow the theme you pick above.").font(.caption).foregroundStyle(.secondary)
                }
                .glassCard()
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Themes")
        .onChange(of: wallpaperItem) { _, item in
            Task {
                if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    withAnimation { theme.setWallpaper(img) }
                }
            }
        }
    }

    /// Tiny mock of the home screen in that theme's colours.
    private func preview(_ t: AppTheme) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 5)
                Circle().trim(from: 0, to: 0.72).stroke(t.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(t.accent).frame(width: 46, height: 6)
                Capsule().fill(t.accent2.opacity(0.8)).frame(width: 30, height: 6)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - iCloud sync status

/// Listens to the sync engine underneath SwiftData and keeps the latest result of each phase.
@MainActor
final class SyncMonitor: ObservableObject {
    static let shared = SyncMonitor()
    @Published var setup = "Waiting"
    @Published var importing = "Waiting"
    @Published var exporting = "Waiting"
    @Published var lastSuccess: Date?
    @Published var errors: [String] = []
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            let type = event.type
            let finished = event.endDate != nil
            let ok = event.succeeded
            let err = event.error.map { Self.describe($0) }
            Task { @MainActor in self?.record(type: type, finished: finished, ok: ok, error: err) }
        }
    }

    private func record(type: NSPersistentCloudKitContainer.EventType, finished: Bool, ok: Bool, error: String?) {
        let text = !finished ? "Running…" : (ok ? "OK" : "Failed")
        switch type {
        case .setup: setup = text
        case .import: importing = text
        case .export: exporting = text
        @unknown default: break
        }
        if finished && ok { lastSuccess = .now }
        if let error {
            let line = "\(Date.now.formatted(date: .omitted, time: .standard)) \(type == .setup ? "setup" : type == .import ? "import" : "export"): \(error)"
            errors.insert(line, at: 0)
            if errors.count > 12 { errors.removeLast() }
        }
    }

    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        var parts = ["\(ns.domain) \(ns.code)", ns.localizedDescription]
        if let partial = ns.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error], let first = partial.values.first {
            let p = first as NSError
            parts.append("first item: \(p.domain) \(p.code) \(p.localizedDescription)")
        }
        if let reason = ns.userInfo[NSLocalizedFailureReasonErrorKey] as? String { parts.append(reason) }
        return parts.joined(separator: " — ")
    }
}

struct SyncStatusView: View {
    @ObservedObject private var sync = SyncMonitor.shared
    @State private var account = "Checking…"

    var body: some View {
        Form {
            Section("iCloud") {
                row("iCloud account", account)
                row("Setup", sync.setup)
                row("Download from iCloud", sync.importing)
                row("Upload to iCloud", sync.exporting)
                if let d = sync.lastSuccess { row("Last successful sync", d.formatted(date: .abbreviated, time: .shortened)) }
            }
            Section {
                if sync.errors.isEmpty {
                    Text("No sync errors since the app was opened.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(sync.errors, id: \.self) { Text($0).font(.caption2).textSelection(.enabled) }
                }
            } header: {
                Text("Problems")
            } footer: {
                Text("If uploads keep failing, send a screenshot of this page — it shows exactly what iCloud is rejecting. Your data is always safe on this device meanwhile.")
            }
        }
        .navigationTitle("Sync Status")
        .task {
            let status = try? await CKContainer(identifier: "iCloud.group.com.jondhale.ilife").accountStatus()
            account = status == .available ? "Signed in" : "Not signed in"
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(value == "Failed" ? Color.red : value == "OK" || value == "Signed in" ? Color.green : Color.secondary)
        }
    }
}
