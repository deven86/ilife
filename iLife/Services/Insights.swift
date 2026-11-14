import SwiftUI
import SwiftData

/// Things the user can do in one tap from Home or from a coach card.
enum QuickAction: String, Identifiable, CaseIterable {
    case food, mealPhoto, water, workout, weight, photo, inbody, coach, trends, gym
    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: "Log Food"
        case .mealPhoto: "Snap Meal"
        case .water: "Water"
        case .workout: "Workout"
        case .weight: "Weight"
        case .photo: "Progress"
        case .inbody: "InBody"
        case .coach: "Coach"
        case .trends: "Trends"
        case .gym: "Gym"
        }
    }

    var icon: String {
        switch self {
        case .food: "fork.knife"
        case .mealPhoto: "camera.viewfinder"
        case .water: "drop.fill"
        case .workout: "dumbbell.fill"
        case .weight: "scalemass.fill"
        case .photo: "figure.stand"
        case .inbody: "doc.viewfinder"
        case .coach: "sparkles"
        case .trends: "chart.xyaxis.line"
        case .gym: "building.2.fill"
        }
    }

    var color: Color {
        switch self {
        case .food: .green
        case .mealPhoto: .mint
        case .water: .blue
        case .workout: .orange
        case .weight: .purple
        case .photo: .pink
        case .inbody: .cyan
        case .coach: .yellow
        case .trends: .indigo
        case .gym: .teal
        }
    }
}

struct Insight: Identifiable {
    let id: String
    let icon: String
    let color: Color
    let title: String
    let message: String
    /// Higher = shown first.
    let priority: Int
    var action: QuickAction? = nil
    var actionLabel: String? = nil
}

/// Plain numbers the engine reasons over, so it has no dependency on the UI or database.
struct InsightInput {
    var now = Date.now
    var steps = 0.0, stepGoal = 10_000.0
    var activeKcal = 0.0, activeGoal = 600.0
    var exerciseMin = 0.0, exerciseGoal = 45.0
    var sleepHours = 0.0, hrv = 0.0, restingHR = 0.0
    var kcalEaten = 0.0, kcalGoal = 2200.0
    var protein = 0.0, proteinGoal = 120.0
    var waterL = 0.0, waterGoal = 3.0
    var foodsLoggedToday = 0
    var workoutDays: [Date] = []          // start dates of all workouts
    var ptPaid = 0, ptDone = 0
    var membershipDaysLeft: Int? = nil
    var gymName = ""
    var lastInBody: Date? = nil
    var weights: [DayValue] = []          // oldest → newest
    var targetWeight = 0.0
    var photoToday = false
    var photoCount = 0
}

enum InsightsEngine {
    static func workoutStreak(_ dates: [Date], now: Date = .now) -> Int {
        let cal = Calendar.current
        let days = Set(dates.map { cal.startOfDay(for: $0) })
        var d = cal.startOfDay(for: now)
        if !days.contains(d) { d = cal.date(byAdding: .day, value: -1, to: d)! }
        var n = 0
        while days.contains(d) { n += 1; d = cal.date(byAdding: .day, value: -1, to: d)! }
        return n
    }

    /// kg per week from a simple least-squares fit over the last 30 days.
    static func weeklyWeightChange(_ weights: [DayValue], now: Date = .now) -> Double? {
        let recent = weights.filter { $0.date > now.addingTimeInterval(-30 * 86400) }
        guard recent.count >= 2, let first = recent.first, let last = recent.last,
              last.date.timeIntervalSince(first.date) > 5 * 86400 else { return nil }
        let xs = recent.map { $0.date.timeIntervalSince(first.date) / 86400 }
        let ys = recent.map(\.value)
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        var num = 0.0, den = 0.0
        for i in xs.indices { num += (xs[i] - mx) * (ys[i] - my); den += (xs[i] - mx) * (xs[i] - mx) }
        guard den > 0 else { return nil }
        return num / den * 7
    }

    static func generate(_ i: InsightInput) -> [Insight] {
        var out: [Insight] = []
        let cal = Calendar.current
        let hour = Double(cal.component(.hour, from: i.now)) + Double(cal.component(.minute, from: i.now)) / 60
        // Share of the waking day (6 am – 10 pm) that has passed.
        let dayProgress = min(max((hour - 6) / 16, 0), 1)

        // Recovery
        if i.sleepHours > 0 && i.sleepHours < 6 {
            let h = Int(i.sleepHours), m = Int((i.sleepHours - Double(h)) * 60)
            out.append(Insight(id: "sleep.low", icon: "moon.zzz.fill", color: .indigo, title: "Short night: \(h)h \(m)m",
                               message: "Recovery is lower today. Keep the workout lighter, skip max lifts, and aim to be in bed 45 minutes earlier tonight.", priority: 95))
        } else if i.sleepHours >= 7.5 && (i.hrv == 0 || i.hrv >= 40) {
            out.append(Insight(id: "sleep.good", icon: "bolt.heart.fill", color: .green, title: "Well recovered",
                               message: "You slept \(String(format: "%.1f", i.sleepHours)) hours. Good day to push a little harder or add a set.", priority: 55,
                               action: .workout, actionLabel: "Start workout"))
        }

        // Steps
        if i.steps >= i.stepGoal && i.stepGoal > 0 {
            out.append(Insight(id: "steps.done", icon: "figure.walk.motion", color: .cyan, title: "Step goal done",
                               message: "\(Int(i.steps).formatted()) steps today. Anything more is a bonus.", priority: 40))
        } else if hour >= 12 && i.stepGoal > 0 {
            let expected = i.stepGoal * dayProgress
            let behind = expected - i.steps
            if behind > 1500 {
                let minutes = Int((i.stepGoal - i.steps) / 100)
                out.append(Insight(id: "steps.behind", icon: "figure.walk", color: .cyan, title: "\(Int(behind).formatted()) steps behind pace",
                                   message: "You're at \(Int(i.steps).formatted()) of \(Int(i.stepGoal).formatted()). About \(min(minutes, 90)) minutes of walking closes it — try a 15-minute walk after each meal.", priority: 70))
            }
        }

        // Food logging + protein + calories
        if i.foodsLoggedToday == 0 && hour >= 11 {
            out.append(Insight(id: "food.none", icon: "fork.knife", color: .green, title: "Nothing logged yet today",
                               message: "Log what you've eaten so far — it takes seconds, and the numbers only help if they're complete.", priority: 85,
                               action: .food, actionLabel: "Log food"))
        } else if i.proteinGoal > 0 {
            let left = i.proteinGoal - i.protein
            if hour >= 14 && i.protein < i.proteinGoal * 0.55 {
                out.append(Insight(id: "protein.low", icon: "bolt.fill", color: .orange, title: "\(Int(left)) g protein to go",
                                   message: "You're at \(Int(i.protein)) g of \(Int(i.proteinGoal)) g. Easy wins: whey scoop 24 g, 100 g paneer 18 g, 3 eggs 18 g, 150 g chicken 45 g.", priority: 80,
                                   action: .food, actionLabel: "Log food"))
            } else if left <= 0 {
                out.append(Insight(id: "protein.done", icon: "checkmark.seal.fill", color: .green, title: "Protein target hit",
                                   message: "\(Int(i.protein)) g today. That's what builds and keeps muscle.", priority: 35))
            }
        }
        if i.kcalGoal > 0 && i.kcalEaten > i.kcalGoal * 1.1 {
            out.append(Insight(id: "kcal.over", icon: "flame.fill", color: .red, title: "\(Int(i.kcalEaten - i.kcalGoal)) kcal over target",
                               message: "One day doesn't matter much. Keep dinner light and add a walk; the weekly average is what counts.", priority: 65))
        }

        // Water
        if i.waterGoal > 0 {
            let expected = i.waterGoal * dayProgress
            if hour >= 10 && expected - i.waterL > 0.6 {
                out.append(Insight(id: "water.behind", icon: "drop.fill", color: .blue, title: "Drink up",
                                   message: String(format: "%.1f L of %.1f L so far. Two glasses now puts you back on pace.", i.waterL, i.waterGoal), priority: 60,
                                   action: .water, actionLabel: "+250 ml"))
            }
        }

        // Training consistency
        let streak = workoutStreak(i.workoutDays, now: i.now)
        let weekStart = i.now.addingTimeInterval(-7 * 86400)
        let weekCount = Set(i.workoutDays.filter { $0 > weekStart }.map { cal.startOfDay(for: $0) }).count
        if streak >= 3 {
            out.append(Insight(id: "streak", icon: "flame.fill", color: .orange, title: "\(streak)-day streak",
                               message: "Consistency beats intensity. Keep it going — even a 20-minute session counts.", priority: 50))
        }
        if let last = i.workoutDays.max() {
            let gap = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: i.now)).day ?? 0
            if gap >= 3 {
                out.append(Insight(id: "workout.gap", icon: "figure.strengthtraining.traditional", color: .orange, title: "\(gap) days since your last workout",
                                   message: "Start small today: 20 minutes, three exercises. Getting back in is the hard part.", priority: 75,
                                   action: .workout, actionLabel: "Start workout"))
            }
        } else {
            out.append(Insight(id: "workout.first", icon: "figure.strengthtraining.traditional", color: .orange, title: "Log your first workout",
                               message: "Pick a plan or just start a quick session — iLife will track the rest.", priority: 60,
                               action: .workout, actionLabel: "Start workout"))
        }
        if weekCount >= 4 {
            out.append(Insight(id: "week.good", icon: "calendar.badge.checkmark", color: .green, title: "\(weekCount) training days this week",
                               message: "Strong week. Make sure one day is real rest.", priority: 30))
        }

        // Gym
        if i.ptPaid > 0 {
            let left = i.ptPaid - i.ptDone
            if left <= 2 {
                out.append(Insight(id: "pt.left", icon: "person.2.fill", color: .orange,
                                   title: left > 0 ? "\(left) personal-training session\(left == 1 ? "" : "s") left" : "PT package used up",
                                   message: "You've done \(i.ptDone) of \(i.ptPaid) paid sessions. Renew or plan your self-training.", priority: 68,
                                   action: .gym, actionLabel: "Open Gym"))
            }
        }
        if let d = i.membershipDaysLeft {
            if d < 0 {
                out.append(Insight(id: "gym.expired", icon: "building.2.fill", color: .red, title: "Gym membership expired",
                                   message: "\(i.gymName.isEmpty ? "Your membership" : i.gymName) ended \(-d) day\(d == -1 ? "" : "s") ago.", priority: 78, action: .gym, actionLabel: "Open Gym"))
            } else if d <= 15 {
                out.append(Insight(id: "gym.expiring", icon: "building.2.fill", color: .orange, title: "Membership ends in \(d) day\(d == 1 ? "" : "s")",
                                   message: "Renewal offers are usually better before expiry than after.", priority: 66, action: .gym, actionLabel: "Open Gym"))
            }
        }

        // Body
        if let change = weeklyWeightChange(i.weights, now: i.now), let current = i.weights.last?.value {
            let dir = change < 0 ? "down" : "up"
            var msg = String(format: "Trend: %.2f kg %@ per week over the last month.", abs(change), dir)
            if i.targetWeight > 0 {
                let remaining = i.targetWeight - current
                if abs(remaining) < 0.3 {
                    msg += " You're at your target weight."
                } else if (remaining < 0) == (change < 0) && abs(change) > 0.05 {
                    let weeks = Int((remaining / change).rounded(.up))
                    msg += " At this pace you reach \(i.targetWeight.clean) kg in about \(weeks) week\(weeks == 1 ? "" : "s")."
                } else {
                    msg += " That's moving away from your \(i.targetWeight.clean) kg target."
                }
            }
            if abs(change) > 1.0 { msg += " More than 1 kg a week is fast — make sure protein and sleep are in place." }
            out.append(Insight(id: "weight.trend", icon: "chart.line.uptrend.xyaxis", color: .purple, title: "Weight \(dir) \(String(format: "%.1f", abs(change))) kg/week",
                               message: msg, priority: 58, action: .trends, actionLabel: "See trends"))
        }
        if let last = i.lastInBody {
            let days = cal.dateComponents([.day], from: last, to: i.now).day ?? 0
            if days >= 30 {
                out.append(Insight(id: "inbody.due", icon: "doc.viewfinder", color: .cyan, title: "Time for a new InBody test",
                                   message: "Your last test was \(days) days ago. Test at the same time of day, before eating, for a fair comparison.", priority: 45,
                                   action: .inbody, actionLabel: "Scan result"))
            }
        }
        if !i.photoToday && hour < 12 {
            out.append(Insight(id: "photo.today", icon: "camera.fill", color: .pink, title: i.photoCount == 0 ? "Start your transformation album" : "Today's progress photo",
                               message: "Morning light, same spot, same pose. Ten seconds.", priority: 42, action: .photo, actionLabel: "Take photo"))
        }

        if out.isEmpty {
            out.append(Insight(id: "ok", icon: "checkmark.circle.fill", color: .green, title: "Everything's on track",
                               message: "Keep logging food, water and workouts — the more complete the data, the sharper the coaching.", priority: 1))
        }
        return out.sorted { $0.priority > $1.priority }
    }
}

// MARK: - Per-exercise history (last session, best lift)

struct ExerciseHistory {
    var lastSummary: String?
    var bestKg: Double = 0
    var best1RM: Double = 0

    /// `sets` = every set ever logged; `excluding` = the workout being edited.
    static func make(for exercise: String, sets: [ExerciseSet], excluding: WorkoutLog?) -> ExerciseHistory {
        let mine = sets.filter { $0.exercise.caseInsensitiveCompare(exercise) == .orderedSame && $0.log != nil && $0.log?.persistentModelID != excluding?.persistentModelID }
        guard !mine.isEmpty else { return ExerciseHistory() }
        var h = ExerciseHistory()
        h.bestKg = mine.map(\.weightKg).max() ?? 0
        h.best1RM = mine.map { $0.weightKg * (1 + Double($0.reps) / 30) }.max() ?? 0
        if let lastLog = mine.compactMap(\.log).max(by: { $0.start < $1.start }) {
            let lastSets = mine.filter { $0.log?.persistentModelID == lastLog.persistentModelID }.sorted { $0.order < $1.order }
            if let cardio = lastSets.first, cardio.durationMinutes > 0 {
                h.lastSummary = "\(Int(cardio.durationMinutes)) min" + (cardio.distanceKm > 0 ? " · \(cardio.distanceKm.clean) km" : "")
            } else {
                let parts = lastSets.filter { $0.reps > 0 }.map { $0.weightKg > 0 ? "\($0.reps)×\($0.weightKg.clean)" : "\($0.reps)" }
                if !parts.isEmpty { h.lastSummary = parts.prefix(5).joined(separator: ", ") + (parts.contains { $0.contains("×") } ? " kg" : " reps") }
            }
        }
        return h
    }
}

// MARK: - Achievements

struct Achievement: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let progress: Double      // 0…1
    var unlocked: Bool { progress >= 1 }
}

enum Achievements {
    static func all(workouts: Int, streak: Int, bestStreak: Int, photos: Int, scans: Int, foodDays: Int, bestSteps: Double,
                    totalMinutes: Double, ptSessions: Int, prs: Int) -> [Achievement] {
        func p(_ v: Double, _ goal: Double) -> Double { min(v / goal, 1) }
        return [
            Achievement(id: "w1", icon: "figure.strengthtraining.traditional", title: "First Rep", detail: "Log your first workout", progress: p(Double(workouts), 1)),
            Achievement(id: "w10", icon: "dumbbell.fill", title: "Regular", detail: "10 workouts", progress: p(Double(workouts), 10)),
            Achievement(id: "w50", icon: "medal.fill", title: "Committed", detail: "50 workouts", progress: p(Double(workouts), 50)),
            Achievement(id: "w100", icon: "trophy.fill", title: "Century", detail: "100 workouts", progress: p(Double(workouts), 100)),
            Achievement(id: "s3", icon: "flame", title: "Warming Up", detail: "3-day workout streak", progress: p(Double(max(streak, bestStreak)), 3)),
            Achievement(id: "s7", icon: "flame.fill", title: "On Fire", detail: "7-day workout streak", progress: p(Double(max(streak, bestStreak)), 7)),
            Achievement(id: "s30", icon: "flame.circle.fill", title: "Unstoppable", detail: "30-day workout streak", progress: p(Double(max(streak, bestStreak)), 30)),
            Achievement(id: "st10", icon: "figure.walk", title: "10K Day", detail: "10,000 steps in a day", progress: p(bestSteps, 10_000)),
            Achievement(id: "st20", icon: "figure.hiking", title: "Explorer", detail: "20,000 steps in a day", progress: p(bestSteps, 20_000)),
            Achievement(id: "t600", icon: "clock.fill", title: "10 Hours", detail: "600 minutes of training", progress: p(totalMinutes, 600)),
            Achievement(id: "t3000", icon: "clock.badge.checkmark.fill", title: "50 Hours", detail: "3,000 minutes of training", progress: p(totalMinutes, 3000)),
            Achievement(id: "f7", icon: "fork.knife", title: "Food Diary", detail: "Log food on 7 days", progress: p(Double(foodDays), 7)),
            Achievement(id: "f30", icon: "leaf.fill", title: "Nutrition Pro", detail: "Log food on 30 days", progress: p(Double(foodDays), 30)),
            Achievement(id: "p1", icon: "camera.fill", title: "Day One", detail: "First progress photo", progress: p(Double(photos), 1)),
            Achievement(id: "p30", icon: "photo.stack.fill", title: "Transformation", detail: "30 progress photos", progress: p(Double(photos), 30)),
            Achievement(id: "ib1", icon: "doc.viewfinder", title: "Know Your Body", detail: "First InBody scan", progress: p(Double(scans), 1)),
            Achievement(id: "ib4", icon: "chart.line.uptrend.xyaxis", title: "Data Driven", detail: "4 InBody scans", progress: p(Double(scans), 4)),
            Achievement(id: "pt10", icon: "person.2.fill", title: "Coached", detail: "10 personal-training sessions", progress: p(Double(ptSessions), 10)),
            Achievement(id: "pr1", icon: "arrow.up.circle.fill", title: "Stronger", detail: "Set a personal record", progress: p(Double(prs), 1)),
            Achievement(id: "pr10", icon: "star.circle.fill", title: "Record Breaker", detail: "10 personal records", progress: p(Double(prs), 10)),
        ]
    }

    static func bestStreak(_ dates: [Date]) -> Int {
        let cal = Calendar.current
        let days = Set(dates.map { cal.startOfDay(for: $0) }).sorted()
        var best = 0, run = 0
        var prev: Date?
        for d in days {
            if let p = prev, cal.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run); prev = d
        }
        return best
    }
}
