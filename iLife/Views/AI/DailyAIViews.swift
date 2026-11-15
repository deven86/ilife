import SwiftUI
import SwiftData
import Charts

// MARK: - Home cards

/// Today's AI plan and review on Home. Shows nothing heavy when AI mode is off.
struct AIDailyCard: View {
    @ObservedObject private var ai = AIService.shared
    @ObservedObject private var coach = AICoordinator.shared
    @EnvironmentObject var theme: ThemeManager

    private var eveningOrLater: Bool { Calendar.current.component(.hour, from: .now) >= 18 }

    var body: some View {
        if !ai.isOn {
            NavigationLink { AISettingsView() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.title3).foregroundStyle(theme.current.gradient)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Turn on AI mode").font(.subheadline.bold())
                        Text("A plan every morning and a full review every night, written from your own data.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .glassCard()
            }
            .buttonStyle(PressStyle())
        } else {
            VStack(spacing: 12) {
                planCard
                if coach.review != nil || eveningOrLater || coach.working == "night" { reviewCard }
                if let e = coach.error {
                    Text(e).font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder private var planCard: some View {
        if let b = coach.brief {
            NavigationLink { BriefView(brief: b, day: .now) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Today's plan", systemImage: "sun.max.fill").font(.caption.bold()).foregroundStyle(theme.current.gradient)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(b.headline ?? "Your plan is ready").font(.headline).multilineTextAlignment(.leading)
                    ForEach(Array((b.priorities ?? []).prefix(3).enumerated()), id: \.offset) { i, p in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1)").font(.caption2.bold()).foregroundStyle(.white).frame(width: 18, height: 18).background(theme.current.gradient, in: Circle())
                            Text(p).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        }
                    }
                }
                .glassCard()
            }
            .buttonStyle(PressStyle())
        } else {
            HStack(spacing: 12) {
                Image(systemName: "sun.max.fill").font(.title3).foregroundStyle(theme.current.gradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's plan").font(.subheadline.bold())
                    Text(coach.working == "morning" ? "Writing your plan from yesterday's data…" : "Meals, workout, supplements and priorities for today.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if coach.working == "morning" { ProgressView() }
                else { Button("Get plan") { Task { await coach.generateMorning() } }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.small).disabled(coach.working != nil) }
            }
            .glassCard()
        }
    }

    @ViewBuilder private var reviewCard: some View {
        if let r = coach.review {
            NavigationLink { ReviewView(review: r, stats: coach.reviewStats, day: .now) } label: {
                HStack(spacing: 14) {
                    ScoreRing(score: r.overallScore?.value, size: 58, lineWidth: 7)
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Day review", systemImage: "moon.stars.fill").font(.caption.bold()).foregroundStyle(theme.current.gradient)
                        Text(r.headline ?? "Your review is ready").font(.subheadline.bold()).multilineTextAlignment(.leading).lineLimit(3)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .glassCard()
            }
            .buttonStyle(PressStyle())
        } else {
            HStack(spacing: 12) {
                Image(systemName: "moon.stars.fill").font(.title3).foregroundStyle(theme.current.gradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day review").font(.subheadline.bold())
                    Text(coach.working == "night" ? "Reviewing your day, from sleep to workout…" : "Finish logging today, then get your full review.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if coach.working == "night" { ProgressView() }
                else { Button("Review") { Task { await coach.generateNight(for: .now) } }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.small).disabled(coach.working != nil) }
            }
            .glassCard()
        }
    }
}

struct ScoreRing: View {
    let score: Double?
    var size: CGFloat = 54
    var lineWidth: CGFloat = 6
    var label: String? = nil

    private var color: Color {
        guard let score else { return .gray }
        return score >= 80 ? .green : score >= 60 ? .yellow : score >= 40 ? .orange : .red
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                ProgressRing(progress: (score ?? 0) / 100, color: color, lineWidth: lineWidth)
                Text(score.map { "\(Int($0))" } ?? "–").font(.system(size: size * 0.32, weight: .bold, design: .rounded))
            }
            .frame(width: size, height: size)
            if let label { Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}

// MARK: - Tip cards used on every tab

enum AIArea { case nutrition, fitness, supplements, health }

struct AITipCard: View {
    let area: AIArea
    @ObservedObject private var ai = AIService.shared
    @ObservedObject private var coach = AICoordinator.shared
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var session: WorkoutSessionController

    var body: some View {
        if ai.isOn, let b = coach.brief {
            switch area {
            case .nutrition: nutrition(b)
            case .fitness: fitness(b)
            case .supplements: section("Supplements today", "pills.fill", b.supplements)
            case .health:
                VStack(spacing: 12) {
                    section("Body & progress", "figure.arms.open", b.health)
                    section("Recovery", "bed.double.fill", b.recovery)
                }
            }
        }
    }

    private func header(_ title: String, _ icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).font(.headline)
            Spacer()
            Label("AI", systemImage: "sparkles").font(.caption2.bold()).foregroundStyle(theme.current.gradient)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ icon: String, _ s: BriefSection?) -> some View {
        if let s, (s.summary?.isEmpty == false) || !(s.tips ?? []).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                header(title, icon)
                if let sum = s.summary, !sum.isEmpty { Text(sum).font(.subheadline) }
                ForEach(s.tips ?? [], id: \.self) { tip in
                    Label(tip, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                }
            }
            .glassCard()
        }
    }

    @ViewBuilder
    private func nutrition(_ b: MorningBrief) -> some View {
        VStack(spacing: 12) {
            section("Nutrition today", "fork.knife", b.nutrition)
            if let meals = b.meals, !meals.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    header("High-protein ideas for today", "frying.pan.fill")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(meals) { m in
                                NavigationLink { RecipeView(recipe: m) } label: { RecipeTile(recipe: m) }.buttonStyle(PressStyle())
                            }
                        }
                    }
                }
                .glassCard()
            }
        }
    }

    @ViewBuilder
    private func fitness(_ b: MorningBrief) -> some View {
        if let w = b.workout, !(w.exercises ?? []).isEmpty || w.title != nil {
            VStack(alignment: .leading, spacing: 8) {
                header("Suggested for today", "figure.strengthtraining.traditional")
                Text(w.title ?? "Workout").font(.title3.bold())
                if let why = w.why { Text(why).font(.caption).foregroundStyle(.secondary) }
                ForEach(w.exercises ?? []) { ex in
                    HStack(spacing: 10) {
                        ItemThumbnail.exercise(ex.name, size: 36, corner: 8)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(ex.name).font(.subheadline)
                            if let n = ex.note, !n.isEmpty { Text(n).font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text([ex.sets?.value, ex.reps?.value].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " × ")).font(.caption.bold())
                    }
                }
                if !(w.exercises ?? []).isEmpty {
                    Button {
                        Haptics.thump()
                        session.start(name: w.title ?? "Today's workout", category: "Strength", exercises: (w.exercises ?? []).map(\.name))
                    } label: {
                        Label("Start this workout" + (w.durationMinutes.map { " · \(Int($0.value)) min" } ?? ""), systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).disabled(session.isActive)
                }
            }
            .glassCard()
        }
    }
}

struct RecipeTile: View {
    let recipe: Recipe
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ItemThumbnail(photo: nil, illustration: .food(recipe.name), size: 150, corner: 14)
                .frame(height: 84).clipped().clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(recipe.mealType ?? "Meal").font(.caption2.bold()).foregroundStyle(.tint)
            Text(recipe.name).font(.subheadline.bold()).foregroundStyle(Color.primary).lineLimit(2).multilineTextAlignment(.leading)
            Text("\(Int(recipe.protein?.value ?? 0)) g protein · \(Int(recipe.calories?.value ?? 0)) kcal").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 150, alignment: .leading)
    }
}

// MARK: - Recipe

struct RecipeView: View {
    let recipe: Recipe
    @Environment(\.modelContext) private var context
    @State private var meal = MealType.suggested()
    @State private var logged = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.mealType ?? "Meal").font(.caption.bold()).foregroundStyle(.tint)
                    Text(recipe.name).font(.title2.bold())
                    if let why = recipe.why { Text(why).font(.subheadline).foregroundStyle(.secondary) }
                    HStack {
                        macro("\(Int(recipe.calories?.value ?? 0))", "kcal"); Spacer()
                        macro("\(Int(recipe.protein?.value ?? 0)) g", "protein"); Spacer()
                        macro("\(Int(recipe.carbs?.value ?? 0)) g", "carbs"); Spacer()
                        macro("\(Int(recipe.fat?.value ?? 0)) g", "fat")
                        if let t = recipe.prepMinutes?.value, t > 0 { Spacer(); macro("\(Int(t))", "min") }
                    }
                }
                .glassCard()

                if let items = recipe.ingredients, !items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ingredients").font(.headline)
                        ForEach(items, id: \.self) { Label($0, systemImage: "circle.fill").labelStyle(BulletLabel()) }
                    }
                    .glassCard()
                }
                if let steps = recipe.steps, !steps.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Method").font(.headline)
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white).frame(width: 22, height: 22).background(.tint, in: Circle())
                                Text(s).font(.subheadline)
                            }
                        }
                    }
                    .glassCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Picker("Log as", selection: $meal) { ForEach(MealType.allCases) { Text($0.title).tag($0) } }
                    Button {
                        let e = FoodEntry(name: recipe.name, meal: meal, calories: recipe.calories?.value ?? 0, protein: recipe.protein?.value ?? 0,
                                          carbs: recipe.carbs?.value ?? 0, fat: recipe.fat?.value ?? 0, quantity: "1 serving")
                        context.insert(e)
                        try? context.save()
                        Task { await HealthKitManager.shared.saveFood(e) }
                        logged = true
                        Haptics.success()
                    } label: {
                        Label(logged ? "Logged" : "I ate this — log it", systemImage: logged ? "checkmark" : "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).disabled(logged)
                    Text("Macros are AI estimates for one serving as written.").font(.caption2).foregroundStyle(.secondary)
                }
                .glassCard()
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Recipe")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func macro(_ v: String, _ l: String) -> some View {
        VStack(spacing: 0) { Text(v).font(.headline); Text(l).font(.caption2).foregroundStyle(.secondary) }
    }
}

struct BulletLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            configuration.icon.font(.system(size: 5)).foregroundStyle(.secondary).padding(.top, 7)
            configuration.title.font(.subheadline)
        }
    }
}

// MARK: - Morning plan

struct BriefView: View {
    let brief: MorningBrief
    let day: Date
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(day.formatted(date: .complete, time: .omitted).uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
                    Text(brief.headline ?? "Today's plan").font(.title3.bold())
                    ForEach(Array((brief.priorities ?? []).enumerated()), id: \.offset) { i, p in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white).frame(width: 22, height: 22).background(theme.current.gradient, in: Circle())
                            Text(p).font(.subheadline)
                        }
                    }
                }
                .glassCard().appear(0)

                AITipCardStatic(title: "Nutrition", icon: "fork.knife", section: brief.nutrition).appear(1)
                if let meals = brief.meals, !meals.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("High-protein meals", systemImage: "frying.pan.fill").font(.headline)
                        ForEach(meals) { m in
                            NavigationLink { RecipeView(recipe: m) } label: {
                                HStack(spacing: 12) {
                                    ItemThumbnail.food(m.name, size: 52, corner: 12)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.mealType ?? "Meal").font(.caption2.bold()).foregroundStyle(.tint)
                                        Text(m.name).font(.subheadline.bold()).foregroundStyle(Color.primary).multilineTextAlignment(.leading)
                                        Text("\(Int(m.protein?.value ?? 0)) g protein · \(Int(m.calories?.value ?? 0)) kcal").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .glassCard().appear(2)
                }
                if let w = brief.workout {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Workout", systemImage: "figure.strengthtraining.traditional").font(.headline)
                        Text(w.title ?? "Today's session").font(.subheadline.bold())
                        if let why = w.why { Text(why).font(.caption).foregroundStyle(.secondary) }
                        ForEach(w.exercises ?? []) { ex in
                            HStack {
                                Text(ex.name).font(.subheadline)
                                Spacer()
                                Text([ex.sets?.value, ex.reps?.value].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " × ")).font(.caption.bold())
                            }
                        }
                        Text("Start it from the Fitness tab.").font(.caption2).foregroundStyle(.secondary)
                    }
                    .glassCard().appear(3)
                }
                AITipCardStatic(title: "Supplements", icon: "pills.fill", section: brief.supplements).appear(4)
                AITipCardStatic(title: "Recovery", icon: "bed.double.fill", section: brief.recovery).appear(5)
                AITipCardStatic(title: "Body & progress", icon: "figure.arms.open", section: brief.health).appear(6)
                Text("Written by AI from your iLife data. General fitness guidance, not medical advice.").font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Today's Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ShareMenuButton(name: "Plan \(day.formatted(date: .numeric, time: .omitted))") { BriefShareCard(brief: brief, day: day) } }
    }
}

struct AITipCardStatic: View {
    let title: String
    let icon: String
    let section: BriefSection?
    var body: some View {
        if let s = section, (s.summary?.isEmpty == false) || !(s.tips ?? []).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon).font(.headline)
                if let sum = s.summary, !sum.isEmpty { Text(sum).font(.subheadline) }
                ForEach(s.tips ?? [], id: \.self) { Label($0, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
            }
            .glassCard()
        }
    }
}

// MARK: - Night review

struct ReviewView: View {
    let review: NightReview
    let stats: DayStats?
    let day: Date
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 12) {
                    Text(day.formatted(date: .complete, time: .omitted).uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
                    ScoreRing(score: review.overallScore?.value, size: 120, lineWidth: 12)
                    Text(review.headline ?? "Day review").font(.headline).multilineTextAlignment(.center)
                    if let sc = review.scores {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                            ScoreRing(score: sc.sleep?.value, label: "Sleep")
                            ScoreRing(score: sc.activity?.value, label: "Activity")
                            ScoreRing(score: sc.nutrition?.value, label: "Nutrition")
                            ScoreRing(score: sc.hydration?.value, label: "Hydration")
                            ScoreRing(score: sc.supplements?.value, label: "Supplements")
                            ScoreRing(score: sc.recovery?.value, label: "Recovery")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .glassCard().appear(0)

                bullets("What went well", "hand.thumbsup.fill", .green, review.wentWell).appear(1)
                bullets("What to improve", "arrow.up.forward.circle.fill", .orange, review.improve).appear(2)

                ForEach(review.sections ?? []) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.title).font(.headline)
                        Text(s.text).font(.subheadline)
                    }
                    .glassCard()
                }

                if let st = stats {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Your week in charts", systemImage: "chart.bar.fill").font(.headline)
                        if let t = review.trends, !t.isEmpty { Text(t).font(.subheadline) }
                        WeekChart(title: "Steps", values: st.steps7, end: st.day, color: .cyan, goal: st.stepGoal)
                        WeekChart(title: "Sleep (h)", values: st.sleep7, end: st.day, color: .indigo, goal: 8)
                        WeekChart(title: "Calories eaten", values: st.kcal7, end: st.day, color: .red, goal: st.kcalGoal)
                        WeekChart(title: "Protein (g)", values: st.protein7, end: st.day, color: .yellow, goal: st.proteinGoal)
                        WeekChart(title: "Active energy (kcal)", values: st.active7, end: st.day, color: .orange, goal: 0)
                        WeekChart(title: "Workout time (min)", values: st.workoutMin7, end: st.day, color: .green, goal: 0)
                    }
                    .glassCard()
                } else if let t = review.trends, !t.isEmpty {
                    VStack(alignment: .leading, spacing: 6) { Text("Trends").font(.headline); Text(t).font(.subheadline) }.glassCard()
                }

                bullets("Tomorrow", "sunrise.fill", theme.current.accent, review.tomorrow)
                Text("Written by AI from your iLife data. General fitness guidance, not medical advice.").font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Day Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ShareMenuButton(name: "Day review \(day.formatted(date: .numeric, time: .omitted))") { ReviewShareCard(review: review, stats: stats, day: day) } }
    }

    @ViewBuilder
    private func bullets(_ title: String, _ icon: String, _ color: Color, _ items: [String]?) -> some View {
        if let items, !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
                ForEach(items, id: \.self) { Label($0, systemImage: "circle.fill").labelStyle(BulletLabel()) }
            }
            .glassCard()
        }
    }
}

struct WeekChart: View {
    let title: String
    let values: [Double]
    let end: Date
    let color: Color
    let goal: Double

    private var points: [DayValue] {
        let cal = Calendar.current
        return values.enumerated().map { i, v in DayValue(date: cal.date(byAdding: .day, value: i - (values.count - 1), to: end) ?? end, value: v) }
    }

    var body: some View {
        if values.contains(where: { $0 > 0 }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.bold()).foregroundStyle(.secondary)
                Chart {
                    ForEach(points) { p in
                        BarMark(x: .value("Day", p.date, unit: .day), y: .value(title, p.value))
                            .foregroundStyle(Calendar.current.isDate(p.date, inSameDayAs: end) ? color : color.opacity(0.45)).cornerRadius(4)
                    }
                    if goal > 0 {
                        RuleMark(y: .value("Goal", goal)).foregroundStyle(.white.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .frame(height: 90)
            }
        }
    }
}

// MARK: - History

struct AIHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DailyReview.day, order: .reverse) private var all: [DailyReview]

    private var days: [Date] {
        var seen = Set<Date>()
        return all.map { Calendar.current.startOfDay(for: $0.day) }.filter { seen.insert($0).inserted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if all.isEmpty {
                    ContentUnavailableView("No reviews yet", systemImage: "clock.arrow.circlepath",
                                           description: Text("Every morning plan and night review is saved here automatically."))
                        .glassCard()
                }
                ForEach(Array(days.enumerated()), id: \.element) { i, day in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(day.formatted(date: .complete, time: .omitted)).font(.headline)
                        ForEach(all.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }.sorted { $0.kind < $1.kind }) { r in
                            NavigationLink { destination(r) } label: {
                                HStack(spacing: 12) {
                                    if r.kind == "night" { ScoreRing(score: r.overallScore > 0 ? Double(r.overallScore) : nil, size: 42, lineWidth: 5) }
                                    else { Image(systemName: "sun.max.fill").font(.title2).foregroundStyle(.yellow).frame(width: 42) }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.kind == "night" ? "Day review" : "Morning plan").font(.caption.bold()).foregroundStyle(.tint)
                                        Text(r.headline).font(.subheadline).foregroundStyle(Color.primary).multilineTextAlignment(.leading).lineLimit(3)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { context.delete(r); try? context.save() } }
                        }
                    }
                    .glassCard().appear(min(i, 8))
                }
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("AI History")
    }

    @ViewBuilder
    private func destination(_ r: DailyReview) -> some View {
        if r.kind == "night", let review = try? JSONDecoder().decode(NightReview.self, from: Data(r.payload.utf8)) {
            ReviewView(review: review, stats: try? JSONDecoder().decode(DayStats.self, from: Data(r.stats.utf8)), day: r.day)
        } else if let brief = try? JSONDecoder().decode(MorningBrief.self, from: Data(r.payload.utf8)) {
            BriefView(brief: brief, day: r.day)
        } else {
            Text("This entry couldn't be opened.").foregroundStyle(.secondary)
        }
    }
}
