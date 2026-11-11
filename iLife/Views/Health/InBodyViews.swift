import SwiftUI
import SwiftData
import PhotosUI
import VisionKit
import UniformTypeIdentifiers

/// Scan or upload an InBody sheet → OCR → review → save.
struct InBodyImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showCamera = false
    @State private var showFiles = false
    @State private var photoItem: PhotosPickerItem?
    @State private var images: [UIImage] = []
    @State private var isReading = false
    @State private var result: InBodyResult?

    // editable fields
    @State private var date = Date.now
    @State private var weight = ""
    @State private var muscle = ""
    @State private var fatKg = ""
    @State private var fatPct = ""
    @State private var bmi = ""
    @State private var water = ""
    @State private var visceral = ""
    @State private var bmr = ""
    @State private var score = ""
    @State private var saveToHealth = true

    var body: some View {
        NavigationStack {
            Form {
                if result == nil && !isReading {
                    Section {
                        Text("Use the camera to scan your InBody result sheet, or upload a photo or the PDF the InBody app emails you. Numbers are read on your device.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Section("Source") {
                        Button("Scan with camera", systemImage: "doc.viewfinder") { showCamera = true }
                            .disabled(!VNDocumentCameraViewController.isSupported)
                        PhotosPicker(selection: $photoItem, matching: .images) { Label("Choose from Photos", systemImage: "photo") }
                        Button("Upload PDF or image from Files", systemImage: "folder") { showFiles = true }
                    }
                }
                if isReading {
                    Section { HStack { ProgressView(); Text("Reading your InBody report…") } }
                }
                if let result {
                    Section {
                        Label("Found \(result.foundCount) values — check them against your sheet and correct anything that's off.",
                              systemImage: result.foundCount >= 3 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(result.foundCount >= 3 ? .green : .orange)
                        if let img = images.first {
                            Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    Section("Test") {
                        DatePicker("Test date", selection: $date, displayedComponents: .date)
                    }
                    Section("Body composition") {
                        field("Weight", $weight, "kg")
                        field("Skeletal Muscle Mass", $muscle, "kg")
                        field("Body Fat Mass", $fatKg, "kg")
                        field("Percent Body Fat", $fatPct, "%")
                        field("BMI", $bmi, "")
                        field("Total Body Water", $water, "L")
                        field("Visceral Fat Level", $visceral, "")
                        field("Basal Metabolic Rate", $bmr, "kcal")
                        field("InBody Score", $score, "/100")
                    }
                    Section {
                        Toggle("Also save weight & body fat to Apple Health", isOn: $saveToHealth)
                    }
                }
            }
            .navigationTitle("InBody Scan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if result != nil {
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(Double(weight) == nil) }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                DocumentScanner { pages in showCamera = false; Task { await read(pages) } }
                    .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image]) { res in
                guard case .success(let url) = res else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return }
                let pages = url.pathExtension.lowercased() == "pdf" ? InBodyScanner.images(fromPDF: data) : [UIImage(data: data)].compactMap { $0 }
                Task { await read(pages) }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        await read([img])
                    }
                }
            }
        }
    }

    private func field(_ title: String, _ value: Binding<String>, _ unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("–", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            Text(unit).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
        }
    }

    private func read(_ pages: [UIImage]) async {
        guard !pages.isEmpty else { return }
        images = pages
        isReading = true
        let r = await InBodyScanner.scan(pages)
        func s(_ v: Double?) -> String { v.map { $0.clean } ?? "" }
        weight = s(r.weightKg); muscle = s(r.skeletalMuscleKg); fatKg = s(r.bodyFatKg); fatPct = s(r.bodyFatPercent)
        bmi = s(r.bmi); water = s(r.totalBodyWaterL); visceral = s(r.visceralFatLevel); bmr = s(r.bmrKcal); score = s(r.inBodyScore)
        if let d = r.testDate { date = d }
        result = r
        isReading = false
    }

    private func save() {
        let scan = InBodyScan(date: date)
        scan.weightKg = Double(weight) ?? 0
        scan.skeletalMuscleKg = Double(muscle) ?? 0
        scan.bodyFatKg = Double(fatKg) ?? 0
        scan.bodyFatPercent = Double(fatPct) ?? 0
        scan.bmi = Double(bmi) ?? 0
        scan.totalBodyWaterL = Double(water) ?? 0
        scan.visceralFatLevel = Double(visceral) ?? 0
        scan.bmrKcal = Double(bmr) ?? 0
        scan.inBodyScore = Double(score) ?? 0
        scan.image = images.first?.jpegData(compressionQuality: 0.7)
        context.insert(scan)
        try? context.save()
        if saveToHealth { Task { await HealthKitManager.shared.saveInBody(scan) } }
        dismiss()
    }
}

struct InBodyListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \InBodyScan.date, order: .reverse) private var scans: [InBodyScan]
    var body: some View {
        List {
            ForEach(scans) { s in
                NavigationLink { InBodyDetailView(scan: s) } label: {
                    VStack(alignment: .leading) {
                        Text(s.date.formatted(date: .long, time: .omitted)).font(.headline)
                        Text("\(s.weightKg.clean) kg · Muscle \(s.skeletalMuscleKg.clean) kg · Fat \(s.bodyFatPercent.clean)%")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { idx in idx.forEach { context.delete(scans[$0]) } }
        }
        .navigationTitle("InBody History")
    }
}

struct InBodyDetailView: View {
    let scan: InBodyScan
    var body: some View {
        List {
            if let data = scan.image, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFit()
            }
            row("Weight", scan.weightKg, "kg"); row("Skeletal Muscle Mass", scan.skeletalMuscleKg, "kg")
            row("Body Fat Mass", scan.bodyFatKg, "kg"); row("Percent Body Fat", scan.bodyFatPercent, "%")
            row("BMI", scan.bmi, ""); row("Total Body Water", scan.totalBodyWaterL, "L")
            row("Visceral Fat Level", scan.visceralFatLevel, ""); row("BMR", scan.bmrKcal, "kcal")
            row("InBody Score", scan.inBodyScore, "")
        }
        .navigationTitle(scan.date.formatted(date: .abbreviated, time: .omitted))
    }
    private func row(_ t: String, _ v: Double, _ u: String) -> some View {
        HStack { Text(t); Spacer(); Text(v > 0 ? "\(v.clean) \(u)" : "–").foregroundStyle(.secondary) }
    }
}

/// VisionKit document camera (auto edge detection, perspective correction).
struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish([]) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish([]) }
    }
}
