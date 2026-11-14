import SwiftUI
import SwiftData
import UserNotifications
import AVKit
import PhotosUI
import CoreTransferable

/// Daily progress photos: capture, timeline, before/after compare, share.
struct TransformationView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var health: HealthKitManager
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]

    @State private var pose = "All"
    @State private var showCapture = false
    @State private var showCompare = false
    @State private var selecting = false
    @State private var selected: Set<PersistentIdentifier> = []
    @State private var detail: ProgressPhoto?
    @State private var shareItems: [Any] = []
    @State private var showShare = false

    static let poses = ["Front", "Side", "Back", "Other"]

    private var filtered: [ProgressPhoto] { pose == "All" ? photos : photos.filter { $0.pose == pose } }
    private var tookToday: Bool { photos.contains { Calendar.current.isDateInToday($0.date) } }

    /// Consecutive days (ending today or yesterday) with at least one photo.
    private var streak: Int {
        let days = Set(photos.map { Calendar.current.startOfDay(for: $0.date) })
        var d = Calendar.current.startOfDay(for: .now)
        if !days.contains(d) { d = Calendar.current.date(byAdding: .day, value: -1, to: d)! }
        var n = 0
        while days.contains(d) { n += 1; d = Calendar.current.date(byAdding: .day, value: -1, to: d)! }
        return n
    }

    private var months: [(Date, [ProgressPhoto])] {
        let groups = Dictionary(grouping: filtered) { Calendar.current.dateInterval(of: .month, for: $0.date)!.start }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary
                Picker("Pose", selection: $pose) {
                    ForEach(["All"] + Self.poses, id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)

                if photos.isEmpty {
                    ContentUnavailableView {
                        Label("Start your journey", systemImage: "figure.stand")
                    } description: {
                        Text("Take one photo a day in the same spot, same light and same pose. In a few weeks you'll see the change.")
                    } actions: {
                        Button("Take today's photo") { showCapture = true }.buttonStyle(.borderedProminent)
                    }
                    .glassCard()
                }

                ForEach(months, id: \.0) { month, items in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(items) { p in tile(p) }
                        }
                    }
                }
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Transformation")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !photos.isEmpty {
                    Button(selecting ? "Done" : "Select") { selecting.toggle(); selected.removeAll() }
                }
                Button { showCapture = true } label: { Image(systemName: "camera.fill") }
            }
            if selecting {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Compare", systemImage: "rectangle.split.2x1") { showCompare = true }
                        .disabled(selected.count != 2 || photos.contains { selected.contains($0.persistentModelID) && $0.isVideo })
                    Spacer()
                    Text("\(selected.count) selected").font(.caption)
                    Spacer()
                    Button("Share", systemImage: "square.and.arrow.up") {
                        shareItems = photos.filter { selected.contains($0.persistentModelID) }.sorted { $0.date < $1.date }
                            .compactMap { $0.shareItem() }
                        showShare = !shareItems.isEmpty
                    }
                    .disabled(selected.isEmpty)
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        photos.filter { selected.contains($0.persistentModelID) }.forEach { context.delete($0) }
                        selected.removeAll(); selecting = false
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showCapture) { CaptureProgressSheet(defaultWeight: health.weightKg) }
        .sheet(item: $detail) { ProgressDetailView(photo: $0) }
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
        .sheet(isPresented: $showCompare) {
            let pair = photos.filter { selected.contains($0.persistentModelID) }.sorted { $0.date < $1.date }
            if pair.count == 2 { CompareView(before: pair[0], after: pair[1]) }
        }
    }

    private var summary: some View {
        let sorted = photos.sorted { $0.date < $1.date }
        let stills = sorted.filter { !$0.isVideo }
        let first = stills.first, last = stills.last
        let days = sorted.first.map { Calendar.current.dateComponents([.day], from: $0.date, to: .now).day ?? 0 } ?? 0
        let w0 = sorted.first { $0.weightKg > 0 }?.weightKg ?? 0
        let w1 = sorted.last { $0.weightKg > 0 }?.weightKg ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                stat("\(photos.count)", "entries")
                Spacer()
                stat("\(streak)🔥", "day streak")
                Spacer()
                stat("\(days)", "days in")
                Spacer()
                stat(w0 > 0 && w1 > 0 ? String(format: "%+.1f", w1 - w0) : "–", "kg change")
            }
            HStack(spacing: 10) {
                Button { showCapture = true } label: {
                    Label(tookToday ? "Add another" : "Today's photo / video", systemImage: "camera.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                if let first, let last, first.persistentModelID != last.persistentModelID {
                    Button {
                        selected = [first.persistentModelID, last.persistentModelID]
                        showCompare = true
                    } label: {
                        Label("Day 1 vs Now", systemImage: "rectangle.split.2x1").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            DailyReminderToggle()
        }
        .glassCard()
    }

    private func stat(_ v: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func tile(_ p: ProgressPhoto) -> some View {
        let isSel = selected.contains(p.persistentModelID)
        return Button {
            if selecting {
                if isSel { selected.remove(p.persistentModelID) } else { selected.insert(p.persistentModelID) }
            } else { detail = p }
        } label: {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let d = p.thumbnail ?? p.image, let img = UIImage(data: d) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else { Color.gray.opacity(0.3) }
                }
                .frame(minWidth: 0, maxWidth: .infinity).frame(height: 140).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.date.formatted(.dateTime.day().month(.abbreviated))).font(.caption.bold())
                    Text(p.weightKg > 0 ? "\(p.weightKg.clean) kg · \(p.pose)" : p.pose).font(.system(size: 10))
                }
                .foregroundStyle(.white).padding(6)
            }
            .overlay(alignment: .topLeading) {
                if p.isVideo {
                    Label(p.durationSeconds > 0 ? "\(Int(p.durationSeconds))s" : "Video", systemImage: "play.fill")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(.black.opacity(0.55), in: Capsule()).padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if selecting {
                    Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(isSel ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white)).padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Capture

struct CaptureProgressSheet: View {
    let defaultWeight: Double
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var pose = "Front"
    @State private var date = Date.now
    @State private var weight = ""
    @State private var note = ""
    @State private var showCamera = false
    @State private var showVideoCamera = false
    @State private var videoURL: URL?
    @State private var videoItem: PhotosPickerItem?
    @State private var videoSeconds = 0.0
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let videoURL {
                        VideoPlayer(player: AVPlayer(url: videoURL)).frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 12))
                    } else if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 360).frame(maxWidth: .infinity)
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button(image == nil ? "Take photo" : "Retake photo", systemImage: "camera.fill") { showCamera = true }
                        Button(videoURL == nil ? "Record video (up to 30 s)" : "Record again", systemImage: "video.fill") { showVideoCamera = true }
                    }
                    PhotoSourceButton(onPick: { image = $0; videoURL = nil }) { Label("Choose photo from Library", systemImage: "photo.on.rectangle") }
                    PhotosPicker(selection: $videoItem, matching: .videos) { Label("Choose video from Library", systemImage: "film") }
                } footer: {
                    Text("Tip: same place, same light, same pose every day — that's what makes the comparison honest.")
                }
                Section("Details") {
                    Picker("Pose", selection: $pose) { ForEach(TransformationView.poses, id: \.self) { Text($0) } }
                    DatePicker("Date", selection: $date, in: ...Date.now)
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("kg", text: $weight).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Text("kg").foregroundStyle(.secondary)
                    }
                    TextField("Note (optional)", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Progress Photo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled((image == nil && videoURL == nil) || saving)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(device: .front) { img in
                    showCamera = false
                    if let img { image = img; videoURL = nil }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showVideoCamera) {
                VideoCameraPicker { url in
                    showVideoCamera = false
                    if let url { Task { await useVideo(url) } }
                }
                .ignoresSafeArea()
            }
            .onChange(of: videoItem) { _, item in
                guard let item else { return }
                Task {
                    if let movie = try? await item.loadTransferable(type: PickedMovie.self) { await useVideo(movie.url) }
                    videoItem = nil
                }
            }
            .onAppear { if defaultWeight > 0 { weight = defaultWeight.clean } }
        }
    }

    private func useVideo(_ url: URL) async {
        let asset = AVURLAsset(url: url)
        videoSeconds = ((try? await asset.load(.duration))?.seconds) ?? 0
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1200, height: 1200)
        if let cg = try? await gen.image(at: CMTime(seconds: min(0.5, videoSeconds / 2), preferredTimescale: 600)).image {
            image = UIImage(cgImage: cg)
        }
        videoURL = url
    }

    private func save() {
        saving = true
        let p = ProgressPhoto(date: date, pose: pose,
                              image: image.flatMap { ImageTools.jpeg($0, maxSide: 2000, quality: 0.85) },
                              thumbnail: image.flatMap { ImageTools.thumbnail($0) })
        if let videoURL, let data = try? Data(contentsOf: videoURL) {
            p.isVideo = true
            p.video = data
            p.durationSeconds = videoSeconds
        }
        p.weightKg = Double(weight.replacingOccurrences(of: ",", with: ".")) ?? 0
        p.note = note
        context.insert(p)
        try? context.save()
        Haptics.success()
        dismiss()
    }
}

/// A video picked from the photo library, copied to a temp file we own.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("picked-\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

/// Camera in video mode (front camera, medium quality, 30 s max — keeps iCloud storage small).
struct VideoCameraPicker: UIViewControllerRepresentable {
    let onFinish: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.mediaTypes = ["public.movie"]
        vc.cameraCaptureMode = .video
        vc.videoQuality = .typeMedium
        vc.videoMaximumDuration = 30
        if UIImagePickerController.isCameraDeviceAvailable(.front) { vc.cameraDevice = .front }
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (URL?) -> Void
        init(onFinish: @escaping (URL?) -> Void) { self.onFinish = onFinish }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.mediaURL] as? URL)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}

extension ProgressPhoto {
    /// Writes the video to a temp file for playback or sharing.
    func videoFileURL() -> URL? {
        guard isVideo, let video else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("progress", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("iLife-\(Int(date.timeIntervalSince1970)).mov")
        if !FileManager.default.fileExists(atPath: url.path) { try? video.write(to: url) }
        return url
    }

    func shareItem() -> Any? {
        if isVideo { return videoFileURL() }
        return image.flatMap(UIImage.init(data:))
    }
}

// MARK: - Detail

struct ProgressDetailView: View {
    @Bindable var photo: ProgressPhoto
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if photo.isVideo, let url = photo.videoFileURL() {
                        VideoPlayer(player: AVPlayer(url: url)).frame(height: 460).clipShape(RoundedRectangle(cornerRadius: 16))
                    } else if let d = photo.image, let img = UIImage(data: d) {
                        Image(uiImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(photo.date.formatted(date: .complete, time: .shortened)).font(.headline)
                        Picker("Pose", selection: $photo.pose) { ForEach(TransformationView.poses, id: \.self) { Text($0) } }
                            .pickerStyle(.segmented)
                        HStack {
                            Text("Weight")
                            Spacer()
                            TextField("kg", value: $photo.weightKg, format: .number).keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing).frame(width: 80)
                            Text("kg").foregroundStyle(.secondary)
                        }
                        TextField("Note", text: $photo.note, axis: .vertical)
                    }
                    .glassCard()
                }
                .padding()
            }
            .iLifeScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }
                    Button(role: .destructive) { context.delete(photo); dismiss() } label: { Image(systemName: "trash") }
                }
            }
            .sheet(isPresented: $showShare) { ShareSheet(items: [photo.shareItem()].compactMap { $0 }) }
        }
    }
}

// MARK: - Compare

struct CompareView: View {
    let before: ProgressPhoto
    let after: ProgressPhoto
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0     // 0 side-by-side, 1 slider
    @State private var split: CGFloat = 0.5
    @State private var shareImage: IdentImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("", selection: $mode) { Text("Side by side").tag(0); Text("Slider").tag(1) }.pickerStyle(.segmented)
                if mode == 0 {
                    SideBySide(before: before, after: after)
                } else {
                    slider
                }
                Spacer()
            }
            .padding()
            .background { WallpaperView() }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { shareImage = renderCard().map(IdentImage.init) } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
            .sheet(item: $shareImage) { ShareSheet(items: [$0.image]) }
        }
    }

    private var slider: some View {
        GeometryReader { geo in
            ZStack {
                photoView(after).frame(width: geo.size.width, height: geo.size.height).clipped()
                photoView(before).frame(width: geo.size.width, height: geo.size.height).clipped()
                    .mask(alignment: .leading) { Rectangle().frame(width: geo.size.width * split) }
                Rectangle().fill(.white).frame(width: 3).position(x: geo.size.width * split, y: geo.size.height / 2)
                Circle().fill(.white).frame(width: 34, height: 34)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.caption.bold()).foregroundStyle(.black))
                    .position(x: geo.size.width * split, y: geo.size.height / 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .gesture(DragGesture(minimumDistance: 0).onChanged { split = min(max($0.location.x / geo.size.width, 0), 1) })
            .overlay(alignment: .top) {
                HStack {
                    tag(before.date.formatted(date: .abbreviated, time: .omitted))
                    Spacer()
                    tag(after.date.formatted(date: .abbreviated, time: .omitted))
                }
                .padding(8)
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
    }

    private func photoView(_ p: ProgressPhoto) -> some View {
        Group {
            if let d = p.image, let img = UIImage(data: d) { Image(uiImage: img).resizable().scaledToFill() } else { Color.gray }
        }
    }

    private func tag(_ s: String) -> some View {
        Text(s).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4).background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
    }

    /// A clean shareable before/after card.
    @MainActor private func renderCard() -> UIImage? {
        let card = SideBySide(before: before, after: after, branded: true)
            .padding(20).frame(width: 1080 / 2)
            .background(LinearGradient(colors: [Color(red: 0.05, green: 0.15, blue: 0.3), Color(red: 0.05, green: 0.3, blue: 0.35)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: card)
        r.scale = 2
        return r.uiImage
    }
}

struct IdentImage: Identifiable {
    let id = UUID()
    let image: UIImage
    init(_ image: UIImage) { self.image = image }
}

struct SideBySide: View {
    let before: ProgressPhoto
    let after: ProgressPhoto
    var branded = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                column(before, title: "BEFORE")
                column(after, title: "AFTER")
            }
            let days = Calendar.current.dateComponents([.day], from: before.date, to: after.date).day ?? 0
            HStack {
                Text("\(days) days").font(.headline)
                Spacer()
                if before.weightKg > 0 && after.weightKg > 0 {
                    Text(String(format: "%+.1f kg", after.weightKg - before.weightKg)).font(.headline)
                        .foregroundStyle(after.weightKg <= before.weightKg ? .green : .orange)
                }
                if branded { Spacer(); Text("iLife").font(.headline.bold()).foregroundStyle(.cyan) }
            }
            .foregroundStyle(.white)
        }
    }

    private func column(_ p: ProgressPhoto, title: String) -> some View {
        VStack(spacing: 6) {
            Group {
                if let d = p.image, let img = UIImage(data: d) { Image(uiImage: img).resizable().scaledToFill() } else { Color.gray }
            }
            .frame(minWidth: 0, maxWidth: .infinity).aspectRatio(3 / 4, contentMode: .fit).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(title).font(.caption.bold()).foregroundStyle(.white.opacity(0.8))
            Text(p.date.formatted(date: .abbreviated, time: .omitted) + (p.weightKg > 0 ? " · \(p.weightKg.clean) kg" : ""))
                .font(.caption2).foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - Share sheet + daily reminder

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct DailyReminderToggle: View {
    @AppStorage("progressReminderOn") private var on = false
    @AppStorage("progressReminderMinutes") private var minutes = 7 * 60 + 30
    private let id = "ilife.progressPhoto.daily"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Daily photo reminder", isOn: $on)
            if on {
                DatePicker("Remind me at", selection: Binding(
                    get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now)! },
                    set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); minutes = (c.hour ?? 7) * 60 + (c.minute ?? 30) }),
                    displayedComponents: .hourAndMinute)
            }
        }
        .font(.subheadline)
        .onChange(of: on) { _, _ in schedule() }
        .onChange(of: minutes) { _, _ in schedule() }
    }

    private func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard on else { return }
        Task {
            await NotificationService.requestAuthorization()
            let c = UNMutableNotificationContent()
            c.title = "Transformation photo 📸"
            c.body = "Same spot, same pose — take today's progress photo."
            c.sound = .default
            var comps = DateComponents(); comps.hour = minutes / 60; comps.minute = minutes % 60
            try? await center.add(UNNotificationRequest(identifier: id, content: c,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
        }
    }
}
