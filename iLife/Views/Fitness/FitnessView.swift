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

    private var weekLogs: [WorkoutLog] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now))!
        return logs.filter { $0.start >= start }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: $tab) {
                    Text("History").tag(0); Text("Plans").tag(1)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    Button { showQuickStart = true } label: { Label("Start Workout", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(session.isActive)
                    Button { showLog = true } label: { Label("Log Past", systemImage: "plus").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).controlSize(.large)
                }

                if tab == 0 { history } else { plansList }
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Fitness")
        .refreshable { await health.importWorkouts(into: context, notify: false) }
        .sheet(isPresented: $showQuickStart) { QuickStartSheet() }
        .sheet(isPresented: $showLog) { LogWorkoutSheet() }
        .sheet(isPresented: $showNewPlan) { PlanEditorView(plan: nil) }
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
            ForEach(logs.prefix(50)) { log in
                WorkoutRow(log: log)
                    .contextMenu { Button("Delete", role: .destructive) { context.delete(log) } }
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
                                  exercises: plan.orderedExercises.map(\.name))
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
                Text(log.name).font(.headline)
                Text(log.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                Label(log.source, systemImage: log.source == "iLife" ? "app.fill" : "applewatch").font(.caption2).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 8) {
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
            Text(plan.orderedExercises.prefix(5).map(\.name).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
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

struct LogWorkoutSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Strength Training"
    @State private var category = "Strength"
    @State private var start = Date.now.addingTimeInterval(-3600)
    @State private var minutes = 45.0
    @State private var calories = 300.0
    @State private var notes = ""
    @State private var sets: [(String, Int, Double)] = []
    @State private var newExercise = ""
    @State private var newReps = 10
    @State private var newWeight = 20.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $category) {
                        ForEach(["Strength", "Cardio", "HIIT", "Yoga", "Running", "Walking", "Cycling"], id: \.self) { Text($0) }
                    }
                    DatePicker("Started", selection: $start)
                    Stepper("Duration: \(Int(minutes)) min", value: $minutes, in: 1...300, step: 5)
                    Stepper("Calories: \(Int(calories)) kcal", value: $calories, in: 0...3000, step: 10)
                }
                Section("Sets (optional)") {
                    ForEach(sets.indices, id: \.self) { i in
                        Text("\(sets[i].0) — \(sets[i].1) reps × \(sets[i].2.clean) kg")
                    }
                    TextField("Exercise", text: $newExercise)
                    Stepper("Reps: \(newReps)", value: $newReps, in: 1...100)
                    Stepper("Weight: \(newWeight.clean) kg", value: $newWeight, in: 0...400, step: 2.5)
                    Button("Add set") {
                        guard !newExercise.isEmpty else { return }
                        sets.append((newExercise, newReps, newWeight))
                    }
                }
                Section("Notes") { TextField("How did it feel?", text: $notes, axis: .vertical) }
            }
            .navigationTitle("Log Workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let log = WorkoutLog(name: name, category: category, start: start, durationMinutes: minutes, calories: calories)
                        log.notes = notes
                        context.insert(log)
                        for (i, s) in sets.enumerated() {
                            let set = ExerciseSet(exercise: s.0, reps: s.1, weightKg: s.2, order: i)
                            set.log = log
                            context.insert(set)
                        }
                        try? context.save()
                        Task { await HealthKitManager.shared.saveWorkout(log, activity: .from(category: category)) }
                        dismiss()
                    }
                }
            }
        }
    }
}
