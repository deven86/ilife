import SwiftUI
import SwiftData
import Charts

struct FitnessView: View {
    @EnvironmentObject var session: WorkoutSessionController
    @EnvironmentObject var health: HealthKitManager
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @Query(sort: \WorkoutPlan.created) private var plans: [WorkoutPlan]

    @State private var tab = 0
    @State private var showQuickStart = false
    @State private var showLog = false
    @State private var editingPlan: WorkoutPlan?
    @State private var showNewPlan = false
    @State private var editingLog: WorkoutLog?

    private var weekLogs: [WorkoutLog] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now))!
        return logs.filter { $0.start >= start }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: $tab) {
                    Text("History").tag(0); Text("Plans").tag(1); Text("Gym").tag(2)
                }
                .pickerStyle(.segmented)

                if tab != 2 {
                HStack(spacing: 12) {
                    Button { showQuickStart = true } label: { Label("Start Workout", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(session.isActive)
                    Button { showLog = true } label: { Label("Log Past", systemImage: "plus").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).controlSize(.large)
                }
                }

                switch tab {
                case 0: history
                case 1: plansList
                default: GymSection()
                }
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Fitness")
        .refreshable { await health.importWorkouts(into: context, notify: false) }
        .sheet(isPresented: $showQuickStart) { QuickStartSheet() }
        .sheet(isPresented: $showLog) { WorkoutEditorView(log: nil) }
        .sheet(isPresented: $showNewPlan) { PlanEditorView(plan: nil) }
        .sheet(item: $editingLog) { WorkoutEditorView(log: $0) }
        .sheet(item: $editingPlan) { PlanEditorView(plan: $0) }
    }

    // MARK: History

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading) {
                SectionTitle(title: "This Week", trailing: "\(weekLogs.count) sessions · \(Int(weekLogs.reduce(0) { $0 + $1.durationMinutes })) min")
                Chart {
                    ForEach(0..<7, id: \.self) { offset in
                        let day = Calendar.current.date(byAdding: .day, value: offset - 6, to: Calendar.current.startOfDay(for: .now))!
                        let mins = weekLogs.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }.reduce(0) { $0 + $1.durationMinutes }
                        BarMark(x: .value("Day", day, unit: .day), y: .value("Minutes", mins))
                            .foregroundStyle(.tint).cornerRadius(6)
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .frame(height: 140)
            }
            .glassCard()

            if logs.isEmpty {
                ContentUnavailableView("No workouts yet", systemImage: "figure.run",
                                       description: Text("Workouts from Apple Watch and other fitness apps appear here automatically once Apple Health is connected."))
                    .glassCard()
            }
            ForEach(logs.prefix(100)) { log in
                NavigationLink { WorkoutDetailView(log: log) } label: { WorkoutRow(log: log) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editingLog = log }
                        Button("Delete", systemImage: "trash", role: .destructive) { context.delete(log); try? context.save() }
                    }
            }
        }
    }

    // MARK: Plans

    private var plansList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { showNewPlan = true } label: { Label("New Plan", systemImage: "plus.circle.fill") }
            if plans.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Start with ready-made plans").font(.headline)
                    Text("Push / Pull / Legs, Full Body, HIIT and Yoga — edit them any way you like.").font(.caption).foregroundStyle(.secondary)
                    Button("Add starter plans") { PlanTemplates.seed(into: context) }.buttonStyle(.bordered)
                }
                .glassCard()
            }
            ForEach(plans) { plan in
                PlanCard(plan: plan, onEdit: { editingPlan = plan }, onStart: {
                    session.start(name: plan.name, category: plan.focus.contains("HIIT") ? "HIIT" : plan.focus.contains("Yoga") ? "Yoga" : "Strength",
                                  exercises: plan.orderedExercises.map(\.name), photos: plan.orderedExercises.map(\.photo), equipment: plan.orderedExercises.map(\.equipment))
                })
            }
        }
    }
}

struct WorkoutRow: View {
    let log: WorkoutLog
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(.tint)
                .frame(width: 44, height: 44).background(.tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(log.name).font(.headline).lineLimit(1)
                Text(log.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                if !log.exerciseNames.isEmpty {
                    Text(log.exerciseNames.prefix(3).joined(separator: " · ") + (log.exerciseNames.count > 3 ? " +\(log.exerciseNames.count - 3)" : ""))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Label(log.source, systemImage: log.source == "iLife" ? "app.fill" : "applewatch")
                    if log.isPT { Label("PT", systemImage: "person.2.fill").foregroundStyle(.orange) }
                    if !log.exerciseNames.isEmpty { Text("· \(log.orderedSets.count) sets") }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(log.durationMinutes)) min").font(.subheadline.bold())
                Text("\(Int(log.calories)) kcal").font(.caption).foregroundStyle(.orange)
                if log.avgHeartRate > 0 { Text("\(Int(log.avgHeartRate)) bpm").font(.caption2).foregroundStyle(.red) }
            }
        }
        .glassCard(cornerRadius: 18, padding: 12)
    }
    private var icon: String {
        switch log.category {
        case "Strength": "dumbbell.fill"
        case "Mind & Body", "Yoga": "figure.yoga"
        default: "figure.run"
        }
    }
}

struct PlanCard: View {
    let plan: WorkoutPlan
    let onEdit: () -> Void
    let onStart: () -> Void
    private let symbols = Calendar.current.veryShortWeekdaySymbols
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let data = plan.coverPhoto, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(height: 130).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            HStack {
                VStack(alignment: .leading) {
                    Text(plan.name).font(.headline)
                    Text("\(plan.focus) · \(plan.level) · \(plan.estimatedMinutes) min").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onStart) { Image(systemName: "play.fill") }.buttonStyle(.borderedProminent).buttonBorderShape(.circle)
            }
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { d in
                    Text(symbols[d - 1]).font(.caption2.bold()).frame(width: 24, height: 24)
                        .background(plan.weekdays.contains(d) ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(0.1)), in: Circle())
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(plan.orderedExercises) { ex in
                        VStack(spacing: 4) {
                            ItemThumbnail(photo: ex.photo, illustration: .exercise(ex.name, equipment: ex.equipment), size: 60, corner: 12, savedKey: ("exercise", ex.name))
                            Text(ex.name).font(.caption2).lineLimit(2).multilineTextAlignment(.center).frame(width: 68)
                            if !ex.equipment.isEmpty {
                                Text(ex.equipment).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).frame(width: 68)
                            }
                        }
                    }
                }
            }
        }
        .glassCard()
        .onTapGesture(perform: onEdit)
    }
}

struct QuickStartSheet: View {
    @EnvironmentObject var session: WorkoutSessionController
    @Environment(\.dismiss) private var dismiss
    private let types: [(String, String, String)] = [
        ("Strength Training", "Strength", "dumbbell.fill"), ("HIIT", "HIIT", "bolt.heart.fill"),
        ("Running", "Running", "figure.run"), ("Walking", "Walking", "figure.walk"),
        ("Cycling", "Cycling", "figure.outdoor.cycle"), ("Yoga", "Yoga", "figure.yoga"), ("Cardio", "Cardio", "heart.circle.fill")
    ]
    var body: some View {
        NavigationStack {
            List(types, id: \.0) { t in
                Button {
                    session.start(name: t.0, category: t.1, exercises: [])
                    dismiss()
                } label: { Label(t.0, systemImage: t.2) }
            }
            .navigationTitle("Start Workout")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
