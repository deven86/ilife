import SwiftUI
import SwiftData
import Charts

struct HealthHubView: View {
    @Query(sort: \InBodyScan.date, order: .reverse) private var scans: [InBodyScan]
    @Query private var docs: [MedicalDocument]
    @Query private var contacts: [EmergencyContact]
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var progress: [ProgressPhoto]
    @State private var showImport = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TransformationCard(photos: progress)
                inBodyCard
                if scans.count > 1 { trendCard }
                NavigationLink { InBodyListView() } label: {
                    Label("All InBody results (\(scans.count))", systemImage: "list.bullet.rectangle").frame(maxWidth: .infinity, alignment: .leading)
                }
                .glassCard(cornerRadius: 16, padding: 14)

                vaultCard
                emergencyCard
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Health")
        .sheet(isPresented: $showImport) { InBodyImportView() }
    }

    private var inBodyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("InBody Scan Result").font(.headline)
                Spacer()
                Button { showImport = true } label: { Label("Scan / Upload", systemImage: "doc.viewfinder") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            if let s = scans.first {
                Text(s.date.formatted(date: .long, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        stat("Weight", s.weightKg, "kg", previous: scans.dropFirst().first?.weightKg, lowerIsBetter: true)
                        stat("Skeletal Muscle", s.skeletalMuscleKg, "kg", previous: scans.dropFirst().first?.skeletalMuscleKg, lowerIsBetter: false)
                        stat("Body Fat", s.bodyFatPercent, "%", previous: scans.dropFirst().first?.bodyFatPercent, lowerIsBetter: true)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        if s.inBodyScore > 0 { stat("InBody Score", s.inBodyScore, "", previous: nil, lowerIsBetter: false) }
                        if s.bmi > 0 { stat("BMI", s.bmi, "", previous: nil, lowerIsBetter: true) }
                        if s.visceralFatLevel > 0 { stat("Visceral Fat", s.visceralFatLevel, "lvl", previous: nil, lowerIsBetter: true) }
                    }
                    Image(systemName: "figure.stand").font(.system(size: 80, weight: .ultraLight)).foregroundStyle(.cyan.opacity(0.7))
                }
            } else {
                Text("Scan your InBody result sheet or upload the PDF. iLife reads the numbers automatically and tracks every test over time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    private func stat(_ title: String, _ v: Double, _ unit: String, previous: Double?, lowerIsBetter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(v.clean).font(.title3.bold())
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            if let prev = previous, prev > 0, v > 0, prev != v {
                let diff = v - prev
                let good = lowerIsBetter ? diff < 0 : diff > 0
                Text("\(diff > 0 ? "↑" : "↓") \(abs(diff).clean)").font(.caption2.bold()).foregroundStyle(good ? .green : .orange)
            }
        }
    }

    private var trendCard: some View {
        let points = scans.reversed()
        return VStack(alignment: .leading) {
            SectionTitle(title: "Body Composition Trend", trailing: "\(scans.count) tests")
            Chart {
                ForEach(Array(points)) { s in
                    if s.weightKg > 0 {
                        LineMark(x: .value("Date", s.date), y: .value("kg", s.weightKg), series: .value("Metric", "Weight"))
                            .foregroundStyle(.cyan).symbol(.circle).interpolationMethod(.catmullRom)
                    }
                    if s.skeletalMuscleKg > 0 {
                        LineMark(x: .value("Date", s.date), y: .value("kg", s.skeletalMuscleKg), series: .value("Metric", "Muscle"))
                            .foregroundStyle(.green).symbol(.square).interpolationMethod(.catmullRom)
                    }
                    if s.bodyFatKg > 0 {
                        LineMark(x: .value("Date", s.date), y: .value("kg", s.bodyFatKg), series: .value("Metric", "Fat"))
                            .foregroundStyle(.orange).symbol(.triangle).interpolationMethod(.catmullRom)
                    }
                }
            }
            .frame(height: 180)
            HStack(spacing: 14) {
                Label("Weight", systemImage: "circle.fill").foregroundStyle(.cyan)
                Label("Muscle", systemImage: "square.fill").foregroundStyle(.green)
                Label("Fat", systemImage: "triangle.fill").foregroundStyle(.orange)
            }
            .font(.caption2)
        }
        .glassCard()
    }

    private var vaultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Medical Vault", trailing: "Face ID protected")
            HStack {
                ForEach(MedicalDocKind.allCases) { kind in
                    NavigationLink { MedicalVaultView(kind: kind) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: kind.icon).font(.title2).foregroundStyle(.tint)
                            Text(kind.rawValue).font(.caption2).multilineTextAlignment(.center).lineLimit(2)
                            Text("(\(docs.filter { $0.kind == kind }.count))").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .glassCard()
    }

    private var emergencyCard: some View {
        NavigationLink { EmergencyView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "cross.case.fill").font(.title).foregroundStyle(.white)
                    .frame(width: 50, height: 50).background(.red, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading) {
                    Text("Emergency Contact & Medical ID").font(.headline)
                    if let c = contacts.first(where: \.isPrimary) ?? contacts.first {
                        Text("\(c.name) · \(c.phone)").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Add who to call in an emergency").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .glassCard()
    }
}
