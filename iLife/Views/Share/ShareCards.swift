import SwiftUI
import SwiftData
import Charts

private func dayPoints(_ values: [Double], end: Date) -> [DayValue] {
    let cal = Calendar.current
    return values.enumerated().map { i, v in DayValue(date: cal.date(byAdding: .day, value: i - (values.count - 1), to: end) ?? end, value: v) }
}

/// "8×60kg", "20 min · 3 km", "12 reps" or "done".
func setSummary(_ s: ExerciseSet) -> String {
    if s.durationMinutes > 0 {
        let km = s.distanceKm > 0 ? " · \(s.distanceKm.clean) km" : ""
        return "\(Int(s.durationMinutes)) min" + km
    }
    if s.weightKg > 0 { return "\(s.reps)×\(s.weightKg.clean)kg" }
    return s.reps > 0 ? "\(s.reps) reps" : "done"
}

private func hm(_ hours: Double) -> String {
    guard hours > 0 else { return "–" }
    let h = Int(hours), m = Int((hours - Double(h)) * 60)
    return "\(h)h \(m)m"
}

// MARK: - Daily report

struct DayReportData {
    var day: Date
    var stats: DayStats
    var foods: [FoodEntry]
    var logs: [WorkoutLog]
    var meditations: [MeditationLog]
    var supplements: [(name: String, taken: Int, planned: Int)]
    var review: NightReview?
    var trainerNames: [String: String] = [:]

    var text: String {
        var l: [String] = []
        l.append("iLife daily report — \(day.formatted(date: .complete, time: .omitted))")
        if let r = review { l.append("Score \(Int(r.overallScore?.value ?? 0))/100 — \(r.headline ?? "")") }
        l.append("")
        l.append("ACTIVITY: \(Int(stats.steps).formatted()) steps (goal \(Int(stats.stepGoal).formatted())), \(Int(stats.activeKcal)) active kcal, \(Int(stats.exerciseMin)) exercise min")
        l.append("SLEEP: \(hm(stats.sleepHours)); resting HR \(stats.restingHR > 0 ? "\(Int(stats.restingHR)) bpm" : "–"); HRV \(stats.hrv > 0 ? "\(Int(stats.hrv)) ms" : "–")")
        l.append("NUTRITION: \(Int(stats.kcalEaten)) / \(Int(stats.kcalGoal)) kcal · protein \(Int(stats.protein)) g · carbs \(Int(stats.carbs)) g · fat \(Int(stats.fat)) g · water \(String(format: "%.1f", stats.waterL)) L")
        for f in foods { l.append("  • \(f.date.formatted(date: .omitted, time: .shortened)) \(f.meal.title): \(f.name) \(f.quantity) — \(Int(f.calories)) kcal, P\(Int(f.protein))") }
        l.append("WORKOUTS: \(logs.isEmpty ? "none" : "")")
        for w in logs {
            l.append("  • \(w.name) — \(Int(w.durationMinutes)) min, \(Int(w.calories)) kcal\(w.isPT ? ", with trainer \(trainerNames[w.trainerID] ?? "")" : "")")
            for ex in w.exerciseNames {
                let sets = w.orderedSets.filter { $0.exercise == ex }
                let d = sets.map(setSummary).joined(separator: ", ")
                l.append("      \(ex): \(d)")
            }
        }
        if !meditations.isEmpty { l.append("MEDITATION: " + meditations.map { "\($0.title) \(Int($0.minutes.rounded())) min" }.joined(separator: ", ")) }
        if !supplements.isEmpty { l.append("SUPPLEMENTS: " + supplements.map { "\($0.name) \($0.taken)/\($0.planned)" }.joined(separator: ", ")) }
        if stats.weightKg > 0 { l.append("WEIGHT: \(stats.weightKg.clean) kg") }
        if let r = review {
            if let w = r.wentWell, !w.isEmpty { l.append(""); l.append("WENT WELL:"); w.forEach { l.append("  • \($0)") } }
            if let i = r.improve, !i.isEmpty { l.append("TO IMPROVE:"); i.forEach { l.append("  • \($0)") } }
            if let t = r.tomorrow, !t.isEmpty { l.append("TOMORROW:"); t.forEach { l.append("  • \($0)") } }
        }
        return l.joined(separator: "\n")
    }
}

struct DailyReportCard: View {
    let data: DayReportData

    var body: some View {
        let s = data.stats
        ShareFrame(title: "Daily Report", subtitle: data.day.formatted(date: .complete, time: .omitted)) {
            if let r = data.review {
                HStack(spacing: 14) {
                    ScoreRing(score: r.overallScore?.value, size: 70, lineWidth: 8)
                    Text(r.headline ?? "").font(.subheadline.weight(.semibold))
                }
                .shareBox()
            }
            VStack(spacing: 10) {
                HStack {
                    ShareStat(value: Int(s.steps).formatted(), label: "steps", color: .cyan)
                    ShareStat(value: "\(Int(s.activeKcal))", label: "active kcal", color: .orange)
                    ShareStat(value: "\(Int(s.exerciseMin))", label: "exercise min", color: .green)
                }
                HStack {
                    ShareStat(value: hm(s.sleepHours), label: "sleep", color: .indigo)
                    ShareStat(value: s.restingHR > 0 ? "\(Int(s.restingHR))" : "–", label: "resting bpm", color: .pink)
                    ShareStat(value: String(format: "%.1f L", s.waterL), label: "water", color: .blue)
                }
            }
            .shareBox()

            NutritionSummaryBlock(foods: data.foods, kcalGoal: s.kcalGoal, proteinGoal: s.proteinGoal)

            if !data.logs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workouts").font(.headline)
                    ForEach(data.logs) { w in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(w.name) · \(Int(w.durationMinutes)) min · \(Int(w.calories)) kcal" + (w.isPT ? " · PT" : "")).font(.subheadline.bold())
                            ForEach(w.exerciseNames.prefix(10), id: \.self) { ex in
                                let sets = w.orderedSets.filter { $0.exercise == ex }
                                Text("\(ex): " + sets.map(setSummary).joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                }
                .shareBox()
            }

            if !data.meditations.isEmpty || !data.supplements.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !data.meditations.isEmpty {
                        Label(data.meditations.map { "\($0.title) \(Int($0.minutes.rounded())) min" }.joined(separator: " · "), systemImage: "leaf.fill").font(.caption)
                    }
                    ForEach(data.supplements, id: \.name) { sup in
                        Label("\(sup.name): \(sup.taken) of \(sup.planned) doses", systemImage: sup.taken >= sup.planned ? "checkmark.circle.fill" : "circle")
                            .font(.caption).foregroundStyle(sup.taken >= sup.planned ? .green : .orange)
                    }
                }
                .shareBox()
            }

            ShareChart(title: "Steps — last 7 days", points: dayPoints(s.steps7, end: data.day), color: .cyan, goal: s.stepGoal)
            ShareChart(title: "Calories eaten — last 7 days", points: dayPoints(s.kcal7, end: data.day), color: .red, goal: s.kcalGoal)
            ShareChart(title: "Protein (g) — last 7 days", points: dayPoints(s.protein7, end: data.day), color: .yellow, goal: s.proteinGoal)
            if s.sleep7.contains(where: { $0 > 0 }) { ShareChart(title: "Sleep (h) — last 7 days", points: dayPoints(s.sleep7, end: data.day), color: .indigo, goal: 8) }
            if s.workoutMin7.contains(where: { $0 > 0 }) { ShareChart(title: "Workout minutes — last 7 days", points: dayPoints(s.workoutMin7, end: data.day), color: .green) }

            if let r = data.review {
                VStack(alignment: .leading, spacing: 6) {
                    if let w = r.wentWell, !w.isEmpty { Text("Went well").font(.caption.bold()).foregroundStyle(.green); ForEach(w, id: \.self) { Text("• " + $0).font(.caption) } }
                    if let i = r.improve, !i.isEmpty { Text("To improve").font(.caption.bold()).foregroundStyle(.orange); ForEach(i, id: \.self) { Text("• " + $0).font(.caption) } }
                    if let t = r.tomorrow, !t.isEmpty { Text("Tomorrow").font(.caption.bold()).foregroundStyle(.cyan); ForEach(t, id: \.self) { Text("• " + $0).font(.caption) } }
                }
                .shareBox()
            }
        }
    }
}

struct NutritionSummaryBlock: View {
    let foods: [FoodEntry]
    let kcalGoal: Double
    let proteinGoal: Double

    var body: some View {
        let k = foods.reduce(0) { $0 + $1.calories }, p = foods.reduce(0) { $0 + $1.protein }
        let c = foods.reduce(0) { $0 + $1.carbs }, f = foods.reduce(0) { $0 + $1.fat }
        let macro = max(p * 4 + c * 4 + f * 9, 1)
        let parts: [(String, Double, Color)] = [("Protein", p * 4 / macro, .cyan), ("Carbs", c * 4 / macro, .yellow), ("Fat", f * 9 / macro, .pink)]
        return VStack(alignment: .leading, spacing: 10) {
            Text("Nutrition").font(.headline)
            HStack(spacing: 16) {
                ZStack {
                    if k > 0 {
                        Chart(parts, id: \.0) { SectorMark(angle: .value("Share", $0.1), innerRadius: .ratio(0.65), angularInset: 2).foregroundStyle($0.2).cornerRadius(3) }
                    } else { Circle().stroke(.white.opacity(0.2), lineWidth: 10) }
                    VStack(spacing: 0) { Text("\(Int(k))").font(.headline); Text("kcal").font(.caption2).foregroundStyle(.white.opacity(0.6)) }
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(k)) / \(Int(kcalGoal)) kcal").font(.subheadline.bold())
                    Text("Protein \(Int(p)) / \(Int(proteinGoal)) g").font(.caption).foregroundStyle(.cyan)
                    Text("Carbs \(Int(c)) g").font(.caption).foregroundStyle(.yellow)
                    Text("Fat \(Int(f)) g").font(.caption).foregroundStyle(.pink)
                }
            }
            ForEach(MealType.allCases) { meal in
                let items = foods.filter { $0.meal == meal }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(meal.title) · \(Int(items.reduce(0) { $0 + $1.calories })) kcal").font(.caption.bold())
                        ForEach(items) { e in
                            Text("\(e.name)\(e.quantity.isEmpty ? "" : " (\(e.quantity))") — \(Int(e.calories)) kcal, P \(Int(e.protein))g")
                                .font(.caption2).foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
            }
        }
        .shareBox()
    }
}

// MARK: - Single items

struct NutritionDayShareCard: View {
    let day: Date
    let foods: [FoodEntry]
    let kcalGoal: Double
    let proteinGoal: Double
    let waterL: Double
    var body: some View {
        ShareFrame(title: "Nutrition", subtitle: day.formatted(date: .complete, time: .omitted)) {
            NutritionSummaryBlock(foods: foods, kcalGoal: kcalGoal, proteinGoal: proteinGoal)
            Label(String(format: "Water %.1f L", waterL), systemImage: "drop.fill").font(.subheadline).shareBox()
        }
    }
}

struct FoodEntryShareCard: View {
    let entry: FoodEntry
    var body: some View {
        ShareFrame(title: entry.name, subtitle: "\(entry.meal.title) · \(entry.date.formatted(date: .abbreviated, time: .shortened))") {
            if let d = entry.photo ?? MediaStore.shared.photo("food", entry.name), let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFill().frame(height: 220).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            HStack {
                ShareStat(value: "\(Int(entry.calories))", label: "kcal", color: .orange)
                ShareStat(value: "\(Int(entry.protein)) g", label: "protein", color: .cyan)
                ShareStat(value: "\(Int(entry.carbs)) g", label: "carbs", color: .yellow)
                ShareStat(value: "\(Int(entry.fat)) g", label: "fat", color: .pink)
            }
            .shareBox()
            if !entry.quantity.isEmpty { Text(entry.quantity).font(.caption).foregroundStyle(.white.opacity(0.7)) }
        }
    }
}

struct WorkoutShareCard: View {
    let log: WorkoutLog
    var trainerName: String?

    var body: some View {
        let volumes: [(String, Double)] = log.exerciseNames.map { ex in
            (ex, log.orderedSets.filter { $0.exercise == ex }.reduce(0) { $0 + Double($1.reps) * $1.weightKg })
        }
        ShareFrame(title: log.name, subtitle: log.start.formatted(date: .complete, time: .shortened), accent: [.orange, .pink]) {
            HStack {
                ShareStat(value: "\(Int(log.durationMinutes))", label: "minutes", color: .green)
                ShareStat(value: "\(Int(log.calories))", label: "kcal", color: .orange)
                ShareStat(value: "\(log.orderedSets.count)", label: "sets", color: .cyan)
                if log.avgHeartRate > 0 { ShareStat(value: "\(Int(log.avgHeartRate))", label: "avg bpm", color: .pink) }
            }
            .shareBox()
            if log.isPT { Label("Personal training\(trainerName.map { " with \($0)" } ?? "")", systemImage: "person.2.fill").font(.caption).shareBox() }
            ForEach(log.exerciseNames, id: \.self) { ex in
                let sets = log.orderedSets.filter { $0.exercise == ex }
                VStack(alignment: .leading, spacing: 4) {
                    Text(ex).font(.subheadline.bold())
                    Text(sets.map(setSummary).joined(separator: "   ")).font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                .shareBox()
            }
            if volumes.contains(where: { $0.1 > 0 }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Volume by exercise (kg)").font(.caption.bold()).foregroundStyle(.white.opacity(0.8))
                    Chart(volumes.filter { $0.1 > 0 }, id: \.0) { v in
                        BarMark(x: .value("kg", v.1), y: .value("Exercise", v.0))
                            .foregroundStyle(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing)).cornerRadius(3)
                            .annotation(position: .trailing) { Text("\(Int(v.1))").font(.caption2).foregroundStyle(.white.opacity(0.8)) }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(.white.opacity(0.8)) } }
                    .frame(height: CGFloat(max(1, volumes.filter { $0.1 > 0 }.count)) * 30 + 10)
                }
                .shareBox()
            }
            if !log.notes.isEmpty { Text(log.notes).font(.caption).shareBox() }
        }
    }
}

struct MeditationShareCard: View {
    let log: MeditationLog
    var recent: [DayValue] = []
    private let faces = ["😣", "😕", "😐", "🙂", "😌"]
    var body: some View {
        ShareFrame(title: log.title, subtitle: log.date.formatted(date: .complete, time: .shortened), accent: [.purple, .mint]) {
            HStack {
                ShareStat(value: "\(Int(log.minutes.rounded()))", label: "mindful minutes", color: .mint)
                if log.moodBefore > 0 && log.moodAfter > 0 { ShareStat(value: "\(faces[log.moodBefore - 1]) → \(faces[log.moodAfter - 1])", label: "mood") }
                ShareStat(value: log.category.isEmpty ? "Custom" : log.category, label: "type")
            }
            .shareBox()
            if recent.contains(where: { $0.value > 0 }) { ShareChart(title: "Mindful minutes — last 14 days", points: recent, color: .mint, goal: 10) }
        }
    }
}

struct InBodyShareCard: View {
    let scan: InBodyScan
    var previous: InBodyScan?
    var body: some View {
        ShareFrame(title: "InBody Result", subtitle: scan.date.formatted(date: .complete, time: .omitted), accent: [.cyan, .purple]) {
            VStack(spacing: 10) {
                HStack {
                    stat("Weight", scan.weightKg, previous?.weightKg, "kg", lowerBetter: true)
                    stat("Muscle", scan.skeletalMuscleKg, previous?.skeletalMuscleKg, "kg", lowerBetter: false)
                    stat("Body fat", scan.bodyFatPercent, previous?.bodyFatPercent, "%", lowerBetter: true)
                }
                HStack {
                    stat("BMI", scan.bmi, previous?.bmi, "", lowerBetter: true)
                    stat("Visceral", scan.visceralFatLevel, previous?.visceralFatLevel, "", lowerBetter: true)
                    stat("Score", scan.inBodyScore, previous?.inBodyScore, "", lowerBetter: false)
                }
            }
            .shareBox()
            if !scan.aiSummary.isEmpty { Text(scan.aiSummary).font(.caption).shareBox() }
            if scan.trunkKg > 0 {
                HStack {
                    ShareStat(value: scan.leftArmKg.clean, label: "L arm kg"); ShareStat(value: scan.rightArmKg.clean, label: "R arm kg")
                    ShareStat(value: scan.trunkKg.clean, label: "trunk kg"); ShareStat(value: scan.leftLegKg.clean, label: "L leg kg"); ShareStat(value: scan.rightLegKg.clean, label: "R leg kg")
                }
                .shareBox()
            }
        }
    }
    private func stat(_ t: String, _ v: Double, _ prev: Double?, _ u: String, lowerBetter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v > 0 ? v.clean + (u.isEmpty ? "" : " \(u)") : "–").font(.system(size: 18, weight: .bold, design: .rounded))
            Text(t).font(.caption2).foregroundStyle(.white.opacity(0.65))
            if let prev, prev > 0, v > 0, prev != v {
                let d = v - prev
                Text("\(d > 0 ? "↑" : "↓") \(abs(d).clean)").font(.caption2.bold()).foregroundStyle((lowerBetter ? d < 0 : d > 0) ? .green : .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReviewShareCard: View {
    let review: NightReview
    let stats: DayStats?
    let day: Date
    var body: some View {
        ShareFrame(title: "Day Review", subtitle: day.formatted(date: .complete, time: .omitted), accent: [.indigo, .cyan]) {
            HStack(spacing: 14) {
                ScoreRing(score: review.overallScore?.value, size: 80, lineWidth: 9)
                Text(review.headline ?? "").font(.subheadline.weight(.semibold))
            }
            .shareBox()
            if let sc = review.scores {
                HStack {
                    ScoreRing(score: sc.sleep?.value, size: 44, lineWidth: 5, label: "Sleep")
                    ScoreRing(score: sc.activity?.value, size: 44, lineWidth: 5, label: "Activity")
                    ScoreRing(score: sc.nutrition?.value, size: 44, lineWidth: 5, label: "Food")
                    ScoreRing(score: sc.hydration?.value, size: 44, lineWidth: 5, label: "Water")
                    ScoreRing(score: sc.recovery?.value, size: 44, lineWidth: 5, label: "Recovery")
                }
                .frame(maxWidth: .infinity).shareBox()
            }
            ForEach(review.sections ?? []) { s in
                VStack(alignment: .leading, spacing: 3) { Text(s.title).font(.caption.bold()); Text(s.text).font(.caption).foregroundStyle(.white.opacity(0.85)) }.shareBox()
            }
            if let st = stats {
                ShareChart(title: "Steps", points: dayPoints(st.steps7, end: day), color: .cyan, goal: st.stepGoal)
                ShareChart(title: "Calories eaten", points: dayPoints(st.kcal7, end: day), color: .red, goal: st.kcalGoal)
                ShareChart(title: "Protein (g)", points: dayPoints(st.protein7, end: day), color: .yellow, goal: st.proteinGoal)
            }
            if let t = review.trends, !t.isEmpty { Text(t).font(.caption).shareBox() }
            if let tm = review.tomorrow, !tm.isEmpty {
                VStack(alignment: .leading, spacing: 3) { Text("Tomorrow").font(.caption.bold()).foregroundStyle(.cyan); ForEach(tm, id: \.self) { Text("• " + $0).font(.caption) } }.shareBox()
            }
        }
    }
}

struct BriefShareCard: View {
    let brief: MorningBrief
    let day: Date
    var body: some View {
        ShareFrame(title: "Today's Plan", subtitle: day.formatted(date: .complete, time: .omitted), accent: [.yellow, .orange]) {
            Text(brief.headline ?? "").font(.subheadline.weight(.semibold)).shareBox()
            if let p = brief.priorities, !p.isEmpty {
                VStack(alignment: .leading, spacing: 4) { ForEach(Array(p.enumerated()), id: \.offset) { i, s in Text("\(i + 1). \(s)").font(.caption) } }.shareBox()
            }
            ForEach(brief.meals ?? []) { m in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(m.mealType ?? "Meal"): \(m.name)").font(.subheadline.bold())
                    Text("\(Int(m.calories?.value ?? 0)) kcal · \(Int(m.protein?.value ?? 0)) g protein · \(Int(m.prepMinutes?.value ?? 0)) min").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    if let ing = m.ingredients { Text(ing.joined(separator: ", ")).font(.caption2).foregroundStyle(.white.opacity(0.75)) }
                    if let steps = m.steps { ForEach(Array(steps.enumerated()), id: \.offset) { i, s in Text("\(i + 1). \(s)").font(.caption2) } }
                }
                .shareBox()
            }
            if let w = brief.workout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(w.title ?? "Workout").font(.subheadline.bold())
                    ForEach(w.exercises ?? []) { e in Text("\(e.name) — \([e.sets?.value, e.reps?.value].compactMap { $0 }.joined(separator: " × "))").font(.caption) }
                }
                .shareBox()
            }
        }
    }
}

struct TrendShareCard: View {
    let title: String
    let unit: String
    let data: [DayValue]
    let color: Color
    var goal: Double = 0
    var line = false
    var body: some View {
        let avg = data.isEmpty ? 0 : data.map(\.value).reduce(0, +) / Double(data.count)
        ShareFrame(title: title, subtitle: rangeText) {
            HStack {
                ShareStat(value: line ? (data.last?.value ?? 0).clean : Int(avg.rounded()).formatted(), label: line ? "latest \(unit)" : "daily average \(unit)", color: color)
                ShareStat(value: "\(data.count)", label: "days with data")
            }
            .shareBox()
            ShareChart(title: title, points: data, color: color, goal: goal, line: line)
        }
    }
    private var rangeText: String {
        guard let a = data.first?.date, let b = data.last?.date else { return "" }
        return "\(a.formatted(date: .abbreviated, time: .omitted)) – \(b.formatted(date: .abbreviated, time: .omitted))"
    }
}
