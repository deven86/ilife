import SwiftUI
import SwiftData
import Charts
import HealthKit

struct TrendsView: View {
    @EnvironmentObject var health: HealthKitManager
    @Query(sort: \FoodEntry.date) private var foods: [FoodEntry]
    @Query(sort: \WorkoutLog.start) private var logs: [WorkoutLog]
    @Query(sort: \InBodyScan.date) private var scans: [InBodyScan]
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
    @Query private var profiles: [HealthProfile]

    @State private var days = 30
    @State private var steps: [DayValue] = []
    @State private var active: [DayValue] = []
    @State private var sleep: [DayValue] = []
    @State private var restingHR: [DayValue] = []
    @State private var hkWeight: [DayValue] = []
    @State private var loading = true

    private var profile: HealthProfile { profiles.first ?? HealthProfile() }
    private var since: Date { Calendar.current.date(byAdding: .day, value: -days + 1, to: Calendar.current.startOfDay(for: .now))! }

    private func byDay<T>(_ items: [T], date: (T) -> Date, value: (T) -> Double) -> [DayValue] {
        let cal = Calendar.current
        var sums: [Date: Double] = [:]
        for item in items where date(item) >= since { sums[cal.startOfDay(for: date(item)), default: 0] += value(item) }
        return sums.map { DayValue(date: $0.key, value: $0.value) }.filter { $0.value > 0 }.sorted { $0.date < $1.date }
    }

    private var weight: [DayValue] {
        var all = hkWeight
        let have = Set(all.map { Calendar.current.startOfDay(for: $0.date) })
        let local = scans.filter { $0.weightKg > 0 }.map { DayValue(date: $0.date, value: $0.weightKg) }
            + measurements.filter { $0.weightKg > 0 }.map { DayValue(date: $0.date, value: $0.weightKg) }
        for v in local where v.date >= since && !have.contains(Calendar.current.startOfDay(for: v.date)) { all.append(v) }
        return all.sorted { $0.date < $1.date }
    }
    private var kcal: [DayValue] { byDay(foods, date: { $0.date }, value: { $0.calories }) }
    private var protein: [DayValue] { byDay(foods, date: { $0.date }, value: { $0.protein }) }
    private var minutes: [DayValue] { byDay(logs, date: { $0.start }, value: { $0.durationMinutes }) }
    private var volume: [DayValue] {
        byDay(logs, date: { $0.start }, value: { log in log.orderedSets.reduce(0) { $0 + Double($1.reps) * $1.weightKg } })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Range", selection: $days) {
                    Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90)
                }
                .pickerStyle(.segmented)

                if loading { ProgressView().padding() }

                TrendCard(title: "Weight", unit: "kg", color: .purple, data: weight, line: true, goal: profile.targetWeightKg, decimals: 1, lowerIsBetter: true).appear(0)
                TrendCard(title: "Steps", unit: "", color: .cyan, data: steps, goal: profile.stepGoal).appear(1)
                TrendCard(title: "Active energy", unit: "kcal", color: .orange, data: active, goal: profile.activeCalorieGoal).appear(2)
                TrendCard(title: "Workout time", unit: "min", color: .green, data: minutes).appear(3)
                TrendCard(title: "Training volume", unit: "kg", color: .mint, data: volume).appear(4)
                TrendCard(title: "Calories eaten", unit: "kcal", color: .red, data: kcal, goal: profile.calorieIntakeGoal, lowerIsBetter: true).appear(5)
                TrendCard(title: "Protein", unit: "g", color: .yellow, data: protein, goal: profile.proteinGoal).appear(6)
                TrendCard(title: "Sleep", unit: "h", color: .indigo, data: sleep, goal: 8, decimals: 1).appear(7)
                TrendCard(title: "Resting heart rate", unit: "bpm", color: .pink, data: restingHR, line: true, lowerIsBetter: true).appear(8)
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Trends")
        .task(id: days) { await load() }
    }

    private func load() async {
        loading = true
        let bpm = HKUnit.count().unitDivided(by: .minute())
        steps = await health.dailySeries(.stepCount, unit: .count(), days: days)
        active = await health.dailySeries(.activeEnergyBurned, unit: .kilocalorie(), days: days)
        restingHR = await health.dailySeries(.restingHeartRate, unit: bpm, days: days, average: true)
        hkWeight = await health.dailySeries(.bodyMass, unit: .gramUnit(with: .kilo), days: days, average: true)
        sleep = await health.sleepSeries(days: min(days, 30))
        loading = false
    }
}

struct TrendCard: View {
    let title: String
    let unit: String
    let color: Color
    let data: [DayValue]
    var line = false
    var goal: Double = 0
    var decimals = 0
    var lowerIsBetter = false

    private var average: Double { data.isEmpty ? 0 : data.map(\.value).reduce(0, +) / Double(data.count) }

    /// Change between the first and second half of the period.
    private var change: Double? {
        guard data.count >= 4 else { return nil }
        let half = data.count / 2
        let a = data.prefix(half).map(\.value).reduce(0, +) / Double(half)
        let b = data.suffix(data.count - half).map(\.value).reduce(0, +) / Double(data.count - half)
        guard a > 0 else { return nil }
        return (b - a) / a * 100
    }

    private func fmt(_ v: Double) -> String {
        decimals == 0 ? Int(v.rounded()).formatted() : String(format: "%.\(decimals)f", v)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if let change {
                    let good = lowerIsBetter ? change <= 0 : change >= 0
                    Label(String(format: "%.0f%%", abs(change)), systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.bold()).foregroundStyle(good ? .green : .orange)
                }
            }
            if data.isEmpty {
                Text("No data yet for this period.").font(.caption).foregroundStyle(.secondary).frame(height: 60)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(fmt(line ? (data.last?.value ?? 0) : average)).font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                    Text(line ? "latest" : "daily average").font(.caption2).foregroundStyle(.secondary)
                }
                Chart {
                    ForEach(data) { d in
                        if line {
                            LineMark(x: .value("Day", d.date, unit: .day), y: .value(title, d.value))
                                .foregroundStyle(color).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 3))
                            AreaMark(x: .value("Day", d.date, unit: .day), y: .value(title, d.value))
                                .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            if data.count <= 14 { PointMark(x: .value("Day", d.date, unit: .day), y: .value(title, d.value)).foregroundStyle(color) }
                        } else {
                            BarMark(x: .value("Day", d.date, unit: .day), y: .value(title, d.value))
                                .foregroundStyle(LinearGradient(colors: [color, color.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                                .cornerRadius(3)
                        }
                    }
                    if goal > 0 {
                        RuleMark(y: .value("Goal", goal))
                            .foregroundStyle(.white.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .trailing) { Text("goal").font(.system(size: 9)).foregroundStyle(.secondary) }
                    }
                }
                .chartYScale(domain: yDomain)
                .frame(height: 150)
            }
        }
        .glassCard()
    }

    private var yDomain: ClosedRange<Double> {
        var values = data.map(\.value)
        if goal > 0 { values.append(goal) }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        if line {
            let pad = max((hi - lo) * 0.25, 1)
            return (lo - pad)...(hi + pad)
        }
        return 0...(hi * 1.15)
    }
}

// MARK: - Achievements

struct AchievementsView: View {
    @Query private var logs: [WorkoutLog]
    @Query private var photos: [ProgressPhoto]
    @Query private var scans: [InBodyScan]
    @Query private var foods: [FoodEntry]
    @EnvironmentObject var health: HealthKitManager
    @EnvironmentObject var theme: ThemeManager
    @State private var bestSteps = 0.0

    private var items: [Achievement] {
        let dates = logs.map(\.start)
        let foodDays = Set(foods.map { Calendar.current.startOfDay(for: $0.date) }).count
        return Achievements.all(workouts: logs.count, streak: InsightsEngine.workoutStreak(dates), bestStreak: Achievements.bestStreak(dates),
                                photos: photos.count, scans: scans.count, foodDays: foodDays, bestSteps: max(bestSteps, health.steps),
                                totalMinutes: logs.reduce(0) { $0 + $1.durationMinutes }, ptSessions: logs.filter(\.isPT).count,
                                prs: UserDefaults.standard.integer(forKey: "prCount"))
    }

    var body: some View {
        let all = items
        let unlocked = all.filter(\.unlocked).count
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Text("\(unlocked) / \(all.count)").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(theme.current.gradient)
                    Text("achievements unlocked").font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: Double(unlocked), total: Double(all.count)).tint(theme.current.accent)
                }
                .glassCard()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(Array(all.enumerated()), id: \.element.id) { i, a in
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().stroke(.white.opacity(0.15), lineWidth: 5)
                                Circle().trim(from: 0, to: a.progress).stroke(a.unlocked ? AnyShapeStyle(theme.current.gradient) : AnyShapeStyle(Color.gray),
                                                                             style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                                Image(systemName: a.icon).font(.title2)
                                    .foregroundStyle(a.unlocked ? AnyShapeStyle(theme.current.gradient) : AnyShapeStyle(Color.gray))
                            }
                            .frame(width: 64, height: 64)
                            Text(a.title).font(.subheadline.bold())
                            Text(a.detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            if !a.unlocked { Text("\(Int(a.progress * 100))%").font(.caption2.bold()).foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity)
                        .opacity(a.unlocked ? 1 : 0.65)
                        .glassCard(cornerRadius: 18, padding: 12)
                        .appear(i)
                    }
                }
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Achievements")
        .task {
            let series = await health.dailySeries(.stepCount, unit: .count(), days: 180)
            bestSteps = series.map(\.value).max() ?? 0
        }
    }
}

// MARK: - Weight & measurements

struct WeightLogSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var health: HealthKitManager
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var history: [BodyMeasurement]
    @State private var date = Date.now
    @State private var weight = ""
    @State private var waist = ""
    @State private var chest = ""
    @State private var hips = ""
    @State private var arm = ""
    @State private var thigh = ""
    @State private var neck = ""
    @State private var note = ""

    private func n(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    row("Weight", $weight, "kg")
                    DatePicker("Date", selection: $date, in: ...Date.now)
                }
                Section("Measurements (optional)") {
                    row("Waist", $waist, "cm"); row("Chest", $chest, "cm"); row("Hips", $hips, "cm")
                    row("Arm", $arm, "cm"); row("Thigh", $thigh, "cm"); row("Neck", $neck, "cm")
                }
                Section { TextField("Note", text: $note) }
                if !history.isEmpty {
                    Section("History") {
                        ForEach(history.prefix(15)) { m in
                            HStack {
                                Text(m.date.formatted(date: .abbreviated, time: .omitted))
                                Spacer()
                                Text([m.weightKg > 0 ? "\(m.weightKg.clean) kg" : nil, m.waistCm > 0 ? "waist \(m.waistCm.clean)" : nil]
                                    .compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                        .onDelete { idx in idx.forEach { context.delete(history[$0]) } }
                    }
                }
            }
            .navigationTitle("Weight & Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let m = BodyMeasurement(date: date)
                        m.weightKg = n(weight); m.waistCm = n(waist); m.chestCm = n(chest); m.hipsCm = n(hips)
                        m.armCm = n(arm); m.thighCm = n(thigh); m.neckCm = n(neck); m.note = note
                        context.insert(m)
                        try? context.save()
                        let kg = m.weightKg, when = date
                        Task { await health.saveWeight(kg: kg, date: when) }
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(n(weight) <= 0 && n(waist) <= 0)
                }
            }
            .onAppear { if weight.isEmpty, health.weightKg > 0 { weight = health.weightKg.clean } }
        }
    }

    private func row(_ title: String, _ v: Binding<String>, _ unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("–", text: v).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text(unit).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
        }
    }
}
