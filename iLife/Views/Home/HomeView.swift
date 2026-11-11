import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var health: HealthKitManager
    @EnvironmentObject var session: WorkoutSessionController
    @Environment(\.modelContext) private var context
    @AppStorage("userName") private var userName = "Devendra"

    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \WaterEntry.date, order: .reverse) private var waters: [WaterEntry]
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @Query private var plans: [WorkoutPlan]
    @Query private var profiles: [HealthProfile]
    @Query(sort: \InBodyScan.date, order: .reverse) private var scans: [InBodyScan]

    private var profile: HealthProfile { profiles.first ?? HealthProfile() }
    private var todayFoods: [FoodEntry] { foods.filter { Calendar.current.isDateInToday($0.date) } }
    private var appWaterL: Double { waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.millilitres } / 1000 }
    private var waterL: Double { max(appWaterL, health.waterLitres) }
    private var todayMinutes: Double { max(health.exerciseMinutes, logs.filter { Calendar.current.isDateInToday($0.start) }.reduce(0) { $0 + $1.durationMinutes }) }
    private var todayPlan: WorkoutPlan? {
        let wd = Calendar.current.component(.weekday, from: .now)
        return plans.first { $0.weekdays.contains(wd) }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var readiness: Int {
        var score = 50.0
        score += health.sleepHours > 0 ? min(health.sleepHours / 8, 1) * 30 : 15
        score += health.hrv > 0 ? min(health.hrv / 60, 1) * 10 : 5
        score += health.restingHeartRate > 0 ? max(0, min(1, (80 - health.restingHeartRate) / 30)) * 10 : 5
        return Int(score.rounded())
    }

    private var readinessLabel: (String, Color) {
        switch readiness {
        case 85...: ("Excellent", .green)
        case 70..<85: ("Good", .mint)
        case 50..<70: ("Fair", .yellow)
        default: ("Take it easy", .orange)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                readinessCard
                AdaptiveGrid {
                    MetricTile(title: "Steps", value: health.steps.grouped, unit: "", icon: "shoeprints.fill", color: .cyan,
                               delta: percentChange(health.steps, health.stepsYesterday))
                    MetricTile(title: "Sleep", value: sleepText, unit: "", icon: "moon.fill", color: .indigo,
                               delta: percentChange(health.sleepHours, health.sleepYesterday))
                    MetricTile(title: "Heart Rate", value: health.heartRate.clean, unit: "bpm", icon: "heart.fill", color: .red)
                    MetricTile(title: "Hydration", value: String(format: "%.1f", waterL), unit: "L", icon: "drop.fill", color: .blue)
                    MetricTile(title: "Calories", value: health.activeCalories.grouped, unit: "kcal", icon: "flame.fill", color: .orange)
                    MetricTile(title: "Workout", value: todayMinutes.clean, unit: "min", icon: "dumbbell.fill", color: .purple)
                }
                todayWorkoutCard
                nutritionCard
                if profile.targetWeightKg > 0 { goalCard }
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await health.refreshToday()
            await health.importWorkouts(into: context, notify: false)
            pushWidget()
        }
        .task { pushWidget() }
        .onChange(of: health.steps) { _, _ in pushWidget() }
    }

    private var sleepText: String {
        guard health.sleepHours > 0 else { return "–" }
        let h = Int(health.sleepHours), m = Int((health.sleepHours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(greeting),").font(.title2.weight(.semibold))
                Text("\(userName) 👋").font(.title.bold())
            }
            Spacer()
            ILifeLogo(size: 48)
        }
        .padding(.top, 8)
    }

    private var readinessCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your Readiness Score").font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(readiness)").font(.system(size: 46, weight: .bold, design: .rounded))
                    Text("/100").foregroundStyle(.secondary)
                }
                Label(readinessLabel.0, systemImage: "checkmark.seal.fill").font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 4).background(readinessLabel.1.opacity(0.25), in: Capsule())
                Text("Based on sleep, HRV and resting heart rate").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            ZStack {
                ProgressRing(progress: Double(readiness) / 100, color: readinessLabel.1, lineWidth: 12)
                Image(systemName: "figure.run").font(.title).foregroundStyle(readinessLabel.1)
            }
            .frame(width: 96, height: 96)
        }
        .glassCard()
    }

    private var todayWorkoutCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional").font(.largeTitle).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Workout").font(.headline)
                if let p = todayPlan {
                    Text(p.name).font(.subheadline)
                    Text("\(p.estimatedMinutes) min · \(p.orderedExercises.count) exercises").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No plan scheduled — quick start one").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                if let p = todayPlan {
                    session.start(name: p.name, category: p.focus.contains("Cardio") ? "Cardio" : "Strength",
                                  exercises: p.orderedExercises.map(\.name))
                } else {
                    session.start(name: "Quick Workout", category: "Strength", exercises: [])
                }
            } label: {
                Image(systemName: "play.fill").font(.title2).frame(width: 52, height: 52)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
            .disabled(session.isActive)
        }
        .glassCard()
    }

    private var nutritionCard: some View {
        let kcal = todayFoods.reduce(0) { $0 + $1.calories }
        let p = todayFoods.reduce(0) { $0 + $1.protein }
        let c = todayFoods.reduce(0) { $0 + $1.carbs }
        let f = todayFoods.reduce(0) { $0 + $1.fat }
        let progress = kcal / max(profile.calorieIntakeGoal, 1)
        return HStack(spacing: 18) {
            ZStack {
                ProgressRing(progress: progress, color: .green, lineWidth: 10)
                VStack(spacing: 0) {
                    Text("\(Int(progress * 100))%").font(.headline)
                    Text("of goal").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)
            VStack(alignment: .leading, spacing: 6) {
                Text("Nutrition Today").font(.headline)
                Text("\(Int(kcal)) / \(Int(profile.calorieIntakeGoal)) kcal").font(.subheadline)
                HStack(spacing: 12) {
                    macro("Protein", p, .cyan); macro("Carbs", c, .yellow); macro("Fat", f, .pink)
                }
            }
            Spacer()
        }
        .glassCard()
    }

    private func macro(_ name: String, _ g: Double, _ color: Color) -> some View {
        VStack(alignment: .leading) {
            Text("\(Int(g)) g").font(.caption.bold())
            Text(name).font(.caption2).foregroundStyle(color)
        }
    }

    private var goalCard: some View {
        let current = scans.first?.weightKg ?? health.weightKg
        let start = profile.startWeightKg > 0 ? profile.startWeightKg : current
        let total = abs(start - profile.targetWeightKg)
        let done = total > 0 ? min(1, abs(start - current) / total) : 0
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Goal", trailing: profile.targetDate.formatted(date: .abbreviated, time: .omitted))
            Text("Reach \(profile.targetWeightKg.clean) kg").font(.subheadline)
            ProgressView(value: done).tint(.cyan)
            Text("Now \(current.clean) kg · \(Int(done * 100))% there").font(.caption).foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private func pushWidget() {
        WidgetSync.push(TodaySnapshot(
            steps: health.steps, stepGoal: profile.stepGoal,
            activeCalories: health.activeCalories, calorieGoal: profile.activeCalorieGoal,
            exerciseMinutes: todayMinutes, exerciseGoal: profile.exerciseMinuteGoal,
            waterLitres: waterL, waterGoal: profile.waterGoalLitres,
            caloriesEaten: todayFoods.reduce(0) { $0 + $1.calories }, calorieIntakeGoal: profile.calorieIntakeGoal,
            updated: .now))
    }
}
