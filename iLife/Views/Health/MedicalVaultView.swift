import SwiftUI
import SwiftData
import PhotosUI
import PDFKit
import QuickLook

struct MedicalVaultView: View {
    let kind: MedicalDocKind
    @Environment(\.modelContext) private var context
    @Query(sort: \MedicalDocument.date, order: .reverse) private var all: [MedicalDocument]
    @State private var showAdd = false
    @State private var previewURL: URL?

    private var docs: [MedicalDocument] { all.filter { $0.kind == kind } }

    var body: some View {
        List {
            if docs.isEmpty {
                ContentUnavailableView("No \(kind.rawValue.lowercased()) yet", systemImage: kind.icon,
                                       description: Text("Scan or upload documents. They sync to your private iCloud and stay behind Face ID."))
            }
            ForEach(docs) { d in
                Button { open(d) } label: {
                    HStack {
                        Image(systemName: d.fileType == "pdf" ? "doc.richtext.fill" : "photo.fill").foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(d.title).font(.headline)
                            Text([d.date.formatted(date: .abbreviated, time: .omitted), d.doctor].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { idx in idx.forEach { context.delete(docs[$0]) } }
        }
        .navigationTitle(kind.rawValue)
        .toolbar { Button("Add", systemImage: "plus") { showAdd = true } }
        .sheet(isPresented: $showAdd) { AddMedicalDocView(kind: kind) }
        .quickLookPreview($previewURL)
    }

    /// Write to a protected temp file for Quick Look; deleted on next open.
    private func open(_ d: MedicalDocument) {
        guard let data = d.file else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vault", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = d.title.replacingOccurrences(of: "/", with: "-")
        let url = dir.appendingPathComponent("\(safe.isEmpty ? "document" : safe).\(d.fileType)")
        try? data.write(to: url, options: .completeFileProtection)
        previewURL = url
    }
}

struct AddMedicalDocView: View {
    let kind: MedicalDocKind
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var doctor = ""
    @State private var notes = ""
    @State private var date = Date.now
    @State private var data: Data?
    @State private var fileType = "pdf"
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var photo: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title (e.g. Blood test – Lipid profile)", text: $title)
                    TextField("Doctor / Lab", text: $doctor)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                Section("File") {
                    if data != nil {
                        Label("\(fileType.uppercased()) attached", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    Button("Scan document", systemImage: "doc.viewfinder") { showCamera = true }
                    PhotosPicker(selection: $photo, matching: .images) { Label("Choose photo", systemImage: "photo") }
                    Button("Upload from Files", systemImage: "folder") { showFiles = true }
                }
            }
            .navigationTitle("Add \(kind.rawValue)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let doc = MedicalDocument(title: title.isEmpty ? kind.rawValue : title, kind: kind, date: date, fileType: fileType, file: data)
                        doc.doctor = doctor; doc.notes = notes
                        context.insert(doc)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(data == nil)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                DocumentScanner { pages in
                    showCamera = false
                    if !pages.isEmpty { data = Self.pdf(from: pages); fileType = "pdf" }
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image]) { res in
                guard case .success(let url) = res else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                data = try? Data(contentsOf: url)
                fileType = url.pathExtension.lowercased() == "pdf" ? "pdf" : "jpg"
                if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
            }
            .onChange(of: photo) { _, item in
                Task {
                    if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                        data = img.jpegData(compressionQuality: 0.8); fileType = "jpg"
                    }
                }
            }
        }
    }

    static func pdf(from pages: [UIImage]) -> Data? {
        let doc = PDFDocument()
        for (i, img) in pages.enumerated() { if let page = PDFPage(image: img) { doc.insert(page, at: i) } }
        return doc.dataRepresentation()
    }
}
