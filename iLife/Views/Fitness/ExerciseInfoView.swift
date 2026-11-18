import SwiftUI
import SwiftData
import AVKit
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

/// Everything you've saved for one exercise: your photo, an explainer video or GIF, the equipment photo,
/// a link and your own form cues. Added once, shown wherever the exercise appears.
struct ExerciseInfoView: View {
    let name: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [ExerciseMedia]
    @State private var showVideoCamera = false
    @State private var videoItem: PhotosPickerItem?
    @State private var gifItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var link = ""
    @State private var cues = ""
    @State private var busy = false
    @State private var problem: String?

    private var key: String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var media: ExerciseMedia? { all.first { $0.key == key } }
    private var lib: LibraryExercise? { ExerciseLibrary.find(name) }

    private func ensure() -> ExerciseMedia {
        if let m = media { return m }
        let m = ExerciseMedia(key: key)
        context.insert(m)
        return m
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        SavedPhotoButton(kind: "exercise", name: name, equipment: lib?.equipment ?? "", size: 76)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name).font(.headline)
                            if let lib { Text([lib.muscle, lib.equipment.isEmpty ? "Bodyweight" : lib.equipment].joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                            Text("Tap the picture to set the exercise photo.").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    if let m = media, let data = m.video {
                        if m.videoType == "gif" {
                            AnimatedGIFView(data: data).frame(height: 260).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
                        } else if let url = m.videoFileURL() {
                            VideoPlayer(player: AVPlayer(url: url)).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Button("Remove video / GIF", role: .destructive) { m.video = nil; m.videoType = ""; try? context.save() }
                    } else {
                        Text("No explainer yet. Add a short video of the movement, or a GIF.").font(.caption).foregroundStyle(.secondary)
                    }
                    if busy { HStack { ProgressView(); Text("Saving…").font(.caption) } }
                    if let problem { Text(problem).font(.caption).foregroundStyle(.orange) }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Record a video (up to 30 s)", systemImage: "video.fill") { Presenter.videoCamera(front: false) { store(fileAt: $0) } }
                    }
                    PhotosPicker(selection: $videoItem, matching: .videos) { Label("Choose a video from Photos", systemImage: "film") }
                    PhotosPicker(selection: $gifItem, matching: .images) { Label("Choose a GIF from Photos", systemImage: "photo.stack") }
                    Button("Import video or GIF from Files", systemImage: "folder") { Presenter.file(types: [.movie, .gif]) { store(fileAt: $0) } }
                } header: {
                    Text("Explainer video or GIF")
                } footer: {
                    Text("Keep videos short — they're stored on this device. For long tutorials, paste a link below instead.")
                }

                Section("Equipment photo") {
                    if let data = media?.equipmentPhoto, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 220).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
                        Button("Remove equipment photo", role: .destructive) { media?.equipmentPhoto = nil; try? context.save() }
                    }
                    PhotoSourceButton(onPick: { img in
                        let m = ensure(); m.equipmentPhoto = ImageTools.jpeg(img, maxSide: 1400); m.updated = .now; try? context.save()
                    }) {
                        Label(media?.equipmentPhoto == nil ? "Add a photo of the machine / equipment" : "Change equipment photo", systemImage: "camera.fill")
                    }
                }

                Section("Tutorial link") {
                    TextField("Paste a YouTube or web link", text: $link)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if let url = URL(string: link.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true {
                        Link(destination: url) { Label("Open link", systemImage: "play.rectangle.fill") }
                    }
                }

                Section("My form cues") {
                    TextField("e.g. Seat height 4, elbows tucked, slow on the way down", text: $cues, axis: .vertical).lineLimit(2...6)
                }
            }
            .navigationTitle("Exercise Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { saveText(); dismiss() } } }
            .onFirstAppear { link = media?.link ?? ""; cues = media?.cues ?? "" }
            .onChange(of: videoItem) { _, item in
                guard let item else { return }
                busy = true
                Task {
                    if let movie = try? await item.loadTransferable(type: PickedMovie.self) { store(fileAt: movie.url) } else { problem = "Couldn't read that video."; busy = false }
                    videoItem = nil
                }
            }
            .onChange(of: gifItem) { _, item in
                guard let item else { return }
                busy = true
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        if data.starts(with: [0x47, 0x49, 0x46]) { store(data: data, type: "gif") }
                        else { problem = "That picture isn't a GIF. Use the photo at the top for a still picture."; busy = false }
                    } else { busy = false }
                    gifItem = nil
                }
            }
        }
    }

    private func store(fileAt url: URL) {
        guard let data = try? Data(contentsOf: url) else { problem = "Couldn't read that file."; busy = false; return }
        let ext = url.pathExtension.lowercased()
        store(data: data, type: ext == "gif" ? "gif" : (ext == "mp4" || ext == "m4v" ? "mp4" : "mov"))
    }

    private func store(data: Data, type: String) {
        problem = data.count > 80_000_000 ? "That file is large (\(data.count / 1_000_000) MB) — it will use a lot of storage. A shorter clip is better." : nil
        let m = ensure()
        m.video = data; m.videoType = type; m.updated = .now
        try? context.save()
        busy = false
        Haptics.success()
    }

    private func saveText() {
        let l = link.trimmingCharacters(in: .whitespaces), c = cues.trimmingCharacters(in: .whitespacesAndNewlines)
        if media == nil && l.isEmpty && c.isEmpty { return }
        let m = ensure()
        m.link = l; m.cues = c
        try? context.save()
    }
}

extension ExerciseMedia {
    /// Writes the video to a temp file for the player.
    func videoFileURL() -> URL? {
        guard let video, videoType != "gif", !videoType.isEmpty else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("exercise-media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = key.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "_")
        let url = dir.appendingPathComponent("\(safe)-\(Int(updated.timeIntervalSince1970)).\(videoType)")
        if !FileManager.default.fileExists(atPath: url.path) { try? video.write(to: url) }
        return url
    }
}

/// Plays an animated GIF.
struct AnimatedGIFView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.clipsToBounds = true
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        v.image = Self.animated(from: data)
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {}

    static func animated(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(data: data) }
        var frames: [UIImage] = []
        var duration = 0.0
        let step = max(1, count / 120)          // cap memory on very long GIFs
        for i in stride(from: 0, to: count, by: step) {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            duration += max(d, 0.02) * Double(step)
        }
        return UIImage.animatedImage(with: frames, duration: duration)
    }
}

/// Small button that opens the guide for an exercise; shows a play icon once a video/GIF is saved.
struct ExerciseGuideButton: View {
    let name: String
    var labelled = false
    @Query private var all: [ExerciseMedia]
    @State private var show = false

    private var media: ExerciseMedia? {
        let k = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.first { $0.key == k }
    }

    var body: some View {
        let has = media.map { !$0.videoType.isEmpty || !$0.link.isEmpty } ?? false
        Button { show = true } label: {
            if labelled {
                Label(has ? "How to do it" : "Add guide", systemImage: has ? "play.circle.fill" : "plus.circle")
            } else {
                Image(systemName: has ? "play.circle.fill" : "info.circle").font(.title3)
            }
        }
        .buttonStyle(.borderless)
        .sheet(isPresented: $show) { ExerciseInfoView(name: name) }
    }
}
