import SwiftUI
import SwiftData
import HealthKit

// MARK: - Loading a day's report

@MainActor
enum ReportBuilder {
    static func day(_ day: Date, context ctx: ModelContext) async -> DayReportData {
        let cal = Calendar.current
        let d0 = cal.startOfDay(for: day)
        let (_, stats) = await AIContext.build(day: d0, context: ctx, health: HealthKitManager.shared)
        let foods = ((try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? []).filter { cal.isDate($0.date, inSameDayAs: d0) }.sorted { $0.date < $1.date }
        let logs = ((try? ctx.fetch(FetchDescriptor<WorkoutLog>())) ?? []).filter { cal.isDate($0.start, inSameDayAs: d0) }.sorted { $0.start < $1.start }
        let meds = ((try? ctx.fetch(FetchDescriptor<MeditationLog>())) ?? []).filter { cal.isDate($0.date, inSameDayAs: d0) }
        let doses = ((try? ctx.fetch(FetchDescriptor<SupplementDose>())) ?? []).filter { cal.isDate($0.day, inSameDayAs: d0) }
        let sups = ((try? ctx.fetch(FetchDescriptor<Supplement>())) ?? []).filter { $0.isDue(on: d0) }
            .map { s in (name: s.name, taken: doses.filter { $0.supplementUID == s.uid }.count, planned: s.doseSlots.count) }
        let trainers = (try? ctx.fetch(FetchDescriptor<Trainer>())) ?? []
        let reviews = ((try? ctx.fetch(FetchDescriptor<DailyReview>())) ?? []).filter { $0.kind == "night" && cal.isDate($0.day, inSameDayAs: d0) }
        let review = reviews.max { $0.createdAt < $1.createdAt }.flatMap { try? JSONDecoder().decode(NightReview.self, from: Data($0.payload.utf8)) }
        var data = DayReportData(day: d0, stats: stats, foods: foods, logs: logs, meditations: meds, supplements: sups, review: review)
        data.trainerNames = Dictionary(trainers.map { ($0.uid, $0.fullName) }, uniquingKeysWith: { a, _ in a })
        return data
    }
}

// MARK: - Daily report screen

struct DailyReportView: View {
    @Environment(\.modelContext) private var context
    @State private var day = Date.now
    @State private var data: DayReportData?
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                DatePicker("Day", selection: $day, in: ...Date.now, displayedComponents: .date)
                    .glassCard(cornerRadius: 16, padding: 12)
                if loading { ProgressView().padding() }
                if let data {
                    DailyReportCard(data: data)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                }
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Daily Report")
        .toolbar {
            if let data {
                ShareMenuButton(name: "iLife report \(data.day.formatted(date: .numeric, time: .omitted))", text: { data.text }) { DailyReportCard(data: data) }
            }
        }
        .task(id: Calendar.current.startOfDay(for: day)) {
            loading = true
            data = await ReportBuilder.day(day, context: context)
            loading = false
        }
    }
}

// MARK: - Range report (PDF)

struct RangeReport {
    var from: Date
    var to: Date
    var steps: [DayValue] = []
    var active: [DayValue] = []
    var sleep: [DayValue] = []
    var kcal: [DayValue] = []
    var protein: [DayValue] = []
    var workoutMin: [DayValue] = []
    var meditationMin: [DayValue] = []
    var weight: [DayValue] = []
    var workouts: [WorkoutLog] = []
    var ptDays = 0
    var mindfulTotal = 0.0
    var doseTaken = 0, dosePlanned = 0
    var kcalGoal = 0.0, proteinGoal = 0.0, stepGoal = 0.0
}

struct RangeReportCard: View {
    let r: RangeReport
    private func avg(_ v: [DayValue]) -> Double { v.isEmpty ? 0 : v.map(\.value).reduce(0, +) / Double(v.count) }

    var body: some View {
        ShareFrame(title: "Health Report", subtitle: "\(r.from.formatted(date: .abbreviated, time: .omitted)) – \(r.to.formatted(date: .abbreviated, time: .omitted))") {
            VStack(spacing: 10) {
                HStack {
                    ShareStat(value: Int(avg(r.steps)).formatted(), label: "avg steps", color: .cyan)
                    ShareStat(value: "\(Int(avg(r.active)))", label: "avg active kcal", color: .orange)
                    ShareStat(value: String(format: "%.1f h", avg(r.sleep)), label: "avg sleep", color: .indigo)
                }
                HStack {
                    ShareStat(value: "\(r.workouts.count)", label: "workouts", color: .green)
                    ShareStat(value: "\(Int(r.workouts.reduce(0) { $0 + $1.durationMinutes }))", label: "training min", color: .green)
                    ShareStat(value: "\(r.ptDays)", label: "PT days", color: .orange)
                }
                HStack {
                    ShareStat(value: "\(Int(avg(r.kcal)))", label: "avg kcal eaten", color: .red)
                    ShareStat(value: "\(Int(avg(r.protein))) g", label: "avg protein", color: .yellow)
                    ShareStat(value: "\(Int(r.mindfulTotal))", label: "mindful min", color: .mint)
                }
                if r.dosePlanned > 0 || r.weight.count >= 2 {
                    HStack {
                        if r.dosePlanned > 0 { ShareStat(value: "\(Int(Double(r.doseTaken) / Double(r.dosePlanned) * 100))%", label: "supplement doses taken", color: .teal) }
                        if let a = r.weight.first?.value, let b = r.weight.last?.value, r.weight.count >= 2 {
                            ShareStat(value: String(format: "%+.1f kg", b - a), label: "weight change", color: .purple)
                        }
                    }
                }
            }
            .shareBox()
            if !r.weight.isEmpty { ShareChart(title: "Weight (kg)", points: r.weight, color: .purple, line: true) }
            if !r.steps.isEmpty { ShareChart(title: "Steps", points: r.steps, color: .cyan, goal: r.stepGoal) }
            if !r.active.isEmpty { ShareChart(title: "Active energy (kcal)", points: r.active, color: .orange) }
            if !r.sleep.isEmpty { ShareChart(title: "Sleep (h)", points: r.sleep, color: .indigo, goal: 8) }
            if !r.kcal.isEmpty { ShareChart(title: "Calories eaten", points: r.kcal, color: .red, goal: r.kcalGoal) }
            if !r.protein.isEmpty { ShareChart(title: "Protein (g)", points: r.protein, color: .yellow, goal: r.proteinGoal) }
            if !r.workoutMin.isEmpty { ShareChart(title: "Workout minutes", points: r.workoutMin, color: .green) }
            if !r.meditationMin.isEmpty { ShareChart(title: "Mindful minutes", points: r.meditationMin, color: .mint) }
            if !r.workouts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workouts").font(.headline)
                    ForEach(r.workouts.prefix(40)) { w in
                        Text("\(w.start.formatted(.dateTime.day().month(.abbreviated))) · \(w.name) · \(Int(w.durationMinutes)) min" + (w.isPT ? " · PT" : ""))
                            .font(.caption2).foregroundStyle(.white.opacity(0.8))
                    }
                    if r.workouts.count > 40 { Text("…and \(r.workouts.count - 40) more").font(.caption2).foregroundStyle(.white.opacity(0.6)) }
                }
                .shareBox()
            }
        }
    }
}

// MARK: - Export centre

struct ExportCenterView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var health: HealthKitManager
    @State private var preset = 30
    @State private var from = Calendar.current.date(byAdding: .day, value: -29, to: .now)!
    @State private var to = Date.now
    @State private var include: Set<String> = ["Workouts", "Exercise sets", "Food", "Water", "Meditation", "Supplements", "Medicines", "Injuries & health events", "Weight & measurements", "InBody", "Payments", "Expenses", "AI reviews"]
    @State private var working = false
    @State private var items: [Any] = []
    @State private var show = false

    static let categories = ["Workouts", "Exercise sets", "Food", "Water", "Meditation", "Supplements", "Weight & measurements", "InBody", "Payments", "Expenses", "AI reviews"]

    private var start: Date { Calendar.current.startOfDay(for: from) }
    private var end: Date { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to))! }

    var body: some View {
        Form {
            Section("Period") {
                Picker("Period", selection: $preset) {
                    Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90); Text("1 year").tag(365); Text("Custom").tag(0)
                }
                .pickerStyle(.segmented)
                .onChange(of: preset) { _, p in
                    if p > 0 { to = .now; from = Calendar.current.date(byAdding: .day, value: -(p - 1), to: .now)! }
                }
                DatePicker("From", selection: $from, in: ...to, displayedComponents: .date).onChange(of: from) { _, _ in preset = presetFor() }
                DatePicker("To", selection: $to, in: from...Date.now, displayedComponents: .date).onChange(of: to) { _, _ in preset = presetFor() }
            }

            Section {
                Button { Task { await sharePDF() } } label: { Label("Health report (PDF with charts)", systemImage: "doc.richtext.fill") }
                Button { Task { await shareImage() } } label: { Label("Health report (image)", systemImage: "photo.fill") }
                NavigationLink { DailyReportView() } label: { Label("Daily report for one day", systemImage: "calendar") }
            } header: { Text("Reports") } footer: { Text("Charts and totals for the period, ready for WhatsApp, email or your doctor and trainer.") }

            Section {
                ForEach(Self.categories, id: \.self) { c in
                    Toggle(c, isOn: Binding(get: { include.contains(c) }, set: { if $0 { include.insert(c) } else { include.remove(c) } }))
                }
                Button { shareCSV() } label: { Label("Export data as spreadsheets (CSV)", systemImage: "tablecells.fill") }
                    .disabled(include.isEmpty)
            } header: { Text("All entries") } footer: { Text("One CSV file per category — opens in Excel, Numbers or Google Sheets.") }

            if working { Section { HStack { ProgressView(); Text("Preparing…") } } }
        }
        .navigationTitle("Export & Share")
        .sheet(isPresented: $show) { ShareSheet(items: items) }
    }

    private func presetFor() -> Int {
        let days = (Calendar.current.dateComponents([.day], from: start, to: Calendar.current.startOfDay(for: to)).day ?? 0) + 1
        return [7, 30, 90, 365].contains(days) && Calendar.current.isDateInToday(to) ? days : 0
    }

    private func buildRange() async -> RangeReport {
        let cal = Calendar.current
        var r = RangeReport(from: start, to: cal.startOfDay(for: to))
        let days = max(1, cal.dateComponents([.day], from: start, to: end).day ?? 1)
        let back = (cal.dateComponents([.day], from: start, to: cal.startOfDay(for: .now)).day ?? 0) + 1
        func clip(_ v: [DayValue]) -> [DayValue] { v.filter { $0.date >= start && $0.date < end } }
        r.steps = clip(await health.dailySeries(.stepCount, unit: .count(), days: back))
        r.active = clip(await health.dailySeries(.activeEnergyBurned, unit: .kilocalorie(), days: back))
        if back <= 60 { r.sleep = clip(await health.sleepSeries(days: back)) }

        func perDay<T>(_ items: [T], date: (T) -> Date, value: (T) -> Double) -> [DayValue] {
            var sums: [Date: Double] = [:]
            for i in items where date(i) >= start && date(i) < end { sums[cal.startOfDay(for: date(i)), default: 0] += value(i) }
            return sums.map { DayValue(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
        }
        let foods = (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        let meds = (try? context.fetch(FetchDescriptor<MeditationLog>())) ?? []
        r.kcal = perDay(foods, date: { $0.date }, value: { $0.calories })
        r.protein = perDay(foods, date: { $0.date }, value: { $0.protein })
        r.workoutMin = perDay(logs, date: { $0.start }, value: { $0.durationMinutes })
        r.meditationMin = perDay(meds, date: { $0.date }, value: { $0.minutes })
        r.mindfulTotal = r.meditationMin.map(\.value).reduce(0, +)
        r.workouts = logs.filter { $0.start >= start && $0.start < end }.sorted { $0.start < $1.start }
        r.ptDays = r.workouts.ptDays().count

        var w = ((try? context.fetch(FetchDescriptor<BodyMeasurement>())) ?? []).filter { $0.weightKg > 0 }.map { DayValue(date: $0.date, value: $0.weightKg) }
        w += ((try? context.fetch(FetchDescriptor<InBodyScan>())) ?? []).filter { $0.weightKg > 0 }.map { DayValue(date: $0.date, value: $0.weightKg) }
        if w.isEmpty { w = await health.dailySeries(.bodyMass, unit: .gramUnit(with: .kilo), days: back, average: true) }
        r.weight = w.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }

        let sups = (try? context.fetch(FetchDescriptor<Supplement>())) ?? []
        let doses = (try? context.fetch(FetchDescriptor<SupplementDose>())) ?? []
        for offset in 0..<days {
            let d = cal.date(byAdding: .day, value: offset, to: start)!
            r.dosePlanned += sups.filter { $0.isDue(on: d) }.reduce(0) { $0 + $1.doseSlots.count }
        }
        r.doseTaken = doses.filter { $0.day >= start && $0.day < end }.count
        let p = (try? context.fetch(FetchDescriptor<HealthProfile>()))?.first
        r.kcalGoal = p?.calorieIntakeGoal ?? 0; r.proteinGoal = p?.proteinGoal ?? 0; r.stepGoal = p?.stepGoal ?? 0
        return r
    }

    private var fileTag: String { "\(start.formatted(.iso8601.year().month().day())) to \(Calendar.current.startOfDay(for: to).formatted(.iso8601.year().month().day()))" }

    private func sharePDF() async {
        working = true
        let r = await buildRange()
        if let url = Exporter.pdf(RangeReportCard(r: r), name: "iLife report \(fileTag)") { items = [url]; show = true }
        working = false
    }

    private func shareImage() async {
        working = true
        let r = await buildRange()
        if let img = Exporter.image(RangeReportCard(r: r)) { items = [img]; show = true }
        working = false
    }

    private func shareCSV() {
        working = true
        defer { working = false }
        func inRange(_ d: Date) -> Bool { d >= start && d < end }
        var files: [URL] = []
        func add(_ name: String, _ header: [String], _ rows: [[Any?]]) {
            if let u = Exporter.file(CSV.table(header, rows), name: "iLife \(name) \(fileTag).csv") { files.append(u) }
        }
        let trainers = (try? context.fetch(FetchDescriptor<Trainer>())) ?? []
        let tName = Dictionary(trainers.map { ($0.uid, $0.fullName) }, uniquingKeysWith: { a, _ in a })
        let logs = ((try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? []).filter { inRange($0.start) }.sorted { $0.start < $1.start }

        if include.contains("Workouts") {
            add("workouts", ["start", "name", "type", "minutes", "kcal", "avg_hr", "session", "trainer", "source", "exercises", "notes"],
                logs.map { [$0.start, $0.name, $0.category, $0.durationMinutes, $0.calories, $0.avgHeartRate, $0.sessionType, tName[$0.trainerID] ?? "", $0.source, $0.exerciseNames.joined(separator: "; "), $0.notes] })
        }
        if include.contains("Exercise sets") {
            var rows: [[Any?]] = []
            for l in logs { for (i, s) in l.orderedSets.enumerated() { rows.append([l.start, l.name, s.exercise, i + 1, s.reps, s.weightKg, s.durationMinutes, s.distanceKm]) } }
            add("exercise sets", ["workout_start", "workout", "exercise", "set", "reps", "kg", "minutes", "km"], rows)
        }
        if include.contains("Food") {
            let f = ((try? context.fetch(FetchDescriptor<FoodEntry>())) ?? []).filter { inRange($0.date) }.sorted { $0.date < $1.date }
            add("food", ["time", "meal", "food", "quantity", "kcal", "protein_g", "carbs_g", "fat_g"], f.map { [$0.date, $0.meal.title, $0.name, $0.quantity, $0.calories, $0.protein, $0.carbs, $0.fat] })
        }
        if include.contains("Water") {
            let w = ((try? context.fetch(FetchDescriptor<WaterEntry>())) ?? []).filter { inRange($0.date) }.sorted { $0.date < $1.date }
            add("water", ["time", "ml"], w.map { [$0.date, $0.millilitres] })
        }
        if include.contains("Meditation") {
            let m = ((try? context.fetch(FetchDescriptor<MeditationLog>())) ?? []).filter { inRange($0.date) }.sorted { $0.date < $1.date }
            add("meditation", ["time", "session", "category", "minutes", "language", "sound", "mood_before", "mood_after", "completed"],
                m.map { [$0.date, $0.title, $0.category, $0.minutes, $0.language, $0.soundscape, $0.moodBefore, $0.moodAfter, $0.completed] })
        }
        if include.contains("Supplements") {
            let sups = (try? context.fetch(FetchDescriptor<Supplement>())) ?? []
            let byID = Dictionary(sups.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
            add("supplements", ["name", "company", "dose", "schedule", "times", "start", "weeks", "suggested_by", "by_name", "purpose", "paused"],
                sups.map { [$0.name, $0.company, $0.dose, $0.scheduleText, $0.doseSlots.map(\.rawValue).joined(separator: "; "), $0.startDate, $0.weeks, $0.suggestedBy, $0.suggestedByName, $0.purpose, $0.isPaused] })
            let d = ((try? context.fetch(FetchDescriptor<SupplementDose>())) ?? []).filter { inRange($0.day) }.sorted { $0.takenAt < $1.takenAt }
            add("supplement doses", ["day", "supplement", "when", "ticked_at"], d.map { [$0.day, byID[$0.supplementUID]?.name ?? "", $0.slot, $0.takenAt] })
        }
        if include.contains("Medicines") {
            let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
            let byID = Dictionary(meds.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
            add("medicines", ["name", "strength", "type", "dose", "schedule", "start", "end", "cause", "doctor", "hospital", "instructions", "paused"],
                meds.map { [$0.name, $0.strength, $0.form.rawValue, $0.dose, $0.scheduleText, $0.startDate, $0.endDate, $0.cause, $0.doctorName, $0.hospital, $0.instructions, $0.isPaused] })
            let d = ((try? context.fetch(FetchDescriptor<MedicationDose>())) ?? []).filter { inRange($0.day) }.sorted { $0.takenAt < $1.takenAt }
            add("medicine doses", ["day", "medicine", "when", "ticked_at"], d.map { [$0.day, byID[$0.medicationUID]?.displayName ?? "", $0.slot, $0.takenAt] })
        }
        if include.contains("Injuries & health events") {
            let atts = (try? context.fetch(FetchDescriptor<MedicalAttachment>())) ?? []
            func cost(_ id: String) -> Double { atts.filter { $0.ownerUID == id && $0.kind == "Bill" }.reduce(0) { $0 + $1.amount } }
            let inj = ((try? context.fetch(FetchDescriptor<Injury>())) ?? []).sorted { $0.date < $1.date }
            add("injuries", ["date", "injury", "body_part", "severity", "how", "treatment", "details", "doctor", "hospital", "admitted", "discharged", "status", "healed", "restrictions", "bills_inr"],
                inj.map { [$0.date, $0.title, $0.bodyPart, $0.severity, $0.howItHappened, $0.procedures.joined(separator: "; "), $0.procedureNotes, $0.doctorName, $0.hospital, $0.admitDate, $0.dischargeDate, $0.status, $0.healedDate, $0.restrictions, cost($0.uid)] })
            let ev = ((try? context.fetch(FetchDescriptor<HealthEvent>())) ?? []).sorted { $0.date < $1.date }
            add("health events", ["date", "ended", "name", "type", "diagnosis", "procedure", "doctor", "speciality", "hospital", "admitted", "discharged", "status", "follow_up", "bills_inr", "notes"],
                ev.map { [$0.date, $0.endDate, $0.title, $0.kind, $0.diagnosis, $0.procedure, $0.doctorName, $0.specialty, $0.hospital, $0.admitDate, $0.dischargeDate, $0.status, $0.followUp, cost($0.uid), $0.notes] })
        }
        if include.contains("Weight & measurements") {
            let m = ((try? context.fetch(FetchDescriptor<BodyMeasurement>())) ?? []).filter { inRange($0.date) }.sorted { $0.date < $1.date }
            add("weight and measurements", ["date", "weight_kg", "waist_cm", "chest_cm", "hips_cm", "arm_cm", "thigh_cm", "neck_cm", "note"],
                m.map { [$0.date, $0.weightKg, $0.waistCm, $0.chestCm, $0.hipsCm, $0.armCm, $0.thighCm, $0.neckCm, $0.note] })
        }
        if include.contains("InBody") {
            let s = ((try? context.fetch(FetchDescriptor<InBodyScan>())) ?? []).filter { inRange($0.date) }.sorted { $0.date < $1.date }
            add("inbody", ["date", "weight_kg", "skeletal_muscle_kg", "body_fat_kg", "body_fat_pct", "bmi", "body_water_l", "visceral_fat", "bmr_kcal", "score", "summary"],
                s.map { [$0.date, $0.weightKg, $0.skeletalMuscleKg, $0.bodyFatKg, $0.bodyFatPercent, $0.bmi, $0.totalBodyWaterL, $0.visceralFatLevel, $0.bmrKcal, $0.inBodyScore, $0.aiSummary] })
        }
        if include.contains("Payments") {
            let p = ((try? context.fetch(FetchDescriptor<GymPayment>())) ?? []).filter { inRange($0.date) }.sorted { $0.date < $1.date }
            add("payments", ["date", "for", "amount_inr", "method", "trainer", "sessions", "reference", "notes"],
                p.map { [$0.date, $0.kind.rawValue, $0.amount, $0.method, tName[$0.trainerID] ?? "", $0.sessionsIncluded, $0.reference, $0.notes] })
        }
        if include.contains("Expenses") {
            let e = ((try? context.fetch(FetchDescriptor<Expense>())) ?? []).filter { inRange($0.date) }.sorted { $0.date < $1.date }
            add("expenses", ["date", "category", "item", "amount_inr", "shop", "quantity", "notes"], e.map { [$0.date, $0.category.rawValue, $0.title, $0.amount, $0.vendor, $0.quantity, $0.notes] })
        }
        if include.contains("AI reviews") {
            let r = ((try? context.fetch(FetchDescriptor<DailyReview>())) ?? []).filter { inRange($0.day) }.sorted { $0.day < $1.day }
            add("ai reviews", ["day", "type", "score", "headline"], r.map { [$0.day, $0.kind == "night" ? "Night review" : "Morning plan", $0.overallScore, $0.headline] })
        }
        guard !files.isEmpty else { return }
        items = files
        show = true
    }
}
