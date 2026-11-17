import SwiftUI
import SwiftData
import QuickLook
import VisionKit
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Keeping bills in Expenses

@MainActor
enum MedicalMoney {
    /// Creates or updates the Expense for a bill attachment; removes it when the amount is cleared.
    static func sync(_ a: MedicalAttachment, ownerTitle: String, in ctx: ModelContext) {
        let uid = a.uid
        let existing = (try? ctx.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.sourceUID == uid }))) ?? []
        guard a.kind == "Bill", a.amount > 0 else { existing.forEach { ctx.delete($0) }; return }
        let e = existing.first ?? Expense()
        if existing.isEmpty { ctx.insert(e) }
        e.sourceUID = uid
        e.category = .medical
        e.title = ownerTitle + (a.title.isEmpty ? "" : " — \(a.title)")
        e.amount = a.amount
        e.date = a.date
        e.vendor = ""
        e.notes = "From Medical (\(a.ownerKind))"
        e.bill = a.data
        e.billType = a.fileType
    }

    /// Deletes everything attached to a record, including the expenses made from its bills.
    static func deleteAttachments(owner uid: String, in ctx: ModelContext) {
        let atts = (try? ctx.fetch(FetchDescriptor<MedicalAttachment>(predicate: #Predicate { $0.ownerUID == uid }))) ?? []
        for a in atts {
            let aid = a.uid
            ((try? ctx.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.sourceUID == aid }))) ?? []).forEach { ctx.delete($0) }
            ctx.delete(a)
        }
    }

    /// Re-labels a record's expenses after it is renamed.
    static func retitle(owner uid: String, title: String, in ctx: ModelContext) {
        let atts = (try? ctx.fetch(FetchDescriptor<MedicalAttachment>(predicate: #Predicate { $0.ownerUID == uid }))) ?? []
        atts.filter { $0.kind == "Bill" }.forEach { sync($0, ownerTitle: title, in: ctx) }
    }
}

// MARK: - Attachments section used by all three editors

struct AttachmentsSection: View {
    let ownerUID: String
    let ownerKind: String
    let ownerTitle: String
    var kinds: [String] = ["Photo", "Prescription", "Report", "Bill", "Scan / X-ray", "Discharge summary", "Other"]
    var header = "Photos, reports & bills"
    @Environment(\.modelContext) private var context
    @Query private var all: [MedicalAttachment]
    @State private var adding: String?
    @State private var editing: MedicalAttachment?
    @State private var preview: URL?

    private var items: [MedicalAttachment] { all.filter { $0.ownerUID == ownerUID }.sorted { $0.date > $1.date } }
    private var billTotal: Double { items.filter { $0.kind == "Bill" }.reduce(0) { $0 + $1.amount } }

    var body: some View {
        Section {
            ForEach(items) { a in
                HStack(spacing: 12) {
                    Button { open(a) } label: { thumb(a) }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.title.isEmpty ? a.kind : a.title).font(.subheadline)
                        Text([a.kind, a.date.formatted(date: .abbreviated, time: .omitted)].joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if a.amount > 0 { Text(inr(a.amount)).font(.subheadline.bold()) }
                }
                .contentShape(Rectangle())
                .onTapGesture { editing = a }
                .swipeActions {
                    Button("Delete", role: .destructive) { delete(a) }
                }
            }
            Menu {
                ForEach(kinds, id: \.self) { k in
                    Button(k, systemImage: icon(k)) { adding = k }
                }
            } label: {
                Label("Add photo, report or bill", systemImage: "paperclip.badge.ellipsis")
            }
        } header: {
            Text(header)
        } footer: {
            if billTotal > 0 { Text("Bills total \(inr(billTotal)) — added to Expenses under Medical & Tests.") }
        }
        .sheet(item: Binding(get: { adding.map { KindBox(kind: $0) } }, set: { adding = $0?.kind })) { box in
            AttachmentEditor(attachment: nil, ownerUID: ownerUID, ownerKind: ownerKind, ownerTitle: ownerTitle, initialKind: box.kind)
        }
        .sheet(item: $editing) { AttachmentEditor(attachment: $0, ownerUID: ownerUID, ownerKind: ownerKind, ownerTitle: ownerTitle, initialKind: $0.kind) }
        .quickLookPreview($preview)
    }

    private struct KindBox: Identifiable { let kind: String; var id: String { kind } }

    func icon(_ k: String) -> String {
        switch k {
        case "Photo": "camera.fill"
        case "Prescription": "doc.text.fill"
        case "Report": "chart.bar.doc.horizontal.fill"
        case "Bill": "indianrupeesign.circle.fill"
        case "Scan / X-ray": "rays"
        case "Discharge summary": "doc.richtext.fill"
        default: "paperclip"
        }
    }

    @ViewBuilder private func thumb(_ a: MedicalAttachment) -> some View {
        if let d = a.thumbnail ?? (a.fileType == "jpg" ? a.data : nil), let img = UIImage(data: d) {
            Image(uiImage: img).resizable().scaledToFill().frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: a.fileType == "pdf" ? "doc.richtext.fill" : icon(a.kind)).font(.title3).foregroundStyle(.tint)
                .frame(width: 46, height: 46).background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func open(_ a: MedicalAttachment) {
        guard let data = a.data else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("medical", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(Exporter.safe(a.title.isEmpty ? a.kind : a.title) + "." + a.fileType)
        try? data.write(to: url, options: .completeFileProtection)
        preview = url
    }

    private func delete(_ a: MedicalAttachment) {
        let aid = a.uid
        ((try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.sourceUID == aid }))) ?? []).forEach { context.delete($0) }
        context.delete(a)
        try? context.save()
    }
}

struct AttachmentEditor: View {
    let attachment: MedicalAttachment?
    let ownerUID: String
    let ownerKind: String
    let ownerTitle: String
    let initialKind: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "Photo"
    @State private var title = ""
    @State private var date = Date.now
    @State private var amount = ""
    @State private var data: Data?
    @State private var thumb: Data?
    @State private var fileType = "jpg"
    @State private var showScan = false
    @State private var showFiles = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let thumb, let img = UIImage(data: thumb) {
                        Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 220).frame(maxWidth: .infinity)
                    } else if data != nil {
                        Label("\(fileType.uppercased()) attached", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    PhotoSourceButton(onPick: { img in
                        data = ImageTools.jpeg(img, maxSide: 2200, quality: 0.8); thumb = ImageTools.thumbnail(img); fileType = "jpg"
                    }) { Label(data == nil ? "Take or choose a photo" : "Replace with a photo", systemImage: "camera.fill") }
                    Button("Scan document", systemImage: "doc.viewfinder") { showScan = true }
                        .disabled(!VNDocumentCameraViewController.isSupported)
                    Button("Attach PDF or image from Files", systemImage: "folder") { showFiles = true }
                }
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(["Photo", "Prescription", "Report", "Bill", "Scan / X-ray", "Discharge summary", "Other"], id: \.self) { Text($0) }
                    }
                    TextField(kind == "Bill" ? "What for (e.g. Apollo Pharmacy, MRI)" : "Title (optional)", text: $title)
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    if kind == "Bill" {
                        HStack {
                            Text("Amount paid")
                            Spacer()
                            Text("₹").foregroundStyle(.secondary)
                            TextField("0", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110)
                        }
                    }
                } footer: {
                    if kind == "Bill" { Text("The amount is added to Expenses → Medical & Tests, with this bill attached.") }
                }
            }
            .navigationTitle(attachment == nil ? "Add \(initialKind)" : (attachment?.kind ?? "Attachment"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(data == nil && !(kind == "Bill" && (Double(amount) ?? 0) > 0))
                }
            }
            .onAppear {
                kind = initialKind
                if let a = attachment {
                    kind = a.kind; title = a.title; date = a.date; amount = a.amount > 0 ? a.amount.clean : ""
                    data = a.data; thumb = a.thumbnail; fileType = a.fileType
                }
            }
            .fullScreenCover(isPresented: $showScan) {
                DocumentScanner { pages in
                    showScan = false
                    if !pages.isEmpty {
                        data = AddMedicalDocView.pdf(from: pages); fileType = "pdf"; thumb = ImageTools.thumbnail(pages[0])
                    }
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image]) { res in
                guard case .success(let url) = res else { return }
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                guard let d = try? Data(contentsOf: url) else { return }
                if url.pathExtension.lowercased() == "pdf" {
                    data = d; fileType = "pdf"; thumb = nil
                } else if let img = UIImage(data: d) {
                    data = ImageTools.jpeg(img, maxSide: 2200, quality: 0.8); thumb = ImageTools.thumbnail(img); fileType = "jpg"
                }
                if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
            }
        }
    }

    private func save() {
        let a = attachment ?? MedicalAttachment(ownerUID: ownerUID, ownerKind: ownerKind, kind: kind)
        if attachment == nil { context.insert(a) }
        a.kind = kind; a.title = title; a.date = date
        a.amount = kind == "Bill" ? (Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0) : 0
        a.data = data; a.thumbnail = thumb; a.fileType = fileType
        MedicalMoney.sync(a, ownerTitle: ownerTitle.isEmpty ? ownerKind.capitalized : ownerTitle, in: context)
        try? context.save()
        Haptics.success()
        dismiss()
    }
}

// MARK: - Medicine reminders

enum MedicationReminders {
    private static func ids(for uid: String) -> [String] {
        var out: [String] = []
        for slot in DoseSlot.allCases { for day in 0...7 { out.append("medicine.\(uid).\(slot.order).\(day)") } }
        return out
    }

    static func cancel(_ uid: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids(for: uid))
    }

    static func schedule(_ m: Medication) {
        cancel(m.uid)
        guard m.remind, m.isCurrent else { return }
        let center = UNUserNotificationCenter.current()
        let days = m.weekdays.isEmpty || m.weekdays.count == 7 ? [0] : m.weekdays
        for slot in m.doseSlots {
            let c = UNMutableNotificationContent()
            c.title = "💊 \(m.displayName)\(m.dose.isEmpty ? "" : " · \(m.dose)")"
            c.body = "\(slot.rawValue)\(m.instructions.isEmpty ? "" : " — \(m.instructions)"). Tick it off in iLife."
            c.sound = .default
            for day in days {
                var comps = DateComponents()
                comps.hour = slot.time.hour; comps.minute = slot.time.minute
                if day > 0 { comps.weekday = day }
                center.add(UNNotificationRequest(identifier: "medicine.\(m.uid).\(slot.order).\(day)", content: c,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
            }
        }
    }

    static func syncAll(_ all: [Medication]) {
        for m in all { if m.remind && m.isCurrent { schedule(m) } else { cancel(m.uid) } }
    }
}

/// Small coloured status chip.
struct StatusChip: View {
    let text: String
    var color: Color {
        switch text {
        case "Healed", "Recovered": .green
        case "Recovering", "Monitoring": .yellow
        case "Severe": .red
        case "Moderate", "Under treatment", "Active": .orange
        case "Ongoing / chronic": .purple
        default: .gray
        }
    }
    var body: some View {
        Text(text).font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.25), in: Capsule()).foregroundStyle(color)
    }
}
