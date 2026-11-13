import SwiftUI
import SwiftData
import UserNotifications

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
    @State private var shareItems: [UIImage] = []
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
                        .disabled(selected.count != 2)
                    Spacer()
                    Text("\(selected.count) selected").font(.caption)
                    Spacer()
                    Button("Share", systemImage: "square.and.arrow.up") {
                        shareItems = photos.filter { selected.contains($0.persistentModelID) }.sorted { $0.date < $1.date }
                            .compactMap { $0.image.flatMap(UIImage.init(data:)) }
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
        let first = sorted.first, last = sorted.last
        let days = first.map { Calendar.current.dateComponents([.day], from: $0.date, to: .now).day ?? 0 } ?? 0
        let w0 = sorted.first { $0.weightKg > 0 }?.weightKg ?? 0
        let w1 = sorted.last { $0.weightKg > 0 }?.weightKg ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                stat("\(photos.count)", "photos")
                Spacer()
                stat("\(streak)🔥", "day streak")
                Spacer()
                stat("\(days)", "days in")
                Spacer()
                stat(w0 > 0 && w1 > 0 ? String(format: "%+.1f", w1 - w0) : "–", "kg change")
            }
            HStack(spacing: 10) {
                Button { showCapture = true } label: {
                    Label(tookToday ? "Add another" : "Take today's photo", systemImage: "camera.fill").frame(maxWidth: .infinity)
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 360).frame(maxWidth: .infinity)
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button(image == nil ? "Open camera" : "Retake", systemImage: "camera.fill") { showCamera = true }
                    }
                    PhotoSourceButton(onPick: { image = $0 }) { Label("Choose from Library", systemImage: "photo.on.rectangle") }
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
                    Button("Save") {
                        guard let image else { return }
                        let p = ProgressPhoto(date: date, pose: pose, image: ImageTools.jpeg(image, maxSide: 2000, quality: 0.85),
                                              thumbnail: ImageTools.thumbnail(image))
                        p.weightKg = Double(weight.replacingOccurrences(of: ",", with: ".")) ?? 0
                        p.note = note
                        context.insert(p)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(image == nil)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(device: .front) { img in
                    showCamera = false
                    if let img { image = img }
                }
                .ignoresSafeArea()
            }
            .onAppear { if defaultWeight > 0 { weight = defaultWeight.clean } }
        }
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
                    if let d = photo.image, let img = UIImage(data: d) {
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
            .sheet(isPresented: $showShare) { ShareSheet(items: [photo.image.flatMap(UIImage.init(data:))].compactMap { $0 }) }
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
