import Foundation
import SwiftData
import HealthKit
import UserNotifications

// MARK: - Lenient JSON pieces (the model sometimes writes "12" where 12 is expected, or the reverse)

struct Num: Codable, Hashable {
    var value: Double
    init(_ v: Double) { value = v }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = Double(s.filter { "0123456789.-".contains($0) }) ?? 0 }
        else { value = 0 }
    }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(value) }
}

struct Str: Codable, Hashable {
    var value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let d = try? c.decode(Double.self) { value = d == d.rounded() ? String(Int(d)) : String(d) }
        else { value = "" }
    }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(value) }
}

// MARK: - Morning plan

struct Recipe: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var mealType: String?
    var why: String?
    var calories: Num?
    var protein: Num?
    var carbs: Num?
    var fat: Num?
    var prepMinutes: Num?
    var ingredients: [String]?
    var steps: [String]?
}

struct BriefSection: Codable, Hashable {
    var summary: String?
    var tips: [String]?
}

struct SuggestedExercise: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var sets: Str?
    var reps: Str?
    var note: String?
}

struct WorkoutSuggestion: Codable, Hashable {
    var title: String?
    var why: String?
    var durationMinutes: Num?
    var exercises: [SuggestedExercise]?
}

struct MorningBrief: Codable {
    var headline: String?
    var priorities: [String]?
    var nutrition: BriefSection?
    var meals: [Recipe]?
    var workout: WorkoutSuggestion?
    var supplements: BriefSection?
    var recovery: BriefSection?
    var health: BriefSection?
}

// MARK: - Night review

struct ReviewScores: Codable {
    var sleep: Num?
    var activity: Num?
    var nutrition: Num?
    var hydration: Num?
    var supplements: Num?
    var recovery: Num?
}

struct ReviewSection: Codable, Identifiable {
    var id: String { title }
    var title: String
    var text: String
}

struct NightReview: Codable {
    var headline: String?
    var overallScore: Num?
    var scores: ReviewScores?
    var wentWell: [String]?
    var improve: [String]?
    var sections: [ReviewSection]?
    var trends: String?
    var tomorrow: [String]?
}

/// The numbers for one day plus the 7 days ending on it (oldest → newest). Stored with every review.
struct DayStats: Codable {
    var day = Date.now
    var steps = 0.0, activeKcal = 0.0, exerciseMin = 0.0, sleepHours = 0.0, restingHR = 0.0, hrv = 0.0
    var kcalEaten = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0, waterL = 0.0
    var workouts = 0, workoutMin = 0.0
    var dosesTaken = 0, dosesPlanned = 0
    var weightKg = 0.0
    var stepGoal = 0.0, kcalGoal = 0.0, proteinGoal = 0.0, waterGoal = 0.0
    var steps7: [Double] = [], active7: [Double] = [], sleep7: [Double] = []
    var kcal7: [Double] = [], protein7: [Double] = [], workoutMin7: [Double] = []
}

// MARK: - Building what the AI sees

@MainActor
enum AIContext {
    /// A numbers-only summary of `day` and the week before it. No name, contact details, documents or photos.
    static func build(day: Date, context ctx: ModelContext, health: HealthKitManager) async -> (text: String, stats: DayStats) {
        let cal = Calendar.current
        let d0 = cal.startOfDay(for: day)
        let d1 = cal.date(byAdding: .day, value: 1, to: d0)!
        let week = (0..<7).map { cal.date(byAdding: .day, value: $0 - 6, to: d0)! }
        let span = max(8, (cal.dateComponents([.day], from: d0, to: cal.startOfDay(for: .now)).day ?? 0) + 8)

        func map(_ series: [DayValue]) -> [Date: Double] { Dictionary(series.map { (cal.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: { a, _ in a }) }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let steps = map(await health.dailySeries(.stepCount, unit: .count(), days: span))
        let active = map(await health.dailySeries(.activeEnergyBurned, unit: .kilocalorie(), days: span))
        let exercise = map(await health.dailySeries(.appleExerciseTime, unit: .minute(), days: span))
        let rhr = map(await health.dailySeries(.restingHeartRate, unit: bpm, days: span, average: true))
        let hrv = map(await health.dailySeries(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), days: span, average: true))
        let hkWater = map(await health.dailySeries(.dietaryWater, unit: .liter(), days: span))
        let sleep = map(await health.sleepSeries(days: min(span, 14)))

        let profile = (try? ctx.fetch(FetchDescriptor<HealthProfile>()))?.first ?? HealthProfile()
        let foods = (try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let waters = (try? ctx.fetch(FetchDescriptor<WaterEntry>())) ?? []
        let logs = (try? ctx.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        let scans = ((try? ctx.fetch(FetchDescriptor<InBodyScan>())) ?? []).sorted { $0.date > $1.date }
        let measures = ((try? ctx.fetch(FetchDescriptor<BodyMeasurement>())) ?? []).sorted { $0.date > $1.date }
        let supplements = (try? ctx.fetch(FetchDescriptor<Supplement>())) ?? []
        let doses = (try? ctx.fetch(FetchDescriptor<SupplementDose>())) ?? []
        let plans = (try? ctx.fetch(FetchDescriptor<WorkoutPlan>())) ?? []

        func foodsOn(_ d: Date) -> [FoodEntry] { foods.filter { cal.isDate($0.date, inSameDayAs: d) } }
        func logsOn(_ d: Date) -> [WorkoutLog] { logs.filter { cal.isDate($0.start, inSameDayAs: d) } }

        var s = DayStats()
        s.day = d0
        s.steps = steps[d0] ?? 0; s.activeKcal = active[d0] ?? 0; s.sleepHours = sleep[d0] ?? 0
        s.restingHR = rhr[d0] ?? 0; s.hrv = hrv[d0] ?? 0
        let dayFoods = foodsOn(d0).sorted { $0.date < $1.date }
        s.kcalEaten = dayFoods.reduce(0) { $0 + $1.calories }; s.protein = dayFoods.reduce(0) { $0 + $1.protein }
        s.carbs = dayFoods.reduce(0) { $0 + $1.carbs }; s.fat = dayFoods.reduce(0) { $0 + $1.fat }
        let appWater = waters.filter { $0.date >= d0 && $0.date < d1 }.reduce(0) { $0 + $1.millilitres } / 1000
        s.waterL = max(appWater, hkWater[d0] ?? 0)
        let dayLogs = logsOn(d0).sorted { $0.start < $1.start }
        s.workouts = dayLogs.count; s.workoutMin = dayLogs.reduce(0) { $0 + $1.durationMinutes }
        s.exerciseMin = max(exercise[d0] ?? 0, s.workoutMin)
        let due = supplements.filter { $0.isDue(on: d0) }
        s.dosesPlanned = due.reduce(0) { $0 + $1.doseSlots.count }
        s.dosesTaken = doses.filter { cal.isDate($0.day, inSameDayAs: d0) }.count
        s.weightKg = measures.first(where: { $0.weightKg > 0 && $0.date < d1 })?.weightKg ?? scans.first(where: { $0.date < d1 })?.weightKg ?? health.weightKg
        s.stepGoal = profile.stepGoal; s.kcalGoal = profile.calorieIntakeGoal; s.proteinGoal = profile.proteinGoal; s.waterGoal = profile.waterGoalLitres
        s.steps7 = week.map { steps[$0] ?? 0 }; s.active7 = week.map { active[$0] ?? 0 }; s.sleep7 = week.map { sleep[$0] ?? 0 }
        s.kcal7 = week.map { foodsOn($0).reduce(0) { $0 + $1.calories } }
        s.protein7 = week.map { foodsOn($0).reduce(0) { $0 + $1.protein } }
        s.workoutMin7 = week.map { logsOn($0).reduce(0) { $0 + $1.durationMinutes } }

        func f(_ v: Double, _ digits: Int = 0) -> String { v == 0 ? "no data" : String(format: "%.\(digits)f", v) }
        var lines: [String] = []
        lines.append("DAY UNDER REVIEW: \(d0.formatted(date: .complete, time: .omitted))")
        var goals = "GOALS: steps \(Int(profile.stepGoal)); active energy \(Int(profile.activeCalorieGoal)) kcal; exercise \(Int(profile.exerciseMinuteGoal)) min"
        goals += "; water \(profile.waterGoalLitres) L; calories \(Int(profile.calorieIntakeGoal)) kcal; protein \(Int(profile.proteinGoal)) g"
        if profile.targetWeightKg > 0 { goals += "; target weight \(profile.targetWeightKg) kg by \(profile.targetDate.formatted(date: .abbreviated, time: .omitted))" }
        lines.append(goals)
        var person: [String] = []
        if profile.heightCm > 0 { person.append("height \(Int(profile.heightCm)) cm") }
        if !profile.gender.isEmpty { person.append(profile.gender) }
        if let dob = profile.dateOfBirth, let age = cal.dateComponents([.year], from: dob, to: .now).year { person.append("age \(age)") }
        if s.weightKg > 0 { person.append("weight \(s.weightKg) kg") }
        if !person.isEmpty { lines.append("PERSON: " + person.joined(separator: ", ")) }
        if let scan = scans.first {
            var ib = "LATEST INBODY (\(scan.date.formatted(date: .abbreviated, time: .omitted))): weight \(scan.weightKg) kg, skeletal muscle \(scan.skeletalMuscleKg) kg"
            ib += ", body fat \(scan.bodyFatPercent)% (\(scan.bodyFatKg) kg), BMI \(scan.bmi), visceral fat \(scan.visceralFatLevel)"
            ib += ", BMR \(Int(scan.bmrKcal)) kcal, score \(Int(scan.inBodyScore))"
            lines.append(ib)
            if scans.count > 1 { let o = scans[1]; lines.append("PREVIOUS INBODY (\(o.date.formatted(date: .abbreviated, time: .omitted))): weight \(o.weightKg) kg, muscle \(o.skeletalMuscleKg) kg, fat \(o.bodyFatPercent)%") }
        }

        lines.append("")
        var dayLine = "THE DAY — sleep (night before) \(f(s.sleepHours, 1)) h; steps \(f(s.steps)); active energy \(f(s.activeKcal)) kcal"
        dayLine += "; exercise \(f(s.exerciseMin)) min; resting HR \(f(s.restingHR)); HRV \(f(s.hrv)) ms; water \(f(s.waterL, 1)) L"
        lines.append(dayLine)
        lines.append("FOOD — total \(Int(s.kcalEaten)) kcal, protein \(Int(s.protein)) g, carbs \(Int(s.carbs)) g, fat \(Int(s.fat)) g" + (dayFoods.isEmpty ? " (NOTHING LOGGED)" : ""))
        for e in dayFoods {
            lines.append("  \(e.date.formatted(date: .omitted, time: .shortened)) \(e.meal.title): \(e.name) \(e.quantity) — \(Int(e.calories)) kcal, P\(Int(e.protein)) C\(Int(e.carbs)) F\(Int(e.fat))")
        }
        lines.append("WORKOUTS — \(dayLogs.isEmpty ? "none logged" : "\(dayLogs.count)")")
        for log in dayLogs {
            let who = log.isPT ? "with personal trainer" : "self training"
            lines.append("  \(log.start.formatted(date: .omitted, time: .shortened)) \(log.name) (\(log.category)), \(Int(log.durationMinutes)) min, \(Int(log.calories)) kcal, \(who), source \(log.source)")
            for ex in log.exerciseNames.prefix(12) {
                let sets = log.orderedSets.filter { $0.exercise == ex }
                let detail = sets.map { set -> String in
                    if set.durationMinutes > 0 { return "\(Int(set.durationMinutes)) min" }
                    return set.weightKg > 0 ? "\(set.reps)x\(set.weightKg)kg" : "\(set.reps) reps"
                }.joined(separator: ", ")
                lines.append("    - \(ex): \(detail)")
            }
        }
        lines.append("SUPPLEMENTS — \(s.dosesTaken) of \(s.dosesPlanned) doses ticked")
        for sup in supplements.filter({ !$0.isFinished && !$0.isPaused }) {
            let taken = doses.filter { $0.supplementUID == sup.uid && cal.isDate($0.day, inSameDayAs: d0) }.map(\.slot)
            var line = "  \(sup.name) (\(sup.company)) \(sup.dose): \(sup.scheduleText)"
            line += "; times: " + sup.doseSlots.map(\.rawValue).joined(separator: ", ")
            line += "; suggested by \(sup.suggestedBy)"
            if !sup.purpose.isEmpty { line += "; for \(sup.purpose)" }
            if sup.isDue(on: d0) { line += "; taken this day: " + (taken.isEmpty ? "none" : taken.joined(separator: ", ")) }
            else { line += "; not due this day" }
            lines.append(line)
        }

        lines.append("")
        lines.append("LAST 7 DAYS (oldest → newest; 0 = no data): ")
        lines.append("  dates: " + week.map { $0.formatted(.dateTime.weekday(.abbreviated).day()) }.joined(separator: " | "))
        func row(_ name: String, _ v: [Double], _ digits: Int = 0) -> String { "  \(name): " + v.map { String(format: "%.\(digits)f", $0) }.joined(separator: " | ") }
        lines.append(row("steps", s.steps7)); lines.append(row("active kcal", s.active7)); lines.append(row("sleep h", s.sleep7, 1))
        lines.append(row("calories eaten", s.kcal7)); lines.append(row("protein g", s.protein7)); lines.append(row("workout min", s.workoutMin7))
        let recentW = measures.filter { $0.weightKg > 0 }.prefix(6).map { "\($0.date.formatted(.dateTime.day().month(.abbreviated))) \($0.weightKg)" }
        if !recentW.isEmpty { lines.append("  weight log (newest first): " + recentW.joined(separator: ", ")) }

        if !plans.isEmpty {
            lines.append("")
            lines.append("SAVED WORKOUT PLANS:")
            for p in plans.prefix(8) {
                let days = p.weekdays.map { cal.shortWeekdaySymbols[$0 - 1] }.joined(separator: "/")
                lines.append("  \(p.name) [\(p.focus), \(p.estimatedMinutes) min\(days.isEmpty ? "" : ", on \(days)")]: " + p.orderedExercises.prefix(8).map(\.name).joined(separator: ", "))
            }
        }
        return (lines.joined(separator: "\n"), s)
    }
}

// MARK: - Coordinator: at most one plan and one review a day

@MainActor
final class AICoordinator: ObservableObject {
    static let shared = AICoordinator()

    @Published var brief: MorningBrief?
    @Published var review: NightReview?
    @Published var reviewStats: DayStats?
    @Published var working: String?          // "morning" | "night" while a request is running
    @Published var error: String?

    @Published var autoMorning: Bool = (UserDefaults.standard.object(forKey: "aiAutoMorning") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(autoMorning, forKey: "aiAutoMorning"); scheduleNotifications() }
    }
    @Published var autoNight: Bool = (UserDefaults.standard.object(forKey: "aiAutoNight") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(autoNight, forKey: "aiAutoNight"); scheduleNotifications() }
    }
    /// Minutes after midnight.
    @Published var morningMinutes: Int = (UserDefaults.standard.object(forKey: "aiMorningMinutes") as? Int) ?? 7 * 60 {
        didSet { UserDefaults.standard.set(morningMinutes, forKey: "aiMorningMinutes"); scheduleNotifications() }
    }
    @Published var nightMinutes: Int = (UserDefaults.standard.object(forKey: "aiNightMinutes") as? Int) ?? 21 * 60 + 30 {
        didSet { UserDefaults.standard.set(nightMinutes, forKey: "aiNightMinutes"); scheduleNotifications() }
    }

    private var container: ModelContainer?
    private var lastAttempt: [String: Date] = [:]
    private let ai = AIService.shared
    private var today: Date { Calendar.current.startOfDay(for: .now) }

    func attach(_ container: ModelContainer) {
        self.container = container
        loadToday()
    }

    private func stored(day: Date, kind: String, in ctx: ModelContext) -> DailyReview? {
        let all = (try? ctx.fetch(FetchDescriptor<DailyReview>())) ?? []
        return all.filter { $0.kind == kind && Calendar.current.isDate($0.day, inSameDayAs: day) }.max { $0.createdAt < $1.createdAt }
    }

    /// Loads today's saved plan and review (no AI call).
    func loadToday() {
        guard let container else { return }
        let ctx = ModelContext(container)
        brief = stored(day: today, kind: "morning", in: ctx).flatMap { try? JSONDecoder().decode(MorningBrief.self, from: Data($0.payload.utf8)) }
        if let r = stored(day: today, kind: "night", in: ctx) {
            review = try? JSONDecoder().decode(NightReview.self, from: Data(r.payload.utf8))
            reviewStats = try? JSONDecoder().decode(DayStats.self, from: Data(r.stats.utf8))
        } else {
            review = nil; reviewStats = nil
        }
    }

    private func canAttempt(_ key: String) -> Bool {
        if let last = lastAttempt[key], Date.now.timeIntervalSince(last) < 30 * 60 { return false }
        return true
    }

    /// Called whenever the app comes to the front. Decides whether a plan or review is due — never more than one of each per day.
    func appBecameActive() async {
        guard ai.isOn, let container, working == nil else { return }
        loadToday()
        let ctx = ModelContext(container)
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: .now) * 60 + cal.component(.minute, from: .now)

        // Missed last night's review? Do it this morning, about yesterday.
        if autoNight, nowMin < 12 * 60, let yesterday = cal.date(byAdding: .day, value: -1, to: today),
           stored(day: yesterday, kind: "night", in: ctx) == nil, hasData(on: yesterday, in: ctx), canAttempt("night-y") {
            lastAttempt["night-y"] = .now
            await generateNight(for: yesterday)
        }
        if autoMorning, brief == nil, nowMin >= 5 * 60, canAttempt("morning") {
            lastAttempt["morning"] = .now
            await generateMorning()
        }
        if autoNight, review == nil, nowMin >= nightMinutes, canAttempt("night") {
            lastAttempt["night"] = .now
            await generateNight(for: today)
        }
    }

    private func hasData(on day: Date, in ctx: ModelContext) -> Bool {
        let cal = Calendar.current
        let foods = (try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let logs = (try? ctx.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        return foods.contains { cal.isDate($0.date, inSameDayAs: day) } || logs.contains { cal.isDate($0.start, inSameDayAs: day) }
    }

    private func save(day: Date, kind: String, headline: String, score: Int, payload: String, stats: DayStats, in ctx: ModelContext) {
        if let old = stored(day: day, kind: kind, in: ctx) { ctx.delete(old) }
        let r = DailyReview(day: Calendar.current.startOfDay(for: day), kind: kind)
        r.headline = headline; r.overallScore = score; r.payload = payload
        r.stats = (try? JSONEncoder().encode(stats)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        r.model = ai.model
        ctx.insert(r)
        try? ctx.save()
    }

    // MARK: Morning plan

    func generateMorning() async {
        guard ai.isOn, let container, working == nil else { return }
        working = "morning"; error = nil
        defer { working = nil }
        let ctx = ModelContext(container)
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let (yText, _) = await AIContext.build(day: yesterday, context: ctx, health: HealthKitManager.shared)
        let (tText, stats) = await AIContext.build(day: today, context: ctx, health: HealthKitManager.shared)
        let lastReview = stored(day: yesterday, kind: "night", in: ctx)?.headline ?? ""

        let system = """
        You are the daily coach inside iLife, one person's private health app in India. Using ONLY the data given, write today's plan.
        Return ONLY one JSON object (no prose, no code fence) with exactly these keys:
        {
          "headline": "one motivating sentence that mentions a real number from their data",
          "priorities": ["3 short, concrete actions for today, most important first"],
          "nutrition": {"summary": "1-2 sentences on yesterday's eating vs goals and today's aim", "tips": ["2-3 specific tips with amounts"]},
          "meals": [3 objects: {"name", "mealType": "Breakfast|Lunch|Dinner|Snack", "why": "one line", "calories", "protein", "carbs", "fat", "prepMinutes",
                     "ingredients": ["item with quantity"], "steps": ["4-7 short cooking steps"]}],
          "workout": {"title", "why": "one line tied to their sleep/recovery/last sessions", "durationMinutes",
                      "exercises": [{"name", "sets", "reps", "note"}]},
          "supplements": {"summary": "one line", "tips": ["what is due today and when; note doses missed yesterday"]},
          "recovery": {"summary": "one line on sleep/HRV/resting HR", "tips": ["1-2 tips"]},
          "health": {"summary": "1-2 sentences on weight/body-composition direction vs their target", "tips": ["1-2 tips"]}
        }
        Rules:
        - Meals: new, practical, high-protein (at least 25 g each), Indian home kitchen. Infer vegetarian / eggs / non-veg from what they log; when unsure give a mix. Realistic macros as numbers.
        - Workout: if a saved plan is scheduled for today's weekday, use it and adjust; otherwise design one from their history and equipment. 5-8 exercises. Make it lighter after short sleep or several hard days in a row; suggest a rest or mobility day when that's right.
        - Supplements: only talk about the ones they already take. Never suggest starting, stopping or changing the dose of anything; if something looks worth reviewing, say to ask their doctor.
        - If a data area shows "no data" or nothing logged, say so plainly and tell them what to log. Never invent numbers.
        - General fitness guidance only: no diagnosis, no medical claims. Keep every string short.
        """
        let user = """
        Now: \(Date.now.formatted(date: .complete, time: .shortened)).
        \(lastReview.isEmpty ? "" : "Last night's review headline: \(lastReview)\n")
        ===== YESTERDAY =====
        \(yText)

        ===== TODAY SO FAR =====
        \(tText)
        """
        do {
            let reply = try await ai.send(system: system, turns: [.init(role: "user", text: user)], maxTokens: 8000)
            let b = try ai.decode(MorningBrief.self, from: reply)
            let payload = (try? JSONEncoder().encode(b)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            save(day: today, kind: "morning", headline: b.headline ?? "Today's plan", score: 0, payload: payload, stats: stats, in: ctx)
            brief = b
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Night review

    func generateNight(for day: Date) async {
        guard ai.isOn, let container, working == nil else { return }
        working = "night"; error = nil
        defer { working = nil }
        let ctx = ModelContext(container)
        let (text, stats) = await AIContext.build(day: day, context: ctx, health: HealthKitManager.shared)
        let isToday = Calendar.current.isDateInToday(day)

        let system = """
        You are the daily coach inside iLife, one person's private health app in India. Review ONE day honestly, from the night's sleep
        through food, workouts, supplements and body readings, using ONLY the data given.
        Return ONLY one JSON object (no prose, no code fence) with exactly these keys:
        {
          "headline": "one honest sentence summing up the day, with a real number",
          "overallScore": 0-100,
          "scores": {"sleep": 0-100 or null, "activity": .., "nutrition": .., "hydration": .., "supplements": .., "recovery": ..},
          "wentWell": ["2-4 specific things, each with a number"],
          "improve": ["2-4 specific things, each with a number and the fix"],
          "sections": [{"title": "Sleep", "text": ".."}, {"title": "Activity & workout", "text": ".."}, {"title": "Nutrition", "text": ".."},
                       {"title": "Hydration", "text": ".."}, {"title": "Supplements", "text": ".."}, {"title": "Body & readings", "text": ".."}],
          "trends": "3-5 sentences describing what the 7-day numbers show: what is rising, falling or flat for steps, active energy, sleep, calories, protein and training time, and what that means",
          "tomorrow": ["3 concrete actions for tomorrow"]
        }
        Scoring: compare against their own goals (100 = goal fully met; scale down in proportion; sleep 100 = 7.5-9 h). Use null for any area with
        no data, and say in that section what to log. overallScore is the average of the areas that have data, rounded.
        Each section text is 2-3 short sentences. Mention when the food log looks incomplete (very low calories with few entries) instead of
        treating it as under-eating. For supplements, only report adherence to their own schedule; never advise starting, stopping or changing doses.
        General fitness guidance only: no diagnosis; for symptoms or abnormal readings say to see a doctor. Never invent numbers.
        """
        let user = "\(isToday ? "Review today (the day is ending now: \(Date.now.formatted(date: .omitted, time: .shortened)))." : "Review this day (it has ended).")\n\n\(text)"
        do {
            let reply = try await ai.send(system: system, turns: [.init(role: "user", text: user)], maxTokens: 8000)
            let r = try ai.decode(NightReview.self, from: reply)
            let payload = (try? JSONEncoder().encode(r)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            save(day: day, kind: "night", headline: r.headline ?? "Day review", score: Int(r.overallScore?.value ?? 0), payload: payload, stats: stats, in: ctx)
            if isToday { review = r; reviewStats = stats }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Notifications

    /// One nudge in the morning and one at night. The plan/review itself is written when you open the app.
    func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["ilife.ai.morning", "ilife.ai.night"])
        guard ai.isOn else { return }
        func add(_ id: String, _ minutes: Int, _ title: String, _ body: String) {
            let c = UNMutableNotificationContent()
            c.title = title; c.body = body; c.sound = .default
            var comps = DateComponents(); comps.hour = minutes / 60; comps.minute = minutes % 60
            center.add(UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
        }
        if autoMorning { add("ilife.ai.morning", morningMinutes, "Your plan for today", "Open iLife for today's meals, workout and priorities.") }
        if autoNight { add("ilife.ai.night", nightMinutes, "Your day review is ready", "Open iLife to see how today went, from sleep to workout, and tomorrow's focus.") }
    }
}
