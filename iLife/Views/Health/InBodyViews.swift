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

    // AI reading
    @ObservedObject private var ai = AIService.shared
    @State private var extra: InBodyAIResult?
    @State private var aiReading = false
    @State private var aiError: String?

    var body: some View {
        NavigationStack {
            Form {
                if result == nil && !isReading {
                    Section {
                        Text("Use the camera to scan your InBody result sheet, or upload a photo or the PDF the InBody app emails you. \(ai.hasKey ? "AI reads every value on the sheet and explains the result." : "Numbers are read on your device; turn on AI (More → AI Assistant) for a fuller, more accurate reading.")")
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
                    Section {
                        if aiReading {
                            HStack { ProgressView(); Text("AI is reading the full sheet…").font(.callout) }
                        } else if extra != nil {
                            Label("Read by AI — values below were updated", systemImage: "sparkles").foregroundStyle(.green).font(.callout)
                        } else if let aiError {
                            Label(aiError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                            Button("Try AI again") { Task { await readWithAI() } }
                        } else if !ai.hasKey {
                            NavigationLink { AISettingsView() } label: {
                                Label("Turn on AI for a more accurate, complete reading", systemImage: "sparkles").font(.callout)
                            }
                        }
                        if let s = extra?.summary, !s.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("What this means").font(.caption.bold())
                                Text(s).font(.callout)
                            }
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
                    if let x = extra {
                        Section("More from the sheet") {
                            more("Protein", x.proteinKg, "kg"); more("Minerals", x.mineralKg, "kg"); more("Fat-Free Mass", x.fatFreeMassKg, "kg")
                            more("Waist-Hip Ratio", x.waistHipRatio, ""); more("Target Weight", x.targetWeightKg, "kg")
                            more("Weight Control", x.weightControlKg, "kg", signed: true); more("Fat Control", x.fatControlKg, "kg", signed: true)
                            more("Muscle Control", x.muscleControlKg, "kg", signed: true)
                            more("Right Arm (lean)", x.rightArmKg, "kg"); more("Left Arm (lean)", x.leftArmKg, "kg"); more("Trunk (lean)", x.trunkKg, "kg")
                            more("Right Leg (lean)", x.rightLegKg, "kg"); more("Left Leg (lean)", x.leftLegKg, "kg")
                        }
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

    @ViewBuilder
    private func more(_ title: String, _ value: Double?, _ unit: String, signed: Bool = false) -> some View {
        if let value {
            HStack {
                Text(title)
                Spacer()
                Text((signed ? String(format: "%+.1f", value) : value.clean) + (unit.isEmpty ? "" : " \(unit)")).foregroundStyle(.secondary)
            }
        }
    }

    private func readWithAI() async {
        guard ai.hasKey, !images.isEmpty else { return }
        aiReading = true; aiError = nil
        do {
            let x = try await ai.readInBody(images)
            func put(_ v: Double?, _ target: inout String) { if let v, v > 0 { target = v.clean } }
            put(x.weightKg, &weight); put(x.skeletalMuscleKg, &muscle); put(x.bodyFatKg, &fatKg); put(x.bodyFatPercent, &fatPct)
            put(x.bmi, &bmi); put(x.totalBodyWaterL, &water); put(x.visceralFatLevel, &visceral); put(x.bmrKcal, &bmr); put(x.inBodyScore, &score)
            if let ds = x.testDate {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
                if let d = f.date(from: ds), d <= .now { date = d }
            }
            extra = x
            Haptics.success()
        } catch {
            aiError = error.localizedDescription
        }
        aiReading = false
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
        await readWithAI()
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
        scan.image = images.first.flatMap { ImageTools.jpeg($0, maxSide: 2000, quality: 0.75) }
        if let x = extra {
            scan.proteinKg = x.proteinKg ?? 0; scan.mineralKg = x.mineralKg ?? 0; scan.fatFreeMassKg = x.fatFreeMassKg ?? 0
            scan.waistHipRatio = x.waistHipRatio ?? 0; scan.targetWeightKg = x.targetWeightKg ?? 0
            scan.weightControlKg = x.weightControlKg ?? 0; scan.fatControlKg = x.fatControlKg ?? 0; scan.muscleControlKg = x.muscleControlKg ?? 0
            scan.rightArmKg = x.rightArmKg ?? 0; scan.leftArmKg = x.leftArmKg ?? 0; scan.trunkKg = x.trunkKg ?? 0
            scan.rightLegKg = x.rightLegKg ?? 0; scan.leftLegKg = x.leftLegKg ?? 0
            scan.aiSummary = x.summary ?? ""
            scan.readBy = "AI"
        }
        context.insert(scan)
        try? context.save()
        if saveToHealth { Task { await HealthKitManager.shared.saveInBody(scan) } }
        Celebration.shared.fire("InBody saved", subtitle: scan.readBy == "AI" ? "Read by AI and added to your trend" : "Added to your trend", icon: "doc.viewfinder")
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
            if !scan.aiSummary.isEmpty {
                Section("What this means") { Text(scan.aiSummary).font(.callout) }
            }
            if scan.readBy == "AI" {
                Section("More from the sheet") {
                    row("Protein", scan.proteinKg, "kg"); row("Minerals", scan.mineralKg, "kg"); row("Fat-Free Mass", scan.fatFreeMassKg, "kg")
                    row("Waist-Hip Ratio", scan.waistHipRatio, ""); row("Target Weight", scan.targetWeightKg, "kg")
                    signed("Weight Control", scan.weightControlKg); signed("Fat Control", scan.fatControlKg); signed("Muscle Control", scan.muscleControlKg)
                }
                Section("Lean mass by segment") {
                    row("Right Arm", scan.rightArmKg, "kg"); row("Left Arm", scan.leftArmKg, "kg"); row("Trunk", scan.trunkKg, "kg")
                    row("Right Leg", scan.rightLegKg, "kg"); row("Left Leg", scan.leftLegKg, "kg")
                }
            }
        }
        .navigationTitle(scan.date.formatted(date: .abbreviated, time: .omitted))
    }
    private func row(_ t: String, _ v: Double, _ u: String) -> some View {
        HStack { Text(t); Spacer(); Text(v > 0 ? "\(v.clean) \(u)" : "–").foregroundStyle(.secondary) }
    }
    private func signed(_ t: String, _ v: Double) -> some View {
        HStack { Text(t); Spacer(); Text(v == 0 ? "0 kg" : String(format: "%+.1f kg", v)).foregroundStyle(.secondary) }
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
