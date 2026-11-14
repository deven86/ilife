import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var health: HealthKitManager
    @EnvironmentObject var session: WorkoutSessionController
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.modelContext) private var context
    @AppStorage("userName") private var userName = "Devendra"

    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \WaterEntry.date, order: .reverse) private var waters: [WaterEntry]
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @Query private var plans: [WorkoutPlan]
    @Query private var profiles: [HealthProfile]
    @Query(sort: \InBodyScan.date, order: .reverse) private var scans: [InBodyScan]
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var progress: [ProgressPhoto]
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
    @Query private var memberships: [GymMembership]
    @Query private var payments: [GymPayment]

    @State private var profileForSheet: HealthProfile?
    @State private var action: QuickAction?
    @State private var showTrends = false
    @State private var showAchievements = false

    // MARK: Derived values

    private var profile: HealthProfile { profiles.first ?? HealthProfile() }
    private var displayName: String {
        if let f = profiles.first?.firstName, !f.isEmpty { return f }
        return userName.isEmpty ? "there" : userName
    }
    private var todayFoods: [FoodEntry] { foods.filter { Calendar.current.isDateInToday($0.date) } }
    private var appWaterL: Double { waters.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.millilitres } / 1000 }
    private var waterL: Double { max(appWaterL, health.waterLitres) }
    private var todayMinutes: Double { max(health.exerciseMinutes, logs.filter { Calendar.current.isDateInToday($0.start) }.reduce(0) { $0 + $1.durationMinutes }) }
    private var kcalEaten: Double { todayFoods.reduce(0) { $0 + $1.calories } }
    private var proteinEaten: Double { todayFoods.reduce(0) { $0 + $1.protein } }
    private var streak: Int { InsightsEngine.workoutStreak(logs.map(\.start)) }
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

    private var weightSeries: [DayValue] {
        var all = scans.filter { $0.weightKg > 0 }.map { DayValue(date: $0.date, value: $0.weightKg) }
        all += measurements.filter { $0.weightKg > 0 }.map { DayValue(date: $0.date, value: $0.weightKg) }
        return all.sorted { $0.date < $1.date }
    }

    private var insights: [Insight] {
        var i = InsightInput()
        i.steps = health.steps; i.stepGoal = profile.stepGoal
        i.activeKcal = health.activeCalories; i.activeGoal = profile.activeCalorieGoal
        i.exerciseMin = todayMinutes; i.exerciseGoal = profile.exerciseMinuteGoal
        i.sleepHours = health.sleepHours; i.hrv = health.hrv; i.restingHR = health.restingHeartRate
        i.kcalEaten = kcalEaten; i.kcalGoal = profile.calorieIntakeGoal
        i.protein = proteinEaten; i.proteinGoal = profile.proteinGoal
        i.waterL = waterL; i.waterGoal = profile.waterGoalLitres
        i.foodsLoggedToday = todayFoods.count
        i.workoutDays = logs.map(\.start)
        i.ptPaid = payments.filter { $0.kind == .personalTraining }.reduce(0) { $0 + $1.sessionsIncluded }
        i.ptDone = logs.filter(\.isPT).count
        if let m = memberships.max(by: { $0.endDate < $1.endDate }) { i.membershipDaysLeft = m.daysLeft; i.gymName = m.gymName }
        i.lastInBody = scans.first?.date
        i.weights = weightSeries
        i.targetWeight = profile.targetWeightKg
        i.photoToday = progress.contains { Calendar.current.isDateInToday($0.date) }
        i.photoCount = progress.count
        return InsightsEngine.generate(i)
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header.appear(0)
                heroCard.appear(1)
                coachCarousel.appear(2)
                quickActions.appear(3)
                tiles.appear(4)
                todayWorkoutCard.appear(5)
                TransformationCard(photos: progress).appear(6)
                nutritionCard.appear(7)
                if profile.targetWeightKg > 0 { goalCard.appear(8) }
                exploreRow.appear(9)
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
            Haptics.tap()
        }
        .task { pushWidget(); checkGoals() }
        .onChange(of: health.steps) { _, _ in pushWidget(); checkGoals() }
        .onChange(of: proteinEaten) { _, _ in checkGoals() }
        .onChange(of: waterL) { _, _ in checkGoals() }
        .sheet(item: $profileForSheet) { p in NavigationStack { ProfileView(profile: p) } }
        .sheet(item: $action) { sheet(for: $0) }
        .navigationDestination(isPresented: $showTrends) { TrendsView() }
        .navigationDestination(isPresented: $showAchievements) { AchievementsView() }
    }

    private func checkGoals() {
        let c = Celebration.shared
        if profile.stepGoal > 0 && health.steps >= profile.stepGoal {
            c.fireOncePerDay(key: "steps", "Step goal smashed", subtitle: "\(Int(health.steps).formatted()) steps today", icon: "figure.walk.motion")
        }
        if profile.proteinGoal > 0 && proteinEaten >= profile.proteinGoal {
            c.fireOncePerDay(key: "protein", "Protein target hit", subtitle: "\(Int(proteinEaten)) g today", icon: "bolt.fill")
        }
        if profile.waterGoalLitres > 0 && waterL >= profile.waterGoalLitres {
            c.fireOncePerDay(key: "water", "Fully hydrated", subtitle: String(format: "%.1f L today", waterL), icon: "drop.fill")
        }
    }

    private func perform(_ a: QuickAction) {
        Haptics.tap()
        switch a {
        case .water:
            context.insert(WaterEntry(millilitres: 250))
            try? context.save()
            Task { await health.saveWater(ml: 250) }
            Haptics.success()
        case .trends: showTrends = true
        case .workout where session.isActive: break
        default: action = a
        }
    }

    @ViewBuilder
    private func sheet(for a: QuickAction) -> some View {
        switch a {
        case .food: AddFoodSheet(meal: MealType.suggested(), date: .now)
        case .mealPhoto: MealPhotoAISheet()
        case .workout: QuickStartSheet()
        case .weight: WeightLogSheet()
        case .photo: CaptureProgressSheet(defaultWeight: health.weightKg)
        case .inbody: InBodyImportView()
        case .coach: NavigationStack { CoachView() }
        case .gym:
            NavigationStack {
                ScrollView { GymSection().padding() }
                    .iLifeScreen().navigationTitle("Gym").navigationBarTitleDisplayMode(.inline)
            }
        default: EmptyView()
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .font(.caption2.bold()).foregroundStyle(.secondary).kerning(1.2)
                Text("\(greeting),").font(.title3.weight(.medium))
                Text(displayName).font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.current.gradient)
            }
            Spacer()
            if streak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").foregroundStyle(.orange).symbolEffect(.pulse)
                    Text("\(streak)").font(.headline.monospacedDigit())
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
            Button { profileForSheet = ensureProfile(context) } label: {
                AvatarView(data: profiles.first?.avatar, name: profiles.first?.fullName.isEmpty == false ? profiles.first!.fullName : userName, size: 54)
            }
            .buttonStyle(PressStyle())
        }
        .padding(.top, 8)
    }

    private var heroCard: some View {
        HStack(spacing: 18) {
            ZStack {
                ProgressRing(progress: health.activeCalories / max(profile.activeCalorieGoal, 1), color: .orange, lineWidth: 13)
                ProgressRing(progress: todayMinutes / max(profile.exerciseMinuteGoal, 1), color: .green, lineWidth: 13).padding(16)
                ProgressRing(progress: health.steps / max(profile.stepGoal, 1), color: .cyan, lineWidth: 13).padding(32)
                VStack(spacing: 0) {
                    Text("\(readiness)").font(.system(size: 26, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("ready").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)
            .glow(theme.current.accent.opacity(0.6))

            VStack(alignment: .leading, spacing: 10) {
                ringRow("Move", "\(Int(health.activeCalories))", "/ \(Int(profile.activeCalorieGoal)) kcal", .orange, "flame.fill")
                ringRow("Exercise", "\(Int(todayMinutes))", "/ \(Int(profile.exerciseMinuteGoal)) min", .green, "figure.run")
                ringRow("Steps", Int(health.steps).formatted(), "/ \(Int(profile.stepGoal).formatted())", .cyan, "shoeprints.fill")
                Label(readinessLabel.0, systemImage: "checkmark.seal.fill").font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(readinessLabel.1.opacity(0.25), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .glassCard()
    }

    private func ringRow(_ title: String, _ value: String, _ goal: String, _ color: Color, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(color).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.headline.monospacedDigit()).contentTransition(.numericText())
                    Text(goal).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var coachCarousel: some View {
        let items = Array(insights.prefix(6))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Coach", systemImage: "sparkles").font(.headline)
                Spacer()
                Button { perform(.coach) } label: { Label("Ask", systemImage: "bubble.left.and.text.bubble.right.fill").font(.caption.bold()) }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { insight in
                        InsightCard(insight: insight) { if let a = insight.action { perform(a) } }
                            .containerRelativeFrame(.horizontal, count: 10, span: 9, spacing: 12)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var quickActions: some View {
        let actions: [QuickAction] = [.food, .mealPhoto, .water, .workout, .weight, .photo, .inbody, .trends]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
            ForEach(actions) { a in
                Button { perform(a) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: a.icon).font(.title3).foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(LinearGradient(colors: [a.color, a.color.opacity(0.6)], startPoint: .top, endPoint: .bottom), in: Circle())
                            .shadow(color: a.color.opacity(0.45), radius: 8, y: 3)
                        Text(a.title).font(.caption2.weight(.medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressStyle())
            }
        }
        .glassCard(padding: 14)
    }

    private var tiles: some View {
        AdaptiveGrid {
            MetricTile(title: "Sleep", value: sleepText, unit: "", icon: "moon.fill", color: .indigo,
                       delta: percentChange(health.sleepHours, health.sleepYesterday))
            MetricTile(title: "Heart Rate", value: health.heartRate.clean, unit: "bpm", icon: "heart.fill", color: .red)
            MetricTile(title: "Hydration", value: String(format: "%.1f", waterL), unit: "/ \(profile.waterGoalLitres.clean) L", icon: "drop.fill", color: .blue)
            MetricTile(title: "Weight", value: (weightSeries.last?.value ?? health.weightKg).clean, unit: "kg", icon: "scalemass.fill", color: .purple)
        }
    }

    private var sleepText: String {
        guard health.sleepHours > 0 else { return "–" }
        let h = Int(health.sleepHours), m = Int((health.sleepHours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    private var todayWorkoutCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional").font(.largeTitle).foregroundStyle(theme.current.gradient)
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
                Haptics.thump()
                if let p = todayPlan {
                    session.start(name: p.name, category: p.focus.contains("Cardio") ? "Cardio" : "Strength",
                                  exercises: p.orderedExercises.map(\.name), photos: p.orderedExercises.map(\.photo), equipment: p.orderedExercises.map(\.equipment))
                } else {
                    session.start(name: "Quick Workout", category: "Strength", exercises: [])
                }
            } label: {
                Image(systemName: "play.fill").font(.title2).foregroundStyle(.white).frame(width: 56, height: 56)
                    .background(theme.current.gradient, in: Circle())
            }
            .buttonStyle(PressStyle())
            .glow(theme.current.accent)
            .disabled(session.isActive)
        }
        .glassCard()
    }

    private var nutritionCard: some View {
        let c = todayFoods.reduce(0) { $0 + $1.carbs }
        let f = todayFoods.reduce(0) { $0 + $1.fat }
        let progress = kcalEaten / max(profile.calorieIntakeGoal, 1)
        return HStack(spacing: 18) {
            ZStack {
                ProgressRing(progress: progress, color: .green, lineWidth: 10)
                VStack(spacing: 0) {
                    Text("\(Int(progress * 100))%").font(.headline).contentTransition(.numericText())
                    Text("of goal").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)
            VStack(alignment: .leading, spacing: 6) {
                Text("Nutrition Today").font(.headline)
                Text("\(Int(kcalEaten)) / \(Int(profile.calorieIntakeGoal)) kcal").font(.subheadline)
                HStack(spacing: 12) {
                    macro("Protein", proteinEaten, .cyan); macro("Carbs", c, .yellow); macro("Fat", f, .pink)
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
        let current = weightSeries.last?.value ?? health.weightKg
        let start = profile.startWeightKg > 0 ? profile.startWeightKg : current
        let total = abs(start - profile.targetWeightKg)
        let done = total > 0 ? min(1, abs(start - current) / total) : 0
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Goal", trailing: profile.targetDate.formatted(date: .abbreviated, time: .omitted))
            Text("Reach \(profile.targetWeightKg.clean) kg").font(.subheadline)
            ProgressView(value: done).tint(theme.current.accent)
            Text("Now \(current.clean) kg · \(Int(done * 100))% there").font(.caption).foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private var exploreRow: some View {
        HStack(spacing: 12) {
            exploreButton("Trends", "chart.xyaxis.line", .indigo) { showTrends = true }
            exploreButton("Achievements", "trophy.fill", .yellow) { showAchievements = true }
        }
    }

    private func exploreButton(_ title: String, _ icon: String, _ color: Color, _ tap: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); tap() } label: {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.subheadline.bold())
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .glassCard(cornerRadius: 18, padding: 14)
        }
        .buttonStyle(PressStyle())
    }

    private func pushWidget() {
        WidgetSync.push(TodaySnapshot(
            steps: health.steps, stepGoal: profile.stepGoal,
            activeCalories: health.activeCalories, calorieGoal: profile.activeCalorieGoal,
            exerciseMinutes: todayMinutes, exerciseGoal: profile.exerciseMinuteGoal,
            waterLitres: waterL, waterGoal: profile.waterGoalLitres,
            caloriesEaten: kcalEaten, calorieIntakeGoal: profile.calorieIntakeGoal,
            updated: .now))
    }
}

struct InsightCard: View {
    let insight: Insight
    let onAction: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: insight.icon).font(.headline).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(insight.color.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(insight.title).font(.subheadline.bold()).lineLimit(2)
            }
            Text(insight.message).font(.caption).foregroundStyle(.secondary).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let label = insight.actionLabel {
                Button(action: onAction) { Text(label).font(.caption.bold()) }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.small).tint(insight.color)
            }
        }
        .frame(minHeight: 132, alignment: .topLeading)
        .glassCard(cornerRadius: 20, padding: 14)
    }
}
